// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniswapDCABridge} from "../../../bridges/dca/UniswapDCABridge.sol";

contract TestDCABridge is UniswapDCABridge {
    using SafeERC20 for IERC20;

    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize,
        address _oracle
    ) UniswapDCABridge(_rollupProcessor, _assetA, _assetB, _tickSize, _oracle) {}

    function rebalanceTest(
        uint256 _a,
        uint256 _b,
        uint256 _price,
        bool _self,
        bool _transfer
    ) public returns (int256, int256) {
        // Only for testing
        (int256 flowA, int256 flowB, , ) = _rebalanceAndfill(_a, _b, _price, _self);

        if (_transfer) {
            if (flowA > 0) {
                ASSET_A.safeTransferFrom(msg.sender, address(this), uint256(flowA));
            } else if (flowA < 0) {
                ASSET_A.safeTransfer(msg.sender, uint256(-flowA));
            }

            if (flowB > 0) {
                ASSET_B.safeTransferFrom(msg.sender, address(this), uint256(flowB));
            } else if (flowB < 0) {
                ASSET_B.safeTransfer(msg.sender, uint256(-flowB));
            }
        }
        return (flowA, flowB);
    }
}
