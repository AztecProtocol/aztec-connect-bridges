// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title A contract that can map between one token and their underlying counterparts, and vice-versa
 * @notice This contract defines the concept of dependent tokens. These are tokens that depend on one or more underlying tokens,
 *         they can't exist on their own. This concept can apply to some known types of tokens, such as:
 *           - Wrappers (WETH/WMATIC/WBNB)
 *           - ERC-4626 tokens
 *           - LP tokens
 *         Now, transformers are smart contract that knows how to map dependent tokens into their underlying counterparts,
 *         and vice-versa. We are doing this so that we can abstract the way tokens can be transformed between each other
 * @dev All non-view functions were made payable, so that they could be multicalled when msg.value > 0
 */
interface ITransformer {
  /// @notice An amount of an underlying token
  struct UnderlyingAmount {
    address underlying;
    uint256 amount;
  }

  /**
   * @notice Returns the addresses of all the underlying tokens, for the given dependent
   * @dev This function must be unaware of context. The returned values must be the same,
   *      regardless of who the caller is
   * @param dependent The address of the dependent token
   * @return The addresses of all the underlying tokens
   */
  function getUnderlying(address dependent) external view returns (address[] memory);

  /**
   * @notice Calculates how much would the transformation to the underlying tokens return
   * @dev This function must be unaware of context. The returned values must be the same,
   *      regardless of who the caller is
   * @param dependent The address of the dependent token
   * @param amountDependent The amount to transform
   * @return The transformed amount in each of the underlying tokens
   */
  function calculateTransformToUnderlying(address dependent, uint256 amountDependent) external view returns (UnderlyingAmount[] memory);

  /**
   * @notice Calculates how much would the transformation to the dependent token return
   * @dev This function must be unaware of context. The returned values must be the same,
   *      regardless of who the caller is
   * @param dependent The address of the dependent token
   * @param underlying The amounts of underlying tokens to transform
   * @return amountDependent The transformed amount in the dependent token
   */
  function calculateTransformToDependent(address dependent, UnderlyingAmount[] calldata underlying)
    external
    view
    returns (uint256 amountDependent);

  /**
   * @notice Calculates how many dependent tokens are needed to transform to the expected
   *         amount of underlying
   * @dev This function must be unaware of context. The returned values must be the same,
   *      regardless of who the caller is
   * @param dependent The address of the dependent token
   * @param expectedUnderlying The expected amounts of underlying tokens
   * @return neededDependent The amount of dependent needed
   */
  function calculateNeededToTransformToUnderlying(address dependent, UnderlyingAmount[] calldata expectedUnderlying)
    external
    view
    returns (uint256 neededDependent);

  /**
   * @notice Calculates how many underlying tokens are needed to transform to the expected
   *         amount of dependent
   * @dev This function must be unaware of context. The returned values must be the same,
   *      regardless of who the caller is
   * @param dependent The address of the dependent token
   * @param expectedDependent The expected amount of dependent tokens
   * @return neededUnderlying The amount of underlying tokens needed
   */
  function calculateNeededToTransformToDependent(address dependent, uint256 expectedDependent)
    external
    view
    returns (UnderlyingAmount[] memory neededUnderlying);

  /**
   * @notice Executes the transformation to the underlying tokens
   * @param dependent The address of the dependent token
   * @param amountDependent The amount to transform
   * @param recipient The address that would receive the underlying tokens
   * @param minAmountOut The minimum amount of underlying that the caller expects to get. Will fail
   *                     if less is received. As a general rule, the underlying tokens should
   *                     be provided in the same order as `getUnderlying` returns them
   * @param deadline A deadline when the transaction becomes invalid
   * @return The transformed amount in each of the underlying tokens
   */
  function transformToUnderlying(
    address dependent,
    uint256 amountDependent,
    address recipient,
    UnderlyingAmount[] calldata minAmountOut,
    uint256 deadline
  ) external payable returns (UnderlyingAmount[] memory);

  /**
   * @notice Executes the transformation to the dependent token
   * @param dependent The address of the dependent token
   * @param underlying The amounts of underlying tokens to transform
   * @param recipient The address that would receive the dependent tokens
   * @param minAmountOut The minimum amount of dependent that the caller expects to get. Will fail
   *                     if less is received
   * @param deadline A deadline when the transaction becomes invalid
   * @return amountDependent The transformed amount in the dependent token
   */
  function transformToDependent(
    address dependent,
    UnderlyingAmount[] calldata underlying,
    address recipient,
    uint256 minAmountOut,
    uint256 deadline
  ) external payable returns (uint256 amountDependent);

  /**
   * @notice Transforms dependent tokens to an expected amount of underlying tokens
   * @param dependent The address of the dependent token
   * @param expectedUnderlying The expected amounts of underlying tokens
   * @param recipient The address that would receive the underlying tokens
   * @param maxAmountIn The maximum amount of dependent that the caller is willing to spend.
   *                    Will fail more is needed
   * @param deadline A deadline when the transaction becomes invalid
   * @return spentDependent The amount of spent dependent tokens
   */
  function transformToExpectedUnderlying(
    address dependent,
    UnderlyingAmount[] calldata expectedUnderlying,
    address recipient,
    uint256 maxAmountIn,
    uint256 deadline
  ) external payable returns (uint256 spentDependent);

  /**
   * @notice Transforms underlying tokens to an expected amount of dependent tokens
   * @param dependent The address of the dependent token
   * @param expectedDependent The expected amounts of dependent tokens
   * @param recipient The address that would receive the underlying tokens
   * @param maxAmountIn The maximum amount of underlying that the caller is willing to spend.
   *                    Will fail more is needed. As a general rule, the underlying tokens should
   *                    be provided in the same order as `getUnderlying` returns them
   * @param deadline A deadline when the transaction becomes invalid
   * @return spentUnderlying The amount of spent underlying tokens
   */
  function transformToExpectedDependent(
    address dependent,
    uint256 expectedDependent,
    address recipient,
    UnderlyingAmount[] calldata maxAmountIn,
    uint256 deadline
  ) external payable returns (UnderlyingAmount[] memory spentUnderlying);
}
