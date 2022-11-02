// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {LiquityTroveDeployment, BaseDeployment} from "../../deployment/liquity/LiquityTroveDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";
import "../../interfaces/liquity/IHintHelpers.sol";
import "../../interfaces/liquity/ITroveManager.sol";
import "../../interfaces/liquity/ISortedTroves.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract TroveBridgeMeasure is LiquityTroveDeployment {
    ISubsidy private constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    address private constant BENEFICIARY = address(uint160(uint256(keccak256(abi.encodePacked("_BENEFICIARY")))));

    IHintHelpers internal constant HINT_HELPERS = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ITroveManager public constant TROVE_MANAGER = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves internal constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    uint256 internal constant OWNER_ETH_BALANCE = 5 ether;
    uint64 internal constant MAX_FEE = 5e16; // Slippage protection: 5%
    // From LiquityMath.sol
    uint256 internal constant NICR_PRECISION = 1e20;

    GasBase internal gasBase;
    TroveBridge internal bridge;

    AztecTypes.AztecAsset internal emptyAsset;
    AztecTypes.AztecAsset internal ethAsset;
    AztecTypes.AztecAsset internal lusdAsset;
    AztecTypes.AztecAsset internal tbAsset; // Accounting token

    function setUp() public override(BaseDeployment) {
        super.setUp();

        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        bridge = TroveBridge(payable(deploy()));
        ROLLUP_PROCESSOR = temp;

        ethAsset = AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        lusdAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        tbAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(bridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // List vaults and fund subsidy
        //        vm.startBroadcast();
        //        SUBSIDY.subsidize{value: 1e17}(
        //            address(bridge),
        //            bridge.computeCriteria(wewethAsset, emptyAsset, lusdAsset, emptyAsset, 0),
        //            500
        //        );
        //        SUBSIDY.registerBeneficiary(BENEFICIARY);
        //        vm.stopBroadcast();

        // Warp time to increase subsidy
        vm.warp(block.timestamp + 10 days);
    }

    function measureETH() public {
        _openTrove();
        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("ETH balance of gasBase", address(gasBase).balance);

        // Borrow
        {
            vm.broadcast();
            gasBase.convert(
                address(bridge),
                ethAsset,
                emptyAsset,
                tbAsset,
                lusdAsset,
                1 ether,
                0,
                MAX_FEE, // accept up to 5 % borrowing fee
                BENEFICIARY,
                500000
            );
        }

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(claimableSubsidyAfterDeposit, 0, "Subsidy was not claimed during deposit");
        emit log_named_uint("Claimable subsidy after deposit", claimableSubsidyAfterDeposit);
    }

    function _openTrove() internal {
        uint256 amtToBorrow = bridge.computeAmtToBorrow(OWNER_ETH_BALANCE);
        uint256 nicr = (OWNER_ETH_BALANCE * NICR_PRECISION) / amtToBorrow;

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = HINT_HELPERS.getApproxHint(nicr, numTrials, randomSeed);
        (address upperHint, address lowerHint) = SORTED_TROVES.findInsertPosition(nicr, approxHint, approxHint);

        // Open the trove
        vm.broadcast();
        bridge.openTrove{value: OWNER_ETH_BALANCE}(upperHint, lowerHint, MAX_FEE);
    }
}
