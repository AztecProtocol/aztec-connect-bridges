// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

library ErrorLib {
    error InvalidCaller();

    error InvalidInput();
    error InvalidInputA();
    error InvalidInputB();
    error InvalidOutputA();
    error InvalidOutputB();
    error InvalidInputAmount();
    error InvalidAuxData();

    error ApproveFailed(address token);
    error TransferFailed(address token);

    error InvalidNonce();
    error AsyncDisabled();
}
