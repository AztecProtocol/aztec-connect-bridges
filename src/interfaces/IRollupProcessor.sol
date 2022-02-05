// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface IRollupProcessor {
  function processAsyncDeFiInteraction(uint256 interactionNonce) external;

  function receiveEthFromBridge(uint256 interactionNonce) external payable;
}
