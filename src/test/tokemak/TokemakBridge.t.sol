// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../../../lib/forge-std/src/Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IManager} from "./interfaces/Manager.sol";
import {TokemakBridge} from "./../../bridges/tokemak/TokemakBridge.sol";

import {AztecTypes} from "./../../aztec/libraries/AztecTypes.sol";

import "../../../lib/ds-test/src/test.sol";

contract TokemakBridgeTest is DSTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address public constant tWETH = 0xD3D13a578a53685B4ac36A1Bab31912D2B2A2F36;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant MANAGER = 0xA86e412109f77c45a3BC1c5870b880492Fb86A14;
    address public constant DEPLOYER = 0x9e0bcE7ec474B481492610eB9dd5D69EB03718D5;
    uint256 constant WETH_SLOT = 3;
    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    event TokenBalance(uint256 previousBalance, uint256 newBalance);

    uint256 nonce = 1;
    TokemakBridge bridge;
    AztecTypes.AztecAsset private empty;

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        bridge = new TokemakBridge(address(rollupProcessor));

        rollupProcessor.setBridgeGasLimit(address(bridge), 2000000);
    }

    function testTokemakBridge() public {
        validateTokemakBridge(1000, 500);
    }

    function validateTokemakBridge(uint256 balance, uint256 depositAmount) public {
        _setTokenBalance(WETH, address(rollupProcessor), balance * 3, WETH_SLOT);

        //Deposit to Pool
        uint256 output = depositToPool(WETH, tWETH, depositAmount);
        nonce += 1;

        //Request Withdraw
        requestWithdrawFromPool(WETH, tWETH, output);
        nonce += 1;

        //Next Cycle
        uint256 newTimestamp = 1748641030;
        vm.warp(newTimestamp);
        vm.startPrank(DEPLOYER);
        IManager(MANAGER).completeRollover("complete");
        IManager(MANAGER).completeRollover("complete2");
        vm.stopPrank();

        //Test if automatic process withdrawal working
        uint256 output2 = depositToPool(WETH, tWETH, depositAmount * 2);
        nonce += 1;

        //Request Withdraw
        requestWithdrawFromPool(WETH, tWETH, output2);

        //Next Cycle
        newTimestamp = 1758641030;
        vm.warp(newTimestamp);
        vm.startPrank(DEPLOYER);
        IManager(MANAGER).completeRollover("complete3");
        IManager(MANAGER).completeRollover("complete4");
        vm.stopPrank();

        //Withdraw
        processPendingWithdrawal(WETH);
    }

    function depositToPool(
        address asset,
        address tAsset,
        uint256 depositAmount
    ) public returns (uint256) {
        IERC20 assetToken = IERC20(asset);
        uint256 beforeBalance = assetToken.balanceOf(address(rollupProcessor));

        AztecTypes.AztecAsset memory wAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: asset,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory wtAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: tAsset,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(bridge),
            wAsset,
            empty,
            wtAsset,
            empty,
            depositAmount,
            nonce,
            0
        );
        uint256 afterBalance = assetToken.balanceOf(address(rollupProcessor));
        emit TokenBalance(beforeBalance, afterBalance);
        return outputValueA;
    }

    function requestWithdrawFromPool(
        address asset,
        address tAsset,
        uint256 depositAmount
    ) public returns (uint256) {
        AztecTypes.AztecAsset memory wAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: asset,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory wtAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: tAsset,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(bridge),
            wtAsset,
            empty,
            wAsset,
            empty,
            depositAmount,
            nonce,
            1
        );

        return outputValueA;
    }

    function processPendingWithdrawal(address asset) public {
        IERC20 assetToken = IERC20(asset);
        uint256 beforeBalance = assetToken.balanceOf(address(rollupProcessor));
        bool completed = rollupProcessor.processAsyncDefiInteraction(nonce);
        uint256 afterBalance = assetToken.balanceOf(address(rollupProcessor));
        emit TokenBalance(beforeBalance, afterBalance);
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance,
        uint256 slot
    ) internal {
        vm.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }
}
