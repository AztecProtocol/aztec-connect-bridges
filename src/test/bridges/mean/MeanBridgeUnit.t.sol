// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MeanBridge} from "../../../bridges/mean/MeanBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {MeanErrorLib} from "../../../bridges/mean/MeanErrorLib.sol";
import {MeanSwapIntervalDecodingLib} from "../../../bridges/mean/MeanSwapIntervalDecodingLib.sol";
import {IDCAHub} from "../../../interfaces/mean/IDCAHub.sol";
import {ITransformerRegistry} from "../../../interfaces/mean/ITransformerRegistry.sol";

contract MeanBridgeUnitTest is Test {
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant DAI_WRAPPER = IERC20(0x4169Df1B7820702f566cc10938DA51F6F597d264);
    address public constant OWNER = 0x0000000000000000000000000000000000000001;
    IDCAHub public constant DCA_HUB = IDCAHub(0x0000000000000000000000000000000000000002);
    ITransformerRegistry public constant TRANSFORMER_REGISTRY = ITransformerRegistry(0x0000000000000000000000000000000000000003);

    AztecTypes.AztecAsset internal emptyAsset;

    address private rollupProcessor;
    MeanBridge private bridge;

    event NewWrappersSupported(address[] wrappers);

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        // Deploy a new example bridge
        bridge = new MeanBridge(DCA_HUB, TRANSFORMER_REGISTRY, OWNER, rollupProcessor);
        vm.label(address(bridge), "MEAN_BRIDGE");
        vm.deal(address(bridge), 0);

        // Some more labels
        vm.label(address(DAI), "DAI");
        vm.label(address(DCA_HUB), "DCA_HUB");
        vm.label(address(TRANSFORMER_REGISTRY), "TRANSFORMER_REGISTRY");
        vm.label(address(OWNER), "OWNER");
    }

    function testSetup() public {
        assertEq(address(bridge.DCA_HUB()), address(DCA_HUB));
        assertEq(address(bridge.TRANSFORMER_REGISTRY()), address(TRANSFORMER_REGISTRY));
        assertEq(bridge.owner(), OWNER);
        assertEq(bridge.getWrapperId(address(DAI_WRAPPER)), 0);
    }

    function testMaxApprove() public {
        IERC20[] memory _tokens = new IERC20[](1);
        _tokens[0] = DAI;
        bridge.maxApprove(_tokens);
        assertEq(DAI.allowance(address(bridge), address(DCA_HUB)), type(uint256).max);
        assertEq(DAI.allowance(address(bridge), address(TRANSFORMER_REGISTRY)), type(uint256).max);
        assertEq(DAI.allowance(address(bridge), rollupProcessor), type(uint256).max);
    }

    function testRevertsWhenRegisteringWrapperThatIsNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeanErrorLib.TokenNotAllowed.selector, 
                DAI_WRAPPER
            )
        );
        
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(DAI_WRAPPER);
        _mockIsTokenAllowed(DAI_WRAPPER, false);
        bridge.registerWrappers(_tokens);
    }

    function testRevertsWhenRegisteringWrapperThatWasAlreadyRegistered() public {        
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(DAI_WRAPPER);
        _mockIsTokenAllowed(DAI_WRAPPER, true);
        bridge.registerWrappers(_tokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                MeanErrorLib.TokenAlreadyRegistered.selector, 
                DAI_WRAPPER
            )
        );
        bridge.registerWrappers(_tokens);
    }

    function testRegisterWrappers() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(DAI_WRAPPER);
        
        vm.expectEmit(true, false, false, false, address(bridge));
        emit NewWrappersSupported(_tokens);
        
        _mockIsTokenAllowed(DAI_WRAPPER, true);
        bridge.registerWrappers(_tokens);
        
        assertEq(DAI_WRAPPER.allowance(address(bridge), address(DCA_HUB)), type(uint256).max);
        assertEq(DAI_WRAPPER.allowance(address(bridge), address(TRANSFORMER_REGISTRY)), type(uint256).max);
        assertEq(bridge.getWrapperId(address(DAI_WRAPPER)), 1);
    }

    function testComputeCriteriaWithERC20s(address _from, address _to, uint24 _amountOfSwaps, uint8 _swapIntervalCode) public {
        vm.assume(_swapIntervalCode < 8);
        uint64 _auxData = _buildAuxData(_amountOfSwaps, _swapIntervalCode);

        uint256 _actual = bridge.computeCriteria(
            _erc20Asset(_from),
            emptyAsset, 
            _erc20Asset(_to),
            emptyAsset, 
            _auxData
        );
        uint256 _expected = _criteriaFor(_from, _to, _amountOfSwaps, _swapIntervalCode);
        assertEq(_actual, _expected);
    }        

    function testComputeCriteriaWithEthAsFromAndWrapperAsTo(uint24 _amountOfSwaps, uint8 _swapIntervalCode) public {
        vm.assume(_swapIntervalCode < 8);
        _registerDAIWrapper();

        uint64 _auxData = _buildAuxData(_amountOfSwaps, _swapIntervalCode, 0, 1);
        uint256 _actual = bridge.computeCriteria(
            _ethAsset(),
            emptyAsset, 
            _erc20Asset(address(DAI)),
            emptyAsset, 
            _auxData
        );
        uint256 _expected = _criteriaFor(address(WETH), address(DAI_WRAPPER), _amountOfSwaps, _swapIntervalCode);
        assertEq(_actual, _expected);
    }

    function testComputeCriteriaWithWrapperAsFromAndEthAsTo(uint24 _amountOfSwaps, uint8 _swapIntervalCode) public {
        vm.assume(_swapIntervalCode < 8);
        _registerDAIWrapper();

        uint64 _auxData = _buildAuxData(_amountOfSwaps, _swapIntervalCode, 1, 0);
        uint256 _actual = bridge.computeCriteria(
            _erc20Asset(address(DAI)),
            emptyAsset, 
            _ethAsset(),
            emptyAsset, 
            _auxData
        );
        uint256 _expected = _criteriaFor(address(DAI_WRAPPER), address(WETH), _amountOfSwaps, _swapIntervalCode);
        assertEq(_actual, _expected);
    }

    function testComputeCriteriaForPosition(address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) public {
        uint256 _expected = uint256(keccak256(abi.encodePacked(_from, _to, _amountOfSwaps, _swapInterval)));
        uint256 _actual = bridge.computeCriteriaForPosition(_from, _to, _amountOfSwaps, _swapInterval);
        assertEq(_actual, _expected);
    }

    function _mockIsTokenAllowed(IERC20 _token, bool _isAllowed) internal {
        vm.mockCall(
            address(DCA_HUB),
            abi.encodeWithSelector(
                DCA_HUB.allowedTokens.selector,
                address(_token)
            ),
            abi.encode(_isAllowed)
        );
    }

    function _registerDAIWrapper() internal {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(DAI_WRAPPER);
        _mockIsTokenAllowed(DAI_WRAPPER, true);
        bridge.registerWrappers(_tokens);
    }

    function _criteriaFor(address _from, address _to, uint32 _amountOfSwaps, uint8 _swapIntervalCode) internal view returns (uint256) {
        return bridge.computeCriteriaForPosition(_from, _to, _amountOfSwaps, MeanSwapIntervalDecodingLib.calculateSwapInterval(_swapIntervalCode));
    }

    function _erc20Asset(address _token) internal pure returns(AztecTypes.AztecAsset memory _asset) {
        _asset.assetType = AztecTypes.AztecAssetType.ERC20;
        _asset.erc20Address = _token;
    }

    function _ethAsset()internal pure returns(AztecTypes.AztecAsset memory _asset) {
        _asset.assetType = AztecTypes.AztecAssetType.ETH;
    }

    function _buildAuxData(uint24 _amountOfSwaps, uint8 _swapIntervalCode) internal pure returns (uint64) {
        return _buildAuxData(_amountOfSwaps, _swapIntervalCode, 0, 0);
    }

    function _buildAuxData(uint24 _amountOfSwaps, uint8 _swapIntervalCode, uint16 _wrapperIdFrom, uint16 _wrapperIdTo) internal pure returns (uint64) {
        return _amountOfSwaps 
            + (uint64(_swapIntervalCode) << 24) 
            + (uint64(_wrapperIdFrom) << 32) 
            + (uint64(_wrapperIdTo) << 48);
    }

}

    
