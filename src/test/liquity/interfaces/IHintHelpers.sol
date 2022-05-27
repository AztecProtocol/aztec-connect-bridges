// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IHintHelpers {
    function getApproxHint(
        uint256 _CR,
        uint256 _numTrials,
        uint256 _inputRandomSeed
    )
        external
        view
        returns (
            address hintAddress,
            uint256 diff,
            uint256 latestRandomSeed
        );
}
