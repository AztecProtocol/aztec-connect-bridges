// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";
import {IHintHelpers} from "../../interfaces/liquity/IHintHelpers.sol";
import {ITroveManager} from "../../interfaces/liquity/ITroveManager.sol";
import {ISortedTroves} from "../../interfaces/liquity/ISortedTroves.sol";

contract LiquityTroveDeployment is BaseDeployment {
    IHintHelpers internal constant HINT_HELPERS = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ITroveManager public constant TROVE_MANAGER = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves internal constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    uint64 internal constant MAX_FEE = 1e16; // Slippage protection: 1%
    // From LiquityMath.sol
    uint256 internal constant NICR_PRECISION = 1e20;

    function deploy(uint256 _initialCr) public returns (address) {
        emit log("Deploying trove bridge");

        vm.broadcast();
        TroveBridge bridge = new TroveBridge(ROLLUP_PROCESSOR, _initialCr);

        emit log_named_address("Trove bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList(uint256 _initialCr) public {
        address bridge = deploy(_initialCr);
        uint256 addressId = listBridge(bridge, 700_000);
        emit log_named_uint("Trove bridge address id", addressId);

        listAsset(TroveBridge(payable(bridge)).LUSD(), 55_000);
        listAsset(bridge, 55_000);

        openTrove(bridge);
    }

    function openTrove(address _bridge) public {
        TroveBridge bridge = TroveBridge(payable(_bridge));

        // 2100 LUSD --> 1800 LUSD is minimum but we also need to cover borrowing fee + liquidation reserve
        uint256 amtToBorrow = 21e20;
        uint256 collateral = _computeRequiredCollateral(amtToBorrow, bridge.INITIAL_ICR());

        emit log_named_uint("Collateral", collateral);

        uint256 nicr = (collateral * NICR_PRECISION) / amtToBorrow;

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint,,) = HINT_HELPERS.getApproxHint(nicr, numTrials, randomSeed);
        (address upperHint, address lowerHint) = SORTED_TROVES.findInsertPosition(nicr, approxHint, approxHint);

        // Open the trove
        vm.broadcast();
        bridge.openTrove{value: collateral}(upperHint, lowerHint, MAX_FEE);

        uint256 status = TROVE_MANAGER.getTroveStatus(address(bridge));
        emit log_named_uint("Trove status", status);
        assertEq(status, 1, "Incorrect trove status - opening the trove failed");
    }

    function _computeRequiredCollateral(uint256 _amtToBorrow, uint256 _icr) internal returns (uint256) {
        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        return (_amtToBorrow * _icr) / price;
    }
}
