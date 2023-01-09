// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AngleSLPBridge, IWETH} from "../../bridges/angle/AngleSLPBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {AngleSLPDeployment, BaseDeployment} from "../../deployment/angle/AngleSLPDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract AngleMeasure is AngleSLPDeployment {
    ISubsidy internal constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    address private constant BENEFICIARY = address(uint160(uint256(keccak256(abi.encodePacked("_BENEFICIARY")))));

    GasBase internal gasBase;
    AngleSLPBridge internal bridge;

    IWETH internal weth;

    AztecTypes.AztecAsset internal emptyAsset;
    AztecTypes.AztecAsset internal ethAsset;
    AztecTypes.AztecAsset internal wethAsset;
    AztecTypes.AztecAsset internal sanWethAsset;

    function setUp() public override(BaseDeployment) {
        super.setUp();

        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        bridge = AngleSLPBridge(payable(deployAndList()));
        ROLLUP_PROCESSOR = temp;

        weth = bridge.WETH();

        ethAsset = AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        wethAsset =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(weth), assetType: AztecTypes.AztecAssetType.ERC20});
        sanWethAsset =
            AztecTypes.AztecAsset({id: 1, erc20Address: bridge.SANWETH(), assetType: AztecTypes.AztecAssetType.ERC20});

        // Fund subsidy
        vm.startBroadcast();
        SUBSIDY.subsidize{value: 10 ether}(address(bridge), 0, 500);
        SUBSIDY.subsidize{value: 10 ether}(address(bridge), 1, 500);
        SUBSIDY.registerBeneficiary(BENEFICIARY);
        vm.stopBroadcast();

        // Warp time to increase subsidy
        vm.warp(block.timestamp + 1 days);
    }

    function measureETH() public {
        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("ETH balance of gasBase", address(gasBase).balance);

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge), ethAsset, emptyAsset, sanWethAsset, emptyAsset, 1 ether, 0, 0, BENEFICIARY, 200000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 sanWethBalance = IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the sanWeth
        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("sanWeth balance of gasBase", sanWethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                sanWethAsset,
                emptyAsset,
                ethAsset,
                emptyAsset,
                sanWethBalance / 2,
                1,
                1,
                BENEFICIARY,
                210000
            );
            emit log_named_uint(
                "sanWeth balance of gasBase", IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase))
                );
        }

        uint256 claimableSubsidyAfterWithdrawal = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(
            claimableSubsidyAfterWithdrawal, claimableSubsidyAfterDeposit, "Subsidy was not claimed during withdrawal"
        );
        emit log_named_uint("Claimable subsidy after withdrawal", claimableSubsidyAfterWithdrawal);
    }

    function measureWETH() public {
        vm.broadcast();
        weth.deposit{value: 2 ether}();
        vm.broadcast();
        weth.transfer(address(gasBase), 2 ether);
        emit log_named_uint("WETH balance of gasBase", weth.balanceOf(address(gasBase)));

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge), wethAsset, emptyAsset, sanWethAsset, emptyAsset, 1 ether, 0, 0, BENEFICIARY, 170000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 sanWethBalance = IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the sanWeth
        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("sanWeth balance of gasBase", sanWethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                sanWethAsset,
                emptyAsset,
                wethAsset,
                emptyAsset,
                sanWethBalance / 2,
                1,
                1,
                BENEFICIARY,
                180000
            );
            emit log_named_uint(
                "sanWeth balance of gasBase", IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase))
                );
        }

        uint256 claimableSubsidyAfterWithdrawal = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(
            claimableSubsidyAfterWithdrawal, claimableSubsidyAfterDeposit, "Subsidy was not claimed during withdrawal"
        );
        emit log_named_uint("Claimable subsidy after withdrawal", claimableSubsidyAfterWithdrawal);
    }
}
