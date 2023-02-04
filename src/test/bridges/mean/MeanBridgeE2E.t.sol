// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "../../aztec/base/BridgeTestBase.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {MeanBridge} from "../../../bridges/mean/MeanBridge.sol";
import {IDCAHub} from "../../../interfaces/mean/IDCAHub.sol";
import {ITransformerRegistry} from "../../../interfaces/mean/ITransformerRegistry.sol";
import {ITransformer} from "../../../interfaces/mean/ITransformer.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {DCAHubSwapperMock} from './mocks/Swapper.sol';

contract MeanBridgeE2eTest is BridgeTestBase {

    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant YIELD_BEARING_DAI = 0xc4113b7605D691E073c162809060b6C5Ae402F1e;
    address public constant YIELD_BEARING_WETH = 0xd4dE9D2Fc1607d1DF63E1c95ecBfa8d7946f5457;
    address private constant BRIDGE_OWNER = 0x0000000000000000000000000000000000000001;
    address private constant HUB_OWNER = 0xEC864BE26084ba3bbF3cAAcF8F6961A9263319C4;
    ExtendedHub private constant HUB = ExtendedHub(0xA5AdC5484f9997fBF7D405b9AA62A7d88883C345);
    ITransformerRegistry private constant TRANSFORMER_REGISTRY = ITransformerRegistry(0xC0136591Df365611B1452B5F8823dEF69Ff3A685);
    MeanBridge private bridge;
    DCAHubSwapperMock private swapper;
    uint256 private bridgeId;
    
    function setUp() public {
        bridge = new MeanBridge(IDCAHub(address(HUB)), TRANSFORMER_REGISTRY, BRIDGE_OWNER, address(ROLLUP_PROCESSOR));
        bridge = new MeanBridge(IDCAHub(address(HUB)), TRANSFORMER_REGISTRY, BRIDGE_OWNER, address(ROLLUP_PROCESSOR));

        // Approve tokens
        IERC20[] memory _toApprove = new IERC20[](2);
        _toApprove[0] = IERC20(DAI);
        _toApprove[1] = IERC20(WETH);
        bridge.maxApprove(_toApprove);

        // Register yield-bearing-wrappers
        address[] memory _yieldBearing = new address[](2);
        _yieldBearing[0] = YIELD_BEARING_DAI;
        _yieldBearing[1] = YIELD_BEARING_WETH;
        vm.prank(BRIDGE_OWNER);
        bridge.registerWrappers(_yieldBearing);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 600_000);
        bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        swapper = new DCAHubSwapperMock();

        vm.label(address(bridge), "MeanBridge");
        vm.label(address(HUB), "DCAHub");
        vm.label(address(TRANSFORMER_REGISTRY), "TRANSFORMER_REGISTRY");
        vm.label(DAI, 'DAI');
        vm.label(WETH, 'WETH');
        vm.label(YIELD_BEARING_DAI, 'YIELD_BEARING_DAI');
        vm.label(YIELD_BEARING_WETH, 'YIELD_BEARING_WETH');
    }

    function testEthToERC20(uint120 _inputAmount) public {
        vm.assume(0 < _inputAmount && _inputAmount <= uint120(type(int120).max));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _inputAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        
        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, 0);
        _assertBalance(_outputAsset, _initialBalanceOutput, _swappedAmount);
    }  

    function testYieldToETH(uint120 _inputAmount) public {
        vm.assume(1 ether <= _inputAmount && _inputAmount <= 15 ether);

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        address _hubFrom = YIELD_BEARING_DAI;
        address _hubTo = WETH;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Validate position
        uint256 _depositAmount = _calculateToYieldBearing(YIELD_BEARING_DAI, DAI, _inputAmount);
        _validatePosition(_positionId, _hubFrom, _hubTo, _depositAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        
        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, 0);
        _assertBalance(_outputAsset, _initialBalanceOutput, _swappedAmount);
    }

    function testERC20ToYieldETH(uint120 _inputAmount) public {
        vm.assume(0.5 ether <= _inputAmount && _inputAmount <= 10_000 ether);

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(DAI));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        address _hubFrom = DAI;
        address _hubTo = YIELD_BEARING_WETH;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _inputAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        uint256 _swappedAmount = _calculateSwapped(_positionId);
        uint256 _swappedUnderlying = _calculateToUnderlying(YIELD_BEARING_WETH, _swappedAmount);

        
        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, 0);
        _assertBalance(_outputAsset, _initialBalanceOutput, _swappedUnderlying);
    }

    function testYieldETHToYieldERC20() public {
        uint120 _inputAmount = 1 ether;

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(DAI));
        address _hubFrom = YIELD_BEARING_WETH;
        address _hubTo = YIELD_BEARING_DAI;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);   
        uint256 _depositAmount = _calculateToYieldBearing(YIELD_BEARING_WETH, WETH, _inputAmount);

        // Validate position
        _validatePosition(_positionId, _hubFrom, _hubTo, _depositAmount);

        // Perform swap
        _swap(_hubFrom, _hubTo);
        
        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, 0);
        // Note: Euler returns some wei less that expected, so we don't test it here
    }

    function testFinaliseIfSwapsPaused(uint120 _inputAmount) public {
        vm.assume(0 < _inputAmount && _inputAmount <= uint120(type(int120).max));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Pause swaps
        vm.prank(HUB_OWNER);
        HUB.pause();

        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, _inputAmount);
        _assertBalance(_outputAsset, _initialBalanceOutput, 0);
    }

    function testFinaliseIfFromIsNotAllowed(uint120 _inputAmount) public {
        vm.assume(0 < _inputAmount && _inputAmount <= uint120(type(int120).max));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Unallow from
        _unallow(_hubFrom);

        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, _inputAmount);
        _assertBalance(_outputAsset, _initialBalanceOutput, 0);
    }   

    function testFinaliseIfToIsNotAllowed(uint120 _inputAmount) public {
        vm.assume(0 < _inputAmount && _inputAmount <= uint120(type(int120).max));

        AztecTypes.AztecAsset memory _inputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory _outputAsset = ROLLUP_ENCODER.getRealAztecAsset(DAI);
        address _hubFrom = WETH;
        address _hubTo = DAI;

        // Deposit to rollup processor
        _dealToRollup(_inputAsset, _inputAmount);

        // Create DCA position
        uint256 _positionId = _convert(_inputAsset, _outputAsset, _hubFrom, _hubTo, _inputAmount);        

        // Unallow to
        _unallow(_hubTo);

        // Close position
        uint256 _initialBalanceInput = _calculateBalance(_inputAsset);
        uint256 _initialBalanceOutput = _calculateBalance(_outputAsset);
        _finalise();

        // Perform checks
        _assertPositionWasTerminated(_positionId);
        _assertBalance(_inputAsset, _initialBalanceInput, _inputAmount);
        _assertBalance(_outputAsset, _initialBalanceOutput, 0);
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
        AztecTypes.AztecAsset memory _output,
        address _from, 
        address _to, 
        uint256 _inputAmount        
    ) internal returns (uint256 _positionId) {
        uint64 _auxData =_buildAuxData(_from, _to, 1, 3);
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, _input, emptyAsset, _output, _input, _auxData, _inputAmount);
        (uint256 _outputValueA, uint256 _outputValueB, bool _isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        assertEq(_outputValueA, 0);
        assertEq(_outputValueB, 0);
        assertTrue(_isAsync);
        _positionId = bridge.positionByNonce(0); 
    }

    function _buildAuxData(address _from, address _to, uint24 _amountOfSwaps, uint8 _swapIntervalCode) internal view returns (uint64) {
        uint32 _wrapperIdFrom = bridge.getWrapperId(_from);
        uint32 _wrapperIdTo = bridge.getWrapperId(_to);
        return _amountOfSwaps 
            + (uint64(_swapIntervalCode) << 24)
            + (uint64(_wrapperIdFrom) << 32) 
            + (uint64(_wrapperIdTo) << 48);
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
        ExtendedHub.SwapInfo memory _swapInfo = HUB.getNextSwapInfo(_tokens, _pairs, true, '');
        uint256 _toProvide = _swapInfo.tokens[0].toProvide + _swapInfo.tokens[1].toProvide;
        deal(_to, address(swapper), _toProvide);
        HUB.swap(
            _tokens,
            _pairs,
            address(swapper),
            address(swapper),
            new uint256[](2),
            '',
            ''
        );
        
    }
    function _calculateSwapped(uint256 _positionId) internal view returns (uint256 _swapped) {
        ExtendedHub.UserPosition memory _position = HUB.userPosition(_positionId);
        return _position.swapped;
    }

    function _finalise() internal {
        bool interactionCompleted = ROLLUP_PROCESSOR.processAsyncDefiInteraction(0);
        assertEq(interactionCompleted, true);
    }

    function _assertPositionWasTerminated(uint256 _positionId) internal {
        bool _isTerminated = HUB.userPosition(_positionId).swapInterval == 0;
        assertTrue(_isTerminated, 'Position was not terminated');
    }

    function _assertBalance(AztecTypes.AztecAsset memory _asset, uint256 _initial, uint256 _diff) internal {
        uint256 _current = _calculateBalance(_asset);
        assertEq(_current - _initial, _diff, 'Balance check failed');
    }

    function _calculateBalance(AztecTypes.AztecAsset memory _asset) internal view returns(uint256) {
        return (_asset.assetType == AztecTypes.AztecAssetType.ETH)
            ? address(ROLLUP_PROCESSOR).balance
            : IERC20(_asset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
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

    function _unallow(address _token) internal {
        address[] memory _tokens = new address[](1);
        _tokens[0] = _token;

        bool[] memory _allowed = new bool[](1);
        _allowed[0] = false;
        vm.prank(HUB_OWNER);
        HUB.setAllowedTokens(_tokens, _allowed);
    }
}

// An extended version of the DCA Hub
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