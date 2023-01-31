// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

library MeanErrorLib {

    /// @notice Thrown when trying to registered a token that is not suported by Mean
    error TokenNotAllowed(address token);

    /// @notice Thrown when trying to register a token that is already registered
    error TokenAlreadyRegistered(address token);
    
}
