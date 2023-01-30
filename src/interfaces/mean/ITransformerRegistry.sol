// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './ITransformer.sol';

/**
 * @title A registry for all existing transformers
 * @notice This contract will contain all registered transformers and act as proxy. When called
 *         the registry will find the corresponding transformer and delegate the call to it. If no
 *         transformer is found, then it will fail
 */
interface ITransformerRegistry is ITransformer {

  /**
   * @notice Returns the registered transformer for the given dependents
   * @param dependents The dependents to get the transformer for
   * @return The registered transformers, or the zero address if there isn't any
   */
  function transformers(address[] calldata dependents) external view returns (ITransformer[] memory);

  /**
   * @notice Executes a transformation to the underlying tokens, by taking the caller's entire
   *         dependent balance. This is meant to be used as part of a multi-hop swap
   * @dev This function was made payable, so that it could be multicalled when msg.value > 0
   * @param dependent The address of the dependent token
   * @param recipient The address that would receive the underlying tokens
   * @param minAmountOut The minimum amount of underlying that the caller expects to get. Will fail
   *                     if less is received. As a general rule, the underlying tokens should
   *                     be provided in the same order as `getUnderlying` returns them
   * @param deadline A deadline when the transaction becomes invalid
   * @return The transformed amount in each of the underlying tokens
   */
  function transformAllToUnderlying(
    address dependent,
    address recipient,
    UnderlyingAmount[] calldata minAmountOut,
    uint256 deadline
  ) external payable returns (UnderlyingAmount[] memory);

  /**
   * @notice Executes a transformation to the dependent token, by taking the caller's entire
   *         underlying balance. This is meant to be used as part of a multi-hop swap
   * @dev This function will not work when the underlying token is ETH/MATIC/BNB, since it can't be taken from the caller
   *      This function was made payable, so that it could be multicalled when msg.value > 0
   * @param dependent The address of the dependent token
   * @param recipient The address that would receive the dependent tokens
   * @param minAmountOut The minimum amount of dependent that the caller expects to get. Will fail
   *                     if less is received
   * @param deadline A deadline when the transaction becomes invalid
   * @return amountDependent The transformed amount in the dependent token
   */
  function transformAllToDependent(
    address dependent,
    address recipient,
    uint256 minAmountOut,
    uint256 deadline
  ) external payable returns (uint256 amountDependent);
}
