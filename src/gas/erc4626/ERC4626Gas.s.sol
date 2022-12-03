// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Bridge} from "../../bridges/erc4626/ERC4626Bridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

import {ERC4626Deployment, BaseDeployment} from "../../deployment/erc4626/ERC4626Deployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract ERC4626Measure is ERC4626Deployment {
    ISubsidy private constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address private constant BENEFICIARY = address(uint160(uint256(keccak256(abi.encodePacked("_BENEFICIARY")))));

    GasBase internal gasBase;
    ERC4626Bridge internal bridge;

    AztecTypes.AztecAsset internal emptyAsset;
    AztecTypes.AztecAsset internal ethAsset;
    AztecTypes.AztecAsset internal wethAsset;
    AztecTypes.AztecAsset internal wewethAsset; // ERC4626-Wrapped Euler WETH (weWETH)

    AztecTypes.AztecAsset internal wstethAsset;
    AztecTypes.AztecAsset internal wewstethAsset; // ERC4626-Wrapped Euler wstETH (wewstETH)

    AztecTypes.AztecAsset internal daiAsset;
    AztecTypes.AztecAsset internal wcDaiAsset; // ERC4626-Wrapped Compound Dai

    function setUp() public override (BaseDeployment) {
        super.setUp();

        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        bridge = ERC4626Bridge(payable(deploy()));
        ROLLUP_PROCESSOR = temp;

        ethAsset = AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        wethAsset =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(WETH), assetType: AztecTypes.AztecAssetType.ERC20});
        wewethAsset = AztecTypes.AztecAsset({
            id: 3,
            erc20Address: 0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        wstethAsset =
            AztecTypes.AztecAsset({id: 4, erc20Address: address(WSTETH), assetType: AztecTypes.AztecAssetType.ERC20});
        wewstethAsset = AztecTypes.AztecAsset({
            id: 5,
            erc20Address: 0x60897720AA966452e8706e74296B018990aEc527,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        daiAsset =
            AztecTypes.AztecAsset({id: 6, erc20Address: address(DAI), assetType: AztecTypes.AztecAssetType.ERC20});
        wcDaiAsset = AztecTypes.AztecAsset({
            id: 7,
            erc20Address: 0x6D088fe2500Da41D7fA7ab39c76a506D7c91f53b,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // List vaults and fund subsidy
        vm.startBroadcast();
        bridge.listVault(wewethAsset.erc20Address);
        bridge.listVault(wewstethAsset.erc20Address);
        bridge.listVault(wcDaiAsset.erc20Address);
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(wethAsset, emptyAsset, wewethAsset, emptyAsset, 0), 500
        );
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(wewethAsset, emptyAsset, wethAsset, emptyAsset, 0), 500
        );
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(wstethAsset, emptyAsset, wewstethAsset, emptyAsset, 0), 500
        );
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(wewstethAsset, emptyAsset, wstethAsset, emptyAsset, 0), 500
        );
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(daiAsset, emptyAsset, wcDaiAsset, emptyAsset, 0), 500
        );
        SUBSIDY.subsidize{value: 1e17}(
            address(bridge), bridge.computeCriteria(wcDaiAsset, emptyAsset, daiAsset, emptyAsset, 0), 500
        );
        SUBSIDY.registerBeneficiary(BENEFICIARY);
        vm.stopBroadcast();

        // Warp time to increase subsidy
        vm.warp(block.timestamp + 10 days);
    }

    function measureETH() public {
        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("ETH balance of gasBase", address(gasBase).balance);

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge), ethAsset, emptyAsset, wewethAsset, emptyAsset, 1 ether, 0, 0, BENEFICIARY, 280000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 wewethBalance = IERC20(wewethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the weweth
        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("weweth balance of gasBase", wewethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                wewethAsset,
                emptyAsset,
                ethAsset,
                emptyAsset,
                wewethBalance / 2,
                1,
                1,
                BENEFICIARY,
                260000
            );
            emit log_named_uint(
                "weweth balance of gasBase", IERC20(wewethAsset.erc20Address).balanceOf(address(gasBase))
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
        WETH.deposit{value: 2 ether}();
        vm.broadcast();
        WETH.transfer(address(gasBase), 2 ether);
        emit log_named_uint("WETH balance of gasBase", WETH.balanceOf(address(gasBase)));

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge), wethAsset, emptyAsset, wewethAsset, emptyAsset, 1 ether, 0, 0, BENEFICIARY, 260000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 wewethBalance = IERC20(wewethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the weweth
        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("weweth balance of gasBase", wewethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                wewethAsset,
                emptyAsset,
                wethAsset,
                emptyAsset,
                wewethBalance / 2,
                1,
                1,
                BENEFICIARY,
                220000
            );
            emit log_named_uint(
                "weweth balance of gasBase", IERC20(wewethAsset.erc20Address).balanceOf(address(gasBase))
                );
        }

        uint256 claimableSubsidyAfterWithdrawal = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(
            claimableSubsidyAfterWithdrawal, claimableSubsidyAfterDeposit, "Subsidy was not claimed during withdrawal"
        );
        emit log_named_uint("Claimable subsidy after withdrawal", claimableSubsidyAfterWithdrawal);
    }

    // @dev expects to be called from an address which holds WSTETH
    function measureWSTETH() public {
        uint256 wstEthBalance = WSTETH.balanceOf(tx.origin);
        vm.broadcast();
        WSTETH.transfer(address(gasBase), wstEthBalance);
        emit log_named_uint("WSTETH balance of gasBase", WSTETH.balanceOf(address(gasBase)));

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge),
                wstethAsset,
                emptyAsset,
                wewstethAsset,
                emptyAsset,
                wstEthBalance,
                0,
                0,
                BENEFICIARY,
                280000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 wewstethBalance = IERC20(wewstethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the weweth
        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("weweth balance of gasBase", wewstethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                wewstethAsset,
                emptyAsset,
                wstethAsset,
                emptyAsset,
                wewstethBalance / 2,
                1,
                1,
                BENEFICIARY,
                240000
            );
            emit log_named_uint(
                "wewstethBalance balance of gasBase", IERC20(wewstethAsset.erc20Address).balanceOf(address(gasBase))
                );
        }

        uint256 claimableSubsidyAfterWithdrawal = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(
            claimableSubsidyAfterWithdrawal, claimableSubsidyAfterDeposit, "Subsidy was not claimed during withdrawal"
        );
        emit log_named_uint("Claimable subsidy after withdrawal", claimableSubsidyAfterWithdrawal);
    }

    function measureCDAI() public {
        uint256 daiBalance = DAI.balanceOf(tx.origin);
        vm.broadcast();
        DAI.transfer(address(gasBase), daiBalance);
        emit log_named_uint("DAI balance of gasBase", DAI.balanceOf(address(gasBase)));

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge), daiAsset, emptyAsset, wcDaiAsset, emptyAsset, daiBalance, 0, 0, BENEFICIARY, 340000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);

        uint256 wcDaiBalance = IERC20(wcDaiAsset.erc20Address).balanceOf(address(gasBase));

        // No need to warp time here because withdrawal has different subsidy criteria
        {
            emit log_named_uint("wcDai balance of gasBase", wcDaiBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                wcDaiAsset,
                emptyAsset,
                daiAsset,
                emptyAsset,
                wcDaiBalance / 2,
                1,
                1,
                BENEFICIARY,
                250000
            );
            emit log_named_uint("wcDai balance of gasBase", IERC20(wcDaiAsset.erc20Address).balanceOf(address(gasBase)));
        }

        uint256 claimableSubsidyAfterWithdrawal = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(
            claimableSubsidyAfterWithdrawal, claimableSubsidyAfterDeposit, "Subsidy was not claimed during withdrawal"
        );
        emit log_named_uint("Claimable subsidy after withdrawal", claimableSubsidyAfterWithdrawal);
    }
}
