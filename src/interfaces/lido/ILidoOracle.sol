// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ILidoOracle {
    function getLastCompletedReportDelta()
        external
        view
        returns (uint256 postTotalPooledEther, uint256 preTotalPooledEther, uint256 timeElapsed);
}
