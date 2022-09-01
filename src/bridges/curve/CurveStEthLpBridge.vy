# @version >=0.3.6

"""
@title  A bridge for entering and exiting a Curve LP position for the eth/steth pool
@licence Apache-2.0
@author Aztec team
@notice You can use this bridge to enter or exit positions on the eth/steth pool
        Can be entered with either eth or steth, but will always exit with both.
"""

from vyper.interfaces import ERC20

interface IRollupProcessor:
    def receiveEthFromBridge(_interactionNonce: uint256): payable

interface ICurvePool:
    def add_liquidity(amounts: uint256[2], min_mint_amount: uint256) -> uint256: payable
    def remove_liquidity(_amount: uint256, _min_amounts: uint256[2]) -> uint256[2]: nonpayable
    def lp_token() -> address: view

interface IWstETh:
    def unwrap(val: uint256) -> uint256: nonpayable
    def wrap(val: uint256) -> uint256: nonpayable

struct AztecAsset:
    id: uint256
    erc20Address: address
    assetType: uint8 # solidity and vyper enums differ, (NON_USED, ETH, ERC20, VIRTUAL)

STETH: constant(address) = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
WSTETH: constant(address) = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
CURVE_POOL: constant(address) = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022
CURVE_ETH_INDEX: constant(int128) = 0
CURVE_STETH_INDEX: constant(int128) = 1
SLIPPAGE_PRECISION: constant(uint256) = 1000000

LP_TOKEN: immutable(address)
ROLLUP_PROCESSOR: immutable(address)

@external
def __init__(_rollupProcessor: address):
    """
    @notice Store address of the rollup processor and lp-token and perform pre-approvals
    @dev    Preapprovals can be used to save gas, and as as the bridge won't hold any funds
            and there are no approvals to it there are no direct funds to steal if approved
            party becomes malicious.
    """
    ROLLUP_PROCESSOR = _rollupProcessor
    LP_TOKEN = ICurvePool(CURVE_POOL).lp_token()

    val: uint256 = max_value(uint256)
    ERC20(STETH).approve(CURVE_POOL, val, default_return_value = True)
    ERC20(STETH).approve(WSTETH, val, default_return_value = True)
    ERC20(LP_TOKEN).approve(ROLLUP_PROCESSOR, val, default_return_value = True)
    ERC20(WSTETH).approve(ROLLUP_PROCESSOR, val, default_return_value = True)    


@payable
@external
def __default__():
    """
    @notice Default used to accept Eth from pool when exiting
    """
    pass


@internal
def _deposit(_value: uint256, _isEthInput: bool, _auxData: uint64) -> (uint256, uint256, bool):
    """
    @notice Perform a deposit (adding liquidity) to the curve pool
    @param  _value The amount of token to deposit
    @param  _isEthInput A flag describing whether Eth is used as input or not
    @dev    When Eth is not the input, input must be WSTETH, which is unwrapped before adding liquidity
    @return outputValueA - The amount of LP-token to receive 
    @return outputValueB - Always zero for this bridge
    @return isAsync - Always false for this bridge
    """
    outputValueA: uint256 = 0
    amounts: uint256[2] = [0, 0]
    minOut: uint256 = (_value * convert(_auxData, uint256)) / SLIPPAGE_PRECISION

    if _isEthInput:
        amounts[CURVE_ETH_INDEX] = _value
        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, minOut, value = _value)
        return (outputValueA, 0, False)
    else:
        amounts[CURVE_STETH_INDEX] = IWstETh(WSTETH).unwrap(_value)
        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, minOut)
        return (outputValueA, 0, False)



@internal
def _withdraw(_value: uint256, _interactionNonce: uint256, _auxData: uint64) -> (uint256, uint256, bool):
    """
    @notice Performs a withdrawal from LP-token to (eth, wsteth)
    @dev    Will exit to eth and steth, and then wrap the steth before returning
    @param  _value - The amount of LP-token to withdraw
    @param  _interactionNonce - The unique identifier of the defi interaction
    @return outputValueA - The amount of eth to retrieve
    @return outputBalueB - The amount of wsteth to retrive
    @return isAsync - Always false for this bridge
    """
    minAmounts: uint256[2] = [0, 0]
    minAmounts[CURVE_ETH_INDEX] = _value * (convert(_auxData, uint256) & (2**32 - 1)) / SLIPPAGE_PRECISION
    minAmounts[CURVE_STETH_INDEX] = _value * (shift(convert(_auxData, uint256), -32) & (2**32 - 1)) / SLIPPAGE_PRECISION

    amounts: uint256[2] = ICurvePool(CURVE_POOL).remove_liquidity(_value, minAmounts)
    wstEth: uint256 = IWstETh(WSTETH).wrap(amounts[1])
    IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge(_interactionNonce, value = amounts[0])
    return (amounts[0], wstEth, False)


@payable
@external
def convert_11192637865(
    _inputAssetA: AztecAsset,
    _inputAssetB: AztecAsset,
    _outputAssetA: AztecAsset,
    _outputAssetB: AztecAsset,
    _totalInputValue: uint256,
    _interactionNonce: uint256,
    _auxData: uint64,
    _rollupBeneficiary: address
) -> (uint256, uint256, bool):
    """
    @notice Function called by the defi proxy, executes deposit or withdrawal depending on input 
    @dev    Instead of `convert` named `convert_11192637865` to work around the `convert` keyword
            while still having the same selector.
    @param  _inputAssetA - The first Aztec Asset to input the call, will be (LPToken or eth or wsteth)
    @param  _inputAssetB - Always empty for this bridge
    @param  _outputAssetA - The first aztec asset to receive from the call, will be (LPToken or eth)
    @param  _outputAssetB - The second aztec asset to receive from the call, will be (none or wsteth)
    @param  _totalInputValue - The amount of token to deposit or withdraw
    @param  _interactionNonce - The unique identifier for this defi interaction
    @param  _auxData - Auxiliary data that can be used by the bridge
    @param  _rollupBeneficiary - The address of the beneficiary of subsidies
    @return OutputValueA - The amount of outputAssetA that the rollup should pull
    @return OutputValueB - The amount of outputAssetB that the rollup should pull
    @return isAsync - True if the bridge is async, false otherwise. Always false for this bridge
    """
    assert msg.sender == ROLLUP_PROCESSOR, "Invalid caller"

    if _inputAssetB.assetType != 0:
        raise "Invalid asset B"

    # Eth or wsteth in -> lp out
    deposit: bool = (_inputAssetA.assetType == 1 or (_inputAssetA.assetType == 2 and _inputAssetA.erc20Address == WSTETH)) and _outputAssetA.assetType == 2 and _outputAssetA.erc20Address == LP_TOKEN

    # lp in -> eth + wsteth out
    withdraw: bool = _inputAssetA.assetType == 2 and _inputAssetA.erc20Address == LP_TOKEN and _outputAssetA.assetType == 1 and _outputAssetB.assetType == 2 and _outputAssetB.erc20Address == WSTETH

    if not((deposit or withdraw) and not(deposit and withdraw)):
        raise "Invalid assets"

    if deposit:
        return self._deposit(_totalInputValue, _inputAssetA.assetType == 1, _auxData)
    return self._withdraw(_totalInputValue, _interactionNonce, _auxData)