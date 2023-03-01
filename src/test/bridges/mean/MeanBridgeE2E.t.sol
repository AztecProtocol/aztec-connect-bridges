// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {console} from "forge-std/console.sol";
import {BridgeTestBase} from "../../aztec/base/BridgeTestBase.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {MeanBridge} from "../../../bridges/mean/MeanBridge.sol";
import {IDCAHub} from "../../../interfaces/mean/IDCAHub.sol";
import {ITransformerRegistry} from "../../../interfaces/mean/ITransformerRegistry.sol";
import {ITransformer} from "../../../interfaces/mean/ITransformer.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {DCAHubSwapperMock} from "./mocks/Swapper.sol";

contract MeanBridgeE2eTest is BridgeTestBase {

    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant YIELD_BEARING_DAI = 0xc4113b7605D691E073c162809060b6C5Ae402F1e;
    address public constant YIELD_BEARING_WETH = 0xd4dE9D2Fc1607d1DF63E1c95ecBfa8d7946f5457;
    address private constant BRIDGE_OWNER = 0x0000000000000000000000000000000000000001;
    address private constant HUB_OWNER = 0xEC864BE26084ba3bbF3cAAcF8F6961A9263319C4;
    address private constant BENEFICIARY = address(11);
    ExtendedHub private constant HUB = ExtendedHub(0xA5AdC5484f9997fBF7D405b9AA62A7d88883C345);
    ITransformerRegistry private constant TRANSFORMER_REGISTRY = ITransformerRegistry(0xC0136591Df365611B1452B5F8823dEF69Ff3A685);
    uint256 private totalShares;
    MeanBridge private bridge;
    DCAHubSwapperMock private swapper;
    uint256 private bridgeId;
    
    function setUp() public {
        bridge = new MeanBridge(IDCAHub(address(HUB)), TRANSFORMER_REGISTRY, BRIDGE_OWNER, address(ROLLUP_PROCESSOR));
        bridge = new MeanBridge(IDCAHub(address(HUB)), TRANSFORMER_REGISTRY, BRIDGE_OWNER, address(ROLLUP_PROCESSOR));

        // Register tokens
        address[] memory _tokens = new address[](4);
        _tokens[0] = DAI;
        _tokens[1] = WETH;
        _tokens[2] = YIELD_BEARING_DAI;
        _tokens[3] = YIELD_BEARING_WETH;
        vm.prank(BRIDGE_OWNER);
        bridge.registerTokens(_tokens);

        totalShares = bridge.VIRTUAL_SHARES_PER_POSITION();

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 600_000);
        bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        swapper = new DCAHubSwapperMock();

        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
        SUBSIDY.registerBeneficiary(BENEFICIARY);

        vm.label(address(bridge), "MeanBridge");
        vm.label(address(HUB), "DCAHub");
        vm.label(address(TRANSFORMER_REGISTRY), "TRANSFORMER_REGISTRY");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(YIELD_BEARING_DAI, "YIELD_BEARING_DAI");
        vm.label(YIELD_BEARING_WETH, "YIELD_BEARING_WETH");        
    }

    function testEthToERC20(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1, uint120(type(int120).max)));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);        

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _inputAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        
        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, 0, _swappedAmount);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);

        // Nothing to claim since pair was not subsidized
        assertEq(SUBSIDY.claimableAmount(BENEFICIARY), 0);
    }    

    function testEthToERC20WithSubsidy(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1, uint120(type(int120).max)));
        _shares = uint128(bound(_shares, 1, totalShares));

        // Setup subsidy
        uint256 _positionCriteria = bridge.computeCriteriaForPosition(MeanBridge.Action.DEPOSIT, WETH, DAI, 1, 1 hours);
        _setUpSubsidy(_positionCriteria);

        // Warp time in order to accumulate claimable subsidy        
        vm.warp(block.timestamp + 1 minutes);

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        _convert(_inputAsset, _auxData, _inputAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        
        // Close position
        _withdraw(_outputAsset, _shares, _auxData);

        // There is something to claim
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0);
    }

    function testYieldToETH(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1 ether, 15 ether));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        address _hubFrom = YIELD_BEARING_DAI;
        address _hubTo = WETH;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);

        // Validate position
        uint256 _depositAmount = _calculateToYieldBearing(YIELD_BEARING_DAI, DAI, _inputAmount);
        _validatePosition(_positionId, _hubFrom, _hubTo, _depositAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        
        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, 0, _swappedAmount);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);
    }

    function testERC20ToYieldETH(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 0.5 ether, 10_000 ether));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(DAI));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        address _hubFrom = DAI;
        address _hubTo = YIELD_BEARING_WETH;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _inputAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        uint256 _swappedUnderlying = _calculateToUnderlying(YIELD_BEARING_WETH, _swappedAmount);

        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, 0, _swappedUnderlying);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);
    }

    function testYieldETHToYieldERC20(uint128 _shares) public {
        uint120 _inputAmount = 1 ether;
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(DAI));
        address _hubFrom = YIELD_BEARING_WETH;
        address _hubTo = YIELD_BEARING_DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);
        uint256 _depositAmount = _calculateToYieldBearing(YIELD_BEARING_WETH, WETH, _inputAmount);

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _depositAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        uint256 _swappedUnderlying = _calculateToUnderlying(YIELD_BEARING_DAI, _swappedAmount);
        
        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, 0, _swappedUnderlying);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);
    }

    function testYieldETHToYieldERC20WithMultipleWithdraws(uint128 _sharesFirstWithdraw) public {
        uint120 _inputAmount = 1 ether;
        _sharesFirstWithdraw = uint128(bound(_sharesFirstWithdraw, 1, totalShares * 3 / 4));
        uint256 _sharesSecondWithdraw = totalShares - _sharesFirstWithdraw;

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(DAI));
        address _hubFrom = YIELD_BEARING_WETH;
        address _hubTo = YIELD_BEARING_DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);
        uint256 _depositAmount = _calculateToYieldBearing(YIELD_BEARING_WETH, WETH, _inputAmount);

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _depositAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        uint256 _swappedUnderlying = _calculateToUnderlying(YIELD_BEARING_DAI, _swappedAmount);
        
        // Close position
        (uint256 _unswappedFirst, uint256 _swappedFirst) = _withdraw(_outputAsset, _sharesFirstWithdraw, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_sharesFirstWithdraw, _unswappedFirst, _swappedFirst, 0, _swappedUnderlying);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);

        // Withdraw second time
        (uint256 _unswappedSecond, uint256 _swappedSecond) = _withdraw(_outputAsset, _sharesSecondWithdraw, _auxData);

        // Perform checks
        _assertReturnedIsCorrect(_sharesSecondWithdraw, _unswappedSecond, _swappedSecond, 0, _swappedUnderlying);
        _assertFundsWereStoredCorrectly(_positionId, 0, _swappedAmount);
        assertEq(_unswappedFirst + _unswappedSecond, 0);
        _assertEqThreshold(_swappedFirst + _swappedSecond, _swappedUnderlying, 2, 0, "Not all swapped");
    }

    function testFinaliseIfSwapsPaused(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1, uint120(type(int120).max)));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);

        // Pause swaps
        vm.prank(HUB_OWNER);
        HUB.pause();

        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _inputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, _inputAmount, 0);
        _assertFundsWereStoredCorrectly(_positionId, _inputAmount, 0);
    }

    function testFinaliseIfFromIsNotAllowed(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1, uint120(type(int120).max)));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);

        // Unallow from
        _mockUnallow(_hubFrom);

        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _inputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, _inputAmount, 0);
        _assertFundsWereStoredCorrectly(_positionId, _inputAmount, 0);
    }   

    function testFinaliseIfToIsNotAllowed(uint120 _inputAmount, uint128 _shares) public {
        _inputAmount = uint120(bound(_inputAmount, 1, uint120(type(int120).max)));
        _shares = uint128(bound(_shares, 1, totalShares));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;
        uint64 _auxData = _buildAuxData(_hubFrom, _hubTo);

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _auxData, _inputAmount);

        // Unallow to
        _mockUnallow(_hubTo);

        // Close position
        (uint256 _unswapped, uint256 _swapped) = _withdraw(_outputAsset, _inputAsset, _shares, _auxData);

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertReturnedIsCorrect(_shares, _unswapped, _swapped, _inputAmount, 0);
        _assertFundsWereStoredCorrectly(_positionId, _inputAmount, 0);
    }    

    function _dealToRollup(AztecTypes.AztecAsset memory _asset, uint256 _amount) internal {
        if (_asset.assetType == AztecTypes.AztecAssetType.ETH) {
            deal(address(ROLLUP_PROCESSOR), _amount);
        } else {
            deal(_asset.erc20Address, address(ROLLUP_PROCESSOR), _amount);
        }
    }

    function _convert(
        AztecTypes.AztecAsset memory _input,
        uint64 _auxData, 
        uint256 _inputAmount        
    ) internal returns (uint256) {
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, _input, emptyAsset, _virtualAsset(0), emptyAsset, _auxData, _inputAmount);
        (uint256 _outputValueA, uint256 _outputValueB, bool _isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        assertEq(_outputValueA, bridge.VIRTUAL_SHARES_PER_POSITION());
        assertEq(_outputValueB, 0);
        assertFalse(_isAsync);
        (uint192 _positionId, uint64 _storedAuxData) = bridge.positionByNonce(0); 
        assertEq(_storedAuxData, _auxData);
        return _positionId;
    }

    function _validatePosition(
        uint256 _positionId,
        address _expectedFrom, 
        address _expectedTo,
        uint256 _deposited
    ) internal {
        ExtendedHub.UserPosition memory _position = HUB.userPosition(_positionId);
        assertEq(_position.from, _expectedFrom, "Invalid from");
        assertEq(_position.to, _expectedTo, "Invalid to");
        assertEq(_position.swapInterval, 1 hours, "Invalid swap interval");
        assertEq(_position.swapsExecuted, 0);
        assertEq(_position.swapped, 0);
        assertEq(_position.swapsLeft, 1);
        assertEq(_position.remaining, _deposited, "Invalid remaining");
        assertEq(_position.rate, _deposited, "Invalid rate");
    }

    function _swap(address _from, address _to) internal {
        (address _tokenA, address _tokenB) = _from < _to
            ? (_from, _to)
            : (_to, _from);
        address[] memory _tokens = new address[](2);
        _tokens[0] = _tokenA;
        _tokens[1] = _tokenB;
        ExtendedHub.PairIndexes[] memory _pairs = new ExtendedHub.PairIndexes[](1);
        _pairs[0] = ExtendedHub.PairIndexes(0, 1);
        ExtendedHub.SwapInfo memory _swapInfo = HUB.getNextSwapInfo(_tokens, _pairs, true, "");
        uint256 _toProvide = _swapInfo.tokens[0].toProvide + _swapInfo.tokens[1].toProvide;
        deal(_to, address(swapper), _toProvide);
        HUB.swap(
            _tokens,
            _pairs,
            address(swapper),
            address(swapper),
            new uint256[](2),
            "",
            ""
        );
    }        

    function _withdraw(AztecTypes.AztecAsset memory _outputA, uint256 _inputAmount, uint64 _auxData) internal returns (uint256, uint256) {
        return _withdraw(_outputA, emptyAsset, _inputAmount, _auxData);
    }

    function _withdraw(AztecTypes.AztecAsset memory _outputA, AztecTypes.AztecAsset memory _outputB, uint256 _inputAmount, uint64 _auxData) internal returns (uint256, uint256) {
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, _virtualAsset(0), emptyAsset, _outputA, _outputB, _auxData, _inputAmount);
        (uint256 _outputValueA, uint256 _outputValueB, bool _isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        assertFalse(_isAsync);
        return (_outputValueB, _outputValueA);
    }
    
    function _setUpSubsidy(uint256 _positionCriteria) internal {
        uint256[] memory _criteria = new uint256[](1);
        _criteria[0] = _positionCriteria;
        uint32[] memory _gasUsage = new uint32[](1);
        _gasUsage[0] = 98765;
        uint32[] memory _minGasPerMinute  = new uint32[](1);
        _minGasPerMinute[0] = 600_000;
        vm.prank(BRIDGE_OWNER);
        bridge.setSubsidies(_criteria, _gasUsage, _minGasPerMinute);
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), _positionCriteria, 600_000);
    }

    function _assertPositionWasTerminated(uint256 _positionId) internal {
        bool _isTerminated = HUB.userPosition(_positionId).swapInterval == 0;
        assertTrue(_isTerminated, "Position was not terminated");
    }

    function _mockUnallow(address _token) internal {
        address[] memory _tokens = new address[](1);
        _tokens[0] = _token;

        bool[] memory _allowed = new bool[](1);
        _allowed[0] = false;
        vm.prank(HUB_OWNER);
        HUB.setAllowedTokens(_tokens, _allowed);
    }

    function _assertReturnedIsCorrect(uint256 _shares, uint256 _unswapped, uint256 _swapped, uint256 _totalUnswapped, uint256 _totalSwapped) internal {
        _assertEqThreshold(_unswapped, Math.mulDiv(_totalUnswapped, _shares, totalShares), 1, 1, "Wrong returned unswapped");
        _assertEqThreshold(_swapped, Math.mulDiv(_totalSwapped, _shares, totalShares), 1, 1, "Wrong returned swapped");
    }

    function _assertEqThreshold(uint256 _actual, uint256 _expected, uint256 _lowerThreshold, uint256 _upperThreshold, string memory _err) internal {
        assertLe(_actual, _expected + _upperThreshold, _err);
        assertGe(_actual, _expected > _lowerThreshold ? _expected - _lowerThreshold : 0, _err);
    }

    function _assertFundsWereStoredCorrectly(uint256 _positionId, uint256 _unswapped, uint256 _swapped) internal {
        (bool wereFundsExtracted, uint248 swappedFunds, uint256 unswappedFunds) = bridge.fundsByPositionId(_positionId);
        assertTrue(wereFundsExtracted);
        assertEq(unswappedFunds, _unswapped, "Wrong stored unswapped funds");
        assertEq(swappedFunds, _swapped, "Wrong stored swapped funds");
    }

    function _buildAuxData(address _from, address _to) internal view returns (uint64) {
        return _buildAuxData(_from, _to, 1, 3);
    }

    function _buildAuxData(address _from, address _to, uint24 _amountOfSwaps, uint8 _swapIntervalCode) internal view returns (uint64) {
        uint32 _tokenIdFrom = bridge.getTokenId(_from);
        uint32 _tokenIdTo = bridge.getTokenId(_to);
        return _amountOfSwaps 
            + (uint64(_swapIntervalCode) << 24)
            + (uint64(_tokenIdFrom) << 32) 
            + (uint64(_tokenIdTo) << 48);
    }
    
    function _calculateSwapped(uint256 _positionId) internal view returns (uint256 _swapped) {
        ExtendedHub.UserPosition memory _position = HUB.userPosition(_positionId);
        return _position.swapped;
    }

    function _calculateToYieldBearing(address _yieldBearing, address _underlying, uint256 _amount) internal view returns (uint256) {
        ITransformer.UnderlyingAmount[] memory _input = new ITransformer.UnderlyingAmount[](1);
        _input[0] = ITransformer.UnderlyingAmount(_underlying, _amount);
        return TRANSFORMER_REGISTRY.calculateTransformToDependent(_yieldBearing, _input);
    }

    function _calculateToUnderlying(address _yieldBearing, uint256 _amount) internal view returns (uint256) {
        ITransformer.UnderlyingAmount[] memory _result = TRANSFORMER_REGISTRY.calculateTransformToUnderlying(_yieldBearing, _amount);
        return _result[0].amount;
    }

    function _virtualAsset(uint256 _nonce) internal pure returns(AztecTypes.AztecAsset memory _asset) {
        _asset.assetType = AztecTypes.AztecAssetType.VIRTUAL;
        _asset.id = _nonce;
    }

}

// An extended version of the DCA Hub
/* solhint-disable */
interface ExtendedHub {

    struct UserPosition {
        address from;
        address to;
        uint32 swapInterval;
        uint32 swapsExecuted;
        uint256 swapped;
        uint32 swapsLeft;
        uint256 remaining;
        uint120 rate;
    }

    struct PairIndexes {
        uint8 indexTokenA;
        uint8 indexTokenB;
    }

    struct SwapInfo {
        TokenInSwap[] tokens;
        PairInSwap[] pairs;
    }

    struct TokenInSwap {
        address token;
        uint256 reward;
        uint256 toProvide;
        uint256 platformFee;
    }

    struct PairInSwap {
        address tokenA;
        address tokenB;
        uint256 totalAmountToSwapTokenA;
        uint256 totalAmountToSwapTokenB;
        uint256 ratioAToB;
        uint256 ratioBToA;
        bytes1 intervalsInSwap;
    }

    function userPosition(uint256 positionId) external view returns (UserPosition memory position);

    function getNextSwapInfo(
        address[] calldata tokens,
        PairIndexes[] calldata pairs,
        bool calculatePrivilegedAvailability,
        bytes calldata oracleData
    ) external view returns (SwapInfo memory swapInformation);

    function swap(
        address[] calldata tokens,
        PairIndexes[] calldata pairsToSwap,
        address rewardRecipient,
        address callbackHandler,
        uint256[] calldata borrow,
        bytes calldata callbackData,
        bytes calldata oracleData
    ) external returns (SwapInfo memory);

    function pause() external; 

    function setAllowedTokens(address[] calldata _tokens, bool[] calldata _allowed) external;
}
/* solhint-enable */