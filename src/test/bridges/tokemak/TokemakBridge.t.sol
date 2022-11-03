// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IManager} from "../../../interfaces/tokemak/IManager.sol";

import {TokemakBridge} from "../../../bridges/tokemak/TokemakBridge.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {Ttoken} from "../../../interfaces/tokemak/Ttoken.sol";

contract TokemakBridgeTest is BridgeTestBase {
    uint256 private constant TWO_WEEK = 60 * 60 * 24 * 7 * 2;

    address public constant MANAGER = 0xA86e412109f77c45a3BC1c5870b880492Fb86A14;
    address public constant DEPLOYER = 0x9e0bcE7ec474B481492610eB9dd5D69EB03718D5;

    mapping(address => bool) public excludedPoolsMapping;
    uint256 private nonce;
    TokemakBridge private bridge;

    uint256 private bridgeAddressId;

    function setUp() public {
        bridge = new TokemakBridge(address(ROLLUP_PROCESSOR));
        vm.deal(address(bridge), 0);
        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2000000);

        vm.stopPrank();

        bridgeAddressId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        address[4] memory excludedPools = [
            0xe7a7D17e2177f66D035d9D50A7f48d8D8E31532D, // deposit paused
            0xADF15Ec41689fc5b6DcA0db7c53c9bFE7981E655, // voting error
            0x8d2254f3AE37201EFe9Dfd9131924FE0bDd97832, // vm.deal overwritting error
            0xeff721Eae19885e17f5B80187d6527aad3fFc8DE // vm.deal overwritting error
        ];
        for (uint256 i = 0; i < excludedPools.length; i++) {
            excludedPoolsMapping[excludedPools[i]] = true;
        }
    }

    function testTokemanBridgeTokens(uint256 _balance, uint256 _amount) public {
        vm.assume(_balance > 1);
        vm.assume(_amount > 1);
        vm.assume(_amount <= _balance / 2);
        vm.assume(_amount <= (1 << 250));

        IManager _manager = IManager(MANAGER);
        address[] memory _pools = _manager.getPools();
        for (uint256 i = 0; i < _pools.length; i++) {
            address _pool = _pools[i];

            if (excludedPoolsMapping[_pool]) continue;
            Ttoken _token = Ttoken(_pool);
            address _asset = _token.underlyer();
            IERC20 _inputToken = IERC20(_asset);

            vm.startPrank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(_pool, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(address(_inputToken), 100000);
            vm.stopPrank();

            validateTokemakBridge(
                _balance,
                _amount,
                getRealAztecAsset(address(_inputToken)),
                getRealAztecAsset(address(_token))
            );
        }
    }

    function validateTokemakBridge(
        uint256 _balance,
        uint256 _amount,
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset
    ) public {
        deal(_inputAsset.erc20Address, address(ROLLUP_PROCESSOR), _balance);

        //Deposit to Pool
        uint256 output = depositToPool(_amount, _inputAsset, _outputAsset);

        //Request Withdraw
        requestWithdrawFromPool(output, _inputAsset, _outputAsset);

        //Next Cycle
        vm.warp(block.timestamp + TWO_WEEK);
        vm.startPrank(DEPLOYER);
        IManager(MANAGER).completeRollover("complete");
        IManager(MANAGER).completeRollover("complete2");
        vm.stopPrank();

        //Test if automatic process withdrawal working
        uint256 output2 = depositToPool(_amount, _inputAsset, _outputAsset);

        nonce = getNextNonce();

        //Request Withdraw
        requestWithdrawFromPool(output2, _inputAsset, _outputAsset);

        //Next Cycle
        vm.warp(block.timestamp + TWO_WEEK);
        vm.startPrank(DEPLOYER);
        IManager(MANAGER).completeRollover("complete3");
        IManager(MANAGER).completeRollover("complete4");
        vm.stopPrank();

        //Withdraw
        processPendingWithdrawal();
    }

    function depositToPool(
        uint256 _depositAmount,
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset
    ) public returns (uint256) {
        uint256 bridgeCallData = encodeBridgeCallData(
            bridgeAddressId,
            _inputAsset,
            emptyAsset,
            _outputAsset,
            emptyAsset,
            0
        );

        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, _depositAmount);

        return outputValueA;
    }

    function requestWithdrawFromPool(
        uint256 _withdrawAmount,
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset
    ) public returns (uint256) {
        uint256 bridgeCallData = encodeBridgeCallData(
            bridgeAddressId,
            _outputAsset,
            emptyAsset,
            _inputAsset,
            emptyAsset,
            1
        );

        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, _withdrawAmount);

        return outputValueA;
    }

    function processPendingWithdrawal() public {
        ROLLUP_PROCESSOR.processAsyncDefiInteraction(nonce);
    }
}
