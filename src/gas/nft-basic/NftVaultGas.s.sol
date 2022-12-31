// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";
import {AddressRegistryDeployment} from "../../deployment/registry/AddressRegistryDeployment.s.sol";
import {NftVault} from "../../bridges/nft-basic/NftVault.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {NftVaultDeployment} from "../../deployment/nft-basic/NftVaultDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

import {ERC721PresetMinterPauserAutoId} from
    "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract NftVaultGas is NftVaultDeployment {
    GasBase internal gasBase;
    NftVault internal bridge;
    NftVault internal bridge2;
    ERC721PresetMinterPauserAutoId internal nftContract;
    address internal registry;
    uint256 internal registryAddressId;

    AztecTypes.AztecAsset private empty;
    AztecTypes.AztecAsset private eth =
        AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
    AztecTypes.AztecAsset private virtualAsset =
        AztecTypes.AztecAsset({id: 100, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private virtualAsset128 =
        AztecTypes.AztecAsset({id: 128, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

    function measure() public {
        uint256 privKey1 = vm.envUint("PRIVATE_KEY");
        address addr1 = vm.addr(privKey1);

        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.startBroadcast();
        gasBase = new GasBase(defiProxy);
        nftContract = new ERC721PresetMinterPauserAutoId("test", "NFT", "");
        nftContract.mint(addr1);
        vm.stopBroadcast();

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        registry = deployAndListAddressRegistry();
        address bridge = deployAndList(registry);
        address bridge2 = deployAndList(registry);
        ROLLUP_PROCESSOR = temp;

        vm.startBroadcast();
        address(gasBase).call{value: 4 ether}("");

        _registerAddress(addr1);
        _registerAddress(bridge);
        _registerAddress(bridge2);

        nftContract.approve(address(bridge), 0);
        vm.stopBroadcast();

        // Get virtual assets
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, virtualAsset, empty, 1, 0, 0, address(0), 400000);
        }
        // deposit nft
        {
            vm.broadcast();
            NftVault(bridge).transferFromAndMatch(virtualAsset.id, address(nftContract), 0);
        }
        // transfer nft
        {
            vm.broadcast();
            gasBase.convert(bridge, virtualAsset, empty, virtualAsset128, empty, 1, 128, 2, address(0), 400000);
        }
        // withdraw nft
        {
            vm.broadcast();
            gasBase.convert(bridge2, virtualAsset128, empty, eth, empty, 1, 0, 0, address(0), 400000);
        }
    }

    function _registerAddress(address _toRegister) internal {
        // get registry virtual asset
        gasBase.convert(address(registry), eth, empty, virtualAsset, empty, 1, 0, 0, address(0), 400000);
        // register address
        gasBase.convert(
            address(registry),
            virtualAsset,
            empty,
            virtualAsset,
            empty,
            uint256(uint160(_toRegister)),
            0,
            0,
            address(0),
            400000
        );
    }
}
