// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEulerEToken} from "../../../interfaces/euler/IEulerEtoken.sol";
import {EulerLendingBridge} from "../../../bridges/euler/EulerLendingBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract EulerTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    struct Balances {
        uint256 underlyingBefore;
        uint256 underlyingMid;
        uint256 underlyingEnd;
        uint256 cBefore;
        uint256 cMid;
        uint256 cEnd;
    }
    
    EulerLendingBridge internal bridge;
    uint256 internal id;
    mapping(address => bool) internal isDeprecated;
    
     function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new EulerLendingBridge(address(ROLLUP_PROCESSOR));
        bridge.preApproveAll();
        vm.label(address(bridge), "EULER_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        isDeprecated[0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1] = true; // cREP - Augur v1
        isDeprecated[0xC11b1268C1A384e55C48c2391d8d480264A3A7F4] = true; // legacy cWBTC token
        isDeprecated[0xF5DCe57282A584D2746FaF1593d3121Fcac444dC] = true; // cSAI
    }
    
    

    
