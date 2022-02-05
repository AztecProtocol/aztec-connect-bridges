// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.11;
pragma experimental ABIEncoderV2;

import { AztecTypes } from "../aztec/AztecTypes.sol";

interface IDefiBridge {
  /**
   * Input cases:
   * Case1: 1 real input.
   * Case2: 1 virtual asset input.
   * Case3: 1 real 1 virtual input.
   *
   * Output cases:
   * Case1: 1 real
   * Case2: 2 real
   * Case3: 1 real 1 virtual
   * Case4: 1 virtual
   *
   * Example use cases with asset mappings
   * 1 1: Swapping.
   * 1 2: Swapping with incentives (2nd output reward token).
   * 1 3: Borrowing. Lock up collateral, get back loan asset and virtual position asset.
   * 1 4: Opening lending position OR Purchasing NFT. Input real asset, get back virtual asset representing NFT or position.
   * 2 1: Selling NFT. Input the virtual asset, get back a real asset.
   * 2 2: Closing a lending position. Get back original asset and reward asset.
   * 2 3: Claiming fees from an open position.
   * 2 4: Voting on a 1 4 case.
   * 3 1: Repaying a borrow. Return loan plus interest. Get collateral back.
   * 3 2: Repaying a borrow. Return loan plus interest. Get collateral plus reward token. (AAVE)
   * 3 3: Partial loan repayment.
   * 3 4: DAO voting stuff.
   */

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggreagte sum of all users funds for the input assets.
  // @param AztecAsset inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset outputAssetB a struct detailing an optional second output asset
  // @param uint256 inputValue, the total amount input, if there are two input assets, equal amounts of both assets will have been input
  // @param uint256 interactionNonce a globally unique identifier for this DeFi interaction. This is used as the assetId if one of the output assets is virtual
  // @param uint64 auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the amount of outputAssetA returned from this interaction, should be 0 if async
  // @return uint256 outputValueB the amount of outputAssetB returned from this interaction, should be 0 if async or bridge only returns 1 asset.
  // @return bool isAsync a flag to toggle if this bridge interaction will return assets at a later date after some third party contract has interacted with it via finalise()
  function convert(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 inputValue,
    uint256 interactionNonce,
    uint64 auxData
  )
    external
    payable
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool isAsync
    );

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggreagte sum of all users funds for the input assets.
  // @param AztecAsset inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset outputAssetB a struct detailing an optional second output asset
  // @param uint256 interactionNonce
  // @param uint64 auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the return value of output asset A
  // @return uint256 outputValueB optional return value of output asset B
  // @dev this function should have a modifier on it to ensure it can only be called by the Rollup Contract
  function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
  ) external payable returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete);


}
