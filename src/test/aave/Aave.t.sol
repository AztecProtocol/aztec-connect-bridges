// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Aave-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveLendingBridge} from "./../../bridges/aave/AaveLending.sol";
import {IPool} from "./../../bridges/aave/interfaces/IPool.sol";
import {ILendingPoolAddressesProvider} from "./../../bridges/aave/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "./../../bridges/aave/interfaces/IAToken.sol";
import {ZkAToken} from "./../../bridges/aave/ZkAToken.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import {WadRayMath} from "./../../bridges/aave/libraries/WadRayMath.sol";

import "../../../lib/ds-test/src/test.sol";


contract AaveTest is DSTest {
    using WadRayMath for uint256;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    AaveLendingBridge aaveLendingBridge;
    ILendingPoolAddressesProvider constant addressesProvider =
        ILendingPoolAddressesProvider(
            0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5
        );
    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IAToken constant aDai = IAToken(0x028171bCA77440897B824Ca71D1c56caC55b68A3);

    IPool pool = IPool(addressesProvider.getLendingPool());

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        aaveLendingBridge = new AaveLendingBridge(
            address(rollupProcessor),
            address(addressesProvider)
        );

        _setTokenBalance(address(dai), address(0xdead), 42069);
    }

    // function testAddDaiToMapping() public {
    //     assertEq(
    //         aaveLendingBridge.underlyingToZkAToken(address(dai)),
    //         address(0)
    //     );
    //     /// Add invalid (revert)
    //     vm.expectRevert("AaveLendingBridge: NO_LENDING_POOL");
    //     aaveLendingBridge.setUnderlyingToZkAToken(address(0xdead));

    //     /// Add dai
    //     aaveLendingBridge.setUnderlyingToZkAToken(address(dai));
    //     assertNotEq(
    //         aaveLendingBridge.underlyingToZkAToken(address(dai)),
    //         address(0)
    //     );

    //     /// Add dai again (revert)
    //     vm.expectRevert("AaveLendingBridge: ZK_TOKEN_SET");
    //     aaveLendingBridge.setUnderlyingToZkAToken(address(dai));
    // }

    // function testEnterWithDai(uint128 depositAmount, uint16 timeDiff) public {
    //     _setupDai();
    //     _enterWithDai(1000000);
    //     _accrueInterest(timeDiff);
    // }

    // function testAdditionalEnter(
    //     uint128 depositAmount1,
    //     uint128 depositAmount2,
    //     uint16 timeDiff
    // ) public {
    //     _setupDai();
    //     _enterWithDai(depositAmount1);

    //     _accrueInterest(timeDiff);

    //     _enterWithDai(depositAmount2);
    // }

    // function testExitPartially(
    //     uint128 depositAmount,
    //     uint128 withdrawAmount,
    //     uint16 timeDiff
    // ) public {
    //     while (withdrawAmount > depositAmount / 2) {
    //         withdrawAmount /= 2;
    //     }

    //     _setupDai();
    //     _enterWithDai(depositAmount);

    //     _accrueInterest(timeDiff);

    //     _exitWithDai(withdrawAmount);
    // }

    // function testExitPartiallyTenCompletely(
    //     uint128 depositAmount,
    //     uint16 timeDiff1,
    //     uint16 timeDiff2
    // ) public {
    //     _setupDai();
    //     _enterWithDai(depositAmount);

    //     _accrueInterest(timeDiff1);

    //     _exitWithDai(depositAmount / 2);

    //     Balances memory balances = _getBalances();

    //     _accrueInterest(timeDiff2);

    //     _exitWithDai(balances.rollupZk);

    //     Balances memory balancesAfter = _getBalances();
    //     assertLt(
    //         balances.rollupZk,
    //         depositAmount,
    //         "never entered, or entered at index = 1"
    //     );
    //     assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
    // }

    // function testExitCompletely(uint128 depositAmount, uint16 timeDiff) public {
    //     _setupDai();
    //     _enterWithDai(depositAmount);

    //     Balances memory balances = _getBalances();

    //     _accrueInterest(timeDiff);

    //     _exitWithDai(balances.rollupZk);

    //     Balances memory balancesAfter = _getBalances();
    //     assertLt(
    //         balances.rollupZk,
    //         depositAmount,
    //         "never entered, or entered at index = 1"
    //     );
    //     assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
    // }

    /// Helpers

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    function _setupDai() internal {
        aaveLendingBridge.setUnderlyingToZkAToken(address(dai));
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 2; // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }

    struct Balances {
        uint256 rollupDai;
        uint256 rollupZk;
        uint256 bridgeAdai;
        uint256 bridgeScaledADai;
    }

    function _getBalances() internal view returns (Balances memory) {
        IERC20 zkToken = IERC20(
            aaveLendingBridge.underlyingToZkAToken(address(dai))
        );
        address rp = address(rollupProcessor);
        address dbp = address(aaveLendingBridge);
        return
            Balances({
                rollupDai: dai.balanceOf(rp),
                rollupZk: zkToken.balanceOf(rp),
                bridgeAdai: aDai.balanceOf(dbp),
                bridgeScaledADai: aDai.scaledBalanceOf(dbp)
            });
    }

    function _accrueInterest(uint256 timeDiff) internal {
        Balances memory balancesBefore = _getBalances();
        uint256 expectedDaiBefore = balancesBefore.rollupZk.rayMul(
            pool.getReserveNormalizedIncome(address(dai))
        );

        vm.warp(block.timestamp + timeDiff);

        Balances memory balancesAfter = _getBalances();
        uint256 expectedDaiAfter = balancesAfter.rollupZk.rayMul(
            pool.getReserveNormalizedIncome(address(dai))
        );

        if (timeDiff > 0) {
            assertGt(
                expectedDaiAfter,
                expectedDaiBefore,
                "Did not earn any interest"
            );
        }

        assertEq(
            expectedDaiBefore,
            balancesBefore.bridgeAdai,
            "Bridge adai not matching before time"
        );
        assertEq(
            expectedDaiAfter,
            balancesAfter.bridgeAdai,
            "Bridge adai not matching after time"
        );
    }

    function _enterWithDai(uint256 amount) public {
        IERC20 zkAToken = IERC20(
            aaveLendingBridge.underlyingToZkAToken(address(dai))
        );

        uint256 depositAmount = amount;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount);

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(aaveLendingBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                0
            );

        Balances memory balanceAfter = _getBalances();

        uint256 index = pool.getReserveNormalizedIncome(address(dai));
        uint256 scaledDiff = depositAmount.rayDiv(index);
        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk +
            scaledDiff;
        uint256 expectedADaiBalanceAfter = expectedScaledBalanceAfter.rayMul(
            index
        );

        assertEq(
            balanceBefore.rollupZk,
            balanceBefore.bridgeScaledADai,
            "Scaled balances before not matching"
        );
        assertEq(
            balanceAfter.rollupZk,
            balanceAfter.bridgeScaledADai,
            "Scaled balances after not matching"
        );
        assertEq(
            balanceAfter.rollupZk - balanceBefore.rollupZk,
            outputValueA,
            "Output value and zk balance not matching"
        );
        assertEq(
            balanceAfter.rollupZk - balanceBefore.rollupZk,
            scaledDiff,
            "Scaled balance change not matching"
        );
        assertEq(
            expectedADaiBalanceAfter,
            balanceAfter.bridgeAdai,
            "ADai balance not matching"
        );
        assertEq(
            balanceBefore.rollupDai - balanceAfter.rollupDai,
            depositAmount,
            "Bridge dai not matching"
        );
    }

    function _exitWithDai(uint256 zkAmount) public {
        IERC20 zkAToken = IERC20(
            aaveLendingBridge.underlyingToZkAToken(address(dai))
        );

        uint256 withdrawAmount = zkAmount;

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(aaveLendingBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                withdrawAmount,
                2,
                0
            );

        Balances memory balanceAfter = _getBalances();

        uint256 index = pool.getReserveNormalizedIncome(address(dai));
        uint256 innerADaiWithdraw = withdrawAmount.rayMul(index);
        uint256 innerScaledChange = innerADaiWithdraw.rayDiv(index);

        // This will fail if the zkAmount > balance of zkATokens
        assertEq(withdrawAmount, innerScaledChange, "Inner not matching");

        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk -
            withdrawAmount;
        uint256 expectedADaiBalanceAfter = expectedScaledBalanceAfter.rayMul(
            index
        );

        assertEq(
            innerADaiWithdraw,
            outputValueA,
            "Output token does not match expected output"
        );
        assertEq(
            balanceBefore.rollupZk,
            balanceBefore.bridgeScaledADai,
            "Scaled balance before not matching"
        );
        assertEq(
            balanceAfter.rollupZk,
            balanceAfter.bridgeScaledADai,
            "Scaled balance after not matching"
        );
        assertEq(
            balanceAfter.rollupZk,
            expectedScaledBalanceAfter,
            "Scaled balance after not matching"
        );
        assertEq(
            balanceBefore.rollupZk - balanceAfter.rollupZk,
            withdrawAmount,
            "Change in zk balance is equal to deposit amount"
        );
        assertEq(
            balanceAfter.bridgeAdai,
            expectedADaiBalanceAfter,
            "Bridge adai balance don't match expected"
        );
    }
}
