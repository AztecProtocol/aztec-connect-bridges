// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStableMaster {
    struct MintBurnData {
        uint64[] xFeeMint;
        uint64[] yFeeMint;
        uint64[] xFeeBurn;
        uint64[] yFeeBurn;
        uint64 targetHAHedge;
        uint64 bonusMalusMint;
        uint64 bonusMalusBurn;
        uint256 capOnStableMinted;
    }

    struct SLPData {
        uint256 lastBlockUpdated;
        uint256 lockedInterests;
        uint256 maxInterestsDistributed;
        uint256 feesAside;
        uint64 slippageFee;
        uint64 feesForSLPs;
        uint64 slippage;
        uint64 interestsForSLPs;
    }

    function deposit(
        uint256 amount,
        address user,
        address poolManager
    ) external;

    function withdraw(
        uint256 amount,
        address burner,
        address dest,
        address poolManager
    ) external;

    function agToken() external returns (address);

    function collateralMap(address poolManager)
        external
        view
        returns (
            IERC20 token,
            address sanToken,
            address perpetualManager,
            address oracle,
            uint256 stocksUsers,
            uint256 sanRate,
            uint256 collatBase,
            SLPData memory slpData,
            MintBurnData memory feeData
        );
}
