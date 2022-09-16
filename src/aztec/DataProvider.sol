// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;
import {AztecTypes} from "./libraries/AztecTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRollupProcessor} from "./interfaces/IRollupProcessor.sol";
import {BridgeBase} from "../bridges/base/BridgeBase.sol";
import {ISubsidy} from "./interfaces/ISubsidy.sol";

/**
 * @notice Helper used for mapping assets and bridges to more meaningful naming
 * @author Aztec Team
 */
contract DataProvider is Ownable {
    struct BridgeData {
        address bridgeAddress;
        uint256 bridgeAddressId;
        string label;
    }

    struct AssetData {
        address assetAddress;
        uint256 assetId;
        string label;
    }

    struct Bridges {
        mapping(uint256 => BridgeData) data;
        mapping(bytes32 => uint256) tagToId;
    }

    struct Assets {
        mapping(uint256 => AssetData) data;
        mapping(bytes32 => uint256) tagToId;
    }

    uint256 private constant INPUT_ASSET_ID_A_SHIFT = 32;
    uint256 private constant INPUT_ASSET_ID_B_SHIFT = 62;
    uint256 private constant OUTPUT_ASSET_ID_A_SHIFT = 92;
    uint256 private constant OUTPUT_ASSET_ID_B_SHIFT = 122;
    uint256 private constant BITCONFIG_SHIFT = 152;
    uint256 private constant AUX_DATA_SHIFT = 184;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG_SHIFT = 29;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG = 0x20000000; // 2 ** 29
    uint256 private constant MASK_THIRTY_TWO_BITS = 0xffffffff;
    uint256 private constant MASK_THIRTY_BITS = 0x3fffffff;
    uint256 private constant MASK_SIXTY_FOUR_BITS = 0xffffffffffffffff;

    ISubsidy public constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    IRollupProcessor public immutable ROLLUP_PROCESSOR;
    Bridges internal bridges;
    Assets internal assets;

    constructor(address _rollupProcessor) {
        ROLLUP_PROCESSOR = IRollupProcessor(_rollupProcessor);
    }

    /**
     * @notice Adds a bridge with a specific tag
     * @dev Only callable by the owner
     * @param _bridgeAddressId The bridge address id for the bridge to list
     * @param _tag The tag to list with the bridge
     */
    function addBridge(uint256 _bridgeAddressId, string memory _tag) public onlyOwner {
        address bridgeAddress = ROLLUP_PROCESSOR.getSupportedBridge(_bridgeAddressId);
        bytes32 digest = keccak256(abi.encode(_tag));
        bridges.tagToId[digest] = _bridgeAddressId;
        bridges.data[_bridgeAddressId] = BridgeData({
            bridgeAddress: bridgeAddress,
            bridgeAddressId: _bridgeAddressId,
            label: _tag
        });
    }

    /**
     * @notice Adds an asset with a specific tag
     * @dev Only callable by the owner
     * @param _assetId The asset id of the asset to list
     * @param _tag The tag to list with the asset
     */
    function addAsset(uint256 _assetId, string memory _tag) public onlyOwner {
        address assetAddress = ROLLUP_PROCESSOR.getSupportedAsset(_assetId);
        bytes32 digest = keccak256(abi.encode(_tag));
        assets.tagToId[digest] = _assetId;
        assets.data[_assetId] = AssetData({assetAddress: assetAddress, assetId: _assetId, label: _tag});
    }

    /**
     * @notice Adds multiple bridges with specific tags
     * @dev Indirectly only callable by the owner
     * @param _assetIds List of asset Ids
     * @param _assetTags List of tags to be used for the asset ids
     * @param _bridgeAddressIds The list of bridge address ids
     * @param _bridgeTags List of tags to be used for the bridges
     */
    function addAssetsAndBridges(
        uint256[] memory _assetIds,
        string[] memory _assetTags,
        uint256[] memory _bridgeAddressIds,
        string[] memory _bridgeTags
    ) public {
        if (_assetIds.length != _assetTags.length || _bridgeAddressIds.length != _bridgeTags.length) {
            revert("Invalid input lengths");
        }
        for (uint256 i = 0; i < _assetTags.length; i++) {
            addAsset(_assetIds[i], _assetTags[i]);
        }
        for (uint256 i = 0; i < _bridgeTags.length; i++) {
            addBridge(_bridgeAddressIds[i], _bridgeTags[i]);
        }
    }

    /**
     * @notice Fetch the `BridgeData` related to a specific bridgeAddressId
     * @param _bridgeAddressId The bridge address id of the bridge to fetch
     * @return The BridgeData data structure for the given bridge
     */
    function getBridge(uint256 _bridgeAddressId) public view returns (BridgeData memory) {
        return bridges.data[_bridgeAddressId];
    }

    /**
     * @notice Fetch the `BridgeData` related to a specific tag
     * @param _tag The tag of the bridge to fetch
     * @return The BridgeData data structure for the given bridge
     */
    function getBridge(string memory _tag) public view returns (BridgeData memory) {
        return bridges.data[bridges.tagToId[keccak256(abi.encode(_tag))]];
    }

    /**
     * @notice Fetch the `AssetData` related to a specific assetId
     * @param _assetId The asset id of the asset to fetch
     * @return The AssetData data structure for the given asset
     */
    function getAsset(uint256 _assetId) public view returns (AssetData memory) {
        return assets.data[_assetId];
    }

    /**
     * @notice Fetch the `AssetData` related to a specific tag
     * @param _tag The tag of the asset to fetch
     * @return The AssetData data structure for the given asset
     */
    function getAsset(string memory _tag) public view returns (AssetData memory) {
        return assets.data[assets.tagToId[keccak256(abi.encode(_tag))]];
    }

    /**
     * @notice Fetch `AssetData` for all supported assets
     * @dev +1 because the Eth base asset is added as well
     * @return A list of AssetData data structures, one for every asset
     */
    function getAssets() public view returns (AssetData[] memory) {
        uint256 assetCount = ROLLUP_PROCESSOR.getSupportedAssetsLength();
        AssetData[] memory assetDatas = new AssetData[](assetCount + 1);
        for (uint256 i = 0; i <= assetCount; i++) {
            assetDatas[i] = getAsset(i);
        }
        return assetDatas;
    }

    /**
     * @notice Fetch `BridgeData` for all supported bridges
     * @return A list of BridgeData data structures, one for every bridge
     */
    function getBridges() public view returns (BridgeData[] memory) {
        uint256 bridgeCount = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        BridgeData[] memory bridgeDatas = new BridgeData[](bridgeCount);
        for (uint256 i = 1; i <= bridgeCount; i++) {
            bridgeDatas[i - 1] = getBridge(i);
        }
        return bridgeDatas;
    }

    /**
     * @notice Fetches the subsidy that can be claimed by the specific call, if it is the next performed.
     * @param _bridgeCallData The bridge call data for a specific bridge interaction
     * @return The amount of eth claimed at the current gas prices
     */
    function getAccumulatedSubsidyAmount(uint256 _bridgeCallData) public view returns (uint256) {
        uint256 bridgeAddressId = _bridgeCallData & MASK_THIRTY_TWO_BITS;
        address bridgeAddress = ROLLUP_PROCESSOR.getSupportedBridge(bridgeAddressId);

        uint256 inputAId = (_bridgeCallData >> INPUT_ASSET_ID_A_SHIFT) & MASK_THIRTY_BITS;
        uint256 inputBId = (_bridgeCallData >> INPUT_ASSET_ID_B_SHIFT) & MASK_THIRTY_BITS;
        uint256 outputAId = (_bridgeCallData >> OUTPUT_ASSET_ID_A_SHIFT) & MASK_THIRTY_BITS;
        uint256 outputBId = (_bridgeCallData >> OUTPUT_ASSET_ID_B_SHIFT) & MASK_THIRTY_BITS;
        uint256 bitconfig = (_bridgeCallData >> BITCONFIG_SHIFT) & MASK_THIRTY_TWO_BITS;
        uint256 auxData = (_bridgeCallData >> AUX_DATA_SHIFT) & MASK_SIXTY_FOUR_BITS;

        AztecTypes.AztecAsset memory inputA = _aztecAsset(inputAId);
        AztecTypes.AztecAsset memory inputB;
        if (bitconfig & 1 == 1) {
            inputB = _aztecAsset(inputBId);
        }

        AztecTypes.AztecAsset memory outputA = _aztecAsset(outputAId);
        AztecTypes.AztecAsset memory outputB;

        if (bitconfig & 2 == 2) {
            outputB = _aztecAsset(outputBId);
        }

        (bool success, bytes memory returnData) = bridgeAddress.staticcall(
            abi.encodeWithSelector(
                BridgeBase.computeCriteria.selector,
                inputA,
                inputB,
                outputA,
                outputB,
                uint64(auxData)
            )
        );

        if (!success) {
            return 0;
        }

        uint256 criteria = abi.decode(returnData, (uint256));

        return SUBSIDY.getAccumulatedSubsidyAmount(bridgeAddress, criteria);
    }

    function _aztecAsset(uint256 _assetId) internal view returns (AztecTypes.AztecAsset memory) {
        if (_assetId >= VIRTUAL_ASSET_ID_FLAG) {
            return
                AztecTypes.AztecAsset({
                    id: _assetId - VIRTUAL_ASSET_ID_FLAG,
                    erc20Address: address(0),
                    assetType: AztecTypes.AztecAssetType.VIRTUAL
                });
        }

        if (_assetId > 0) {
            return
                AztecTypes.AztecAsset({
                    id: _assetId,
                    erc20Address: ROLLUP_PROCESSOR.getSupportedAsset(_assetId),
                    assetType: AztecTypes.AztecAssetType.ERC20
                });
        }

        return AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
    }
}
