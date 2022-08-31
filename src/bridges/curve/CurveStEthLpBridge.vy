# @version >=0.3.6

from vyper.interfaces import ERC20

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

LP_TOKEN: immutable(address)
ROLLUP_PROCESSOR: immutable(address)

CURVE_ETH_INDEX: constant(int128) = 0
CURVE_STETH_INDEX: constant(int128) = 1

@external
def __init__(_rollupProcessor: address):
    ROLLUP_PROCESSOR = _rollupProcessor
    LP_TOKEN = ICurvePool(CURVE_POOL).lp_token()

    val: uint256 = max_value(uint256)
    ERC20(STETH).approve(CURVE_POOL, val, default_return_value = True)
    ERC20(STETH).approve(WSTETH, val, default_return_value = True)
    ERC20(LP_TOKEN).approve(ROLLUP_PROCESSOR, val, default_return_value = True)
    ERC20(WSTETH).approve(ROLLUP_PROCESSOR, val, default_return_value = True)    

@internal
def onlyRollup():
    assert msg.sender == ROLLUP_PROCESSOR, "Invalid caller"

@payable
@external
def __default__():
    pass

@internal
def _deposit(_value: uint256, _outputAssetA: AztecAsset, isEthInput: bool) -> (uint256, uint256, bool):
    outputValueA: uint256 = 0
    amounts: uint256[2] = [0, 0]

    if isEthInput:
        amounts[CURVE_ETH_INDEX] = _value
        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, 0, value = _value)
        return (outputValueA, 0, False)
    else:
        amounts[CURVE_STETH_INDEX] = IWstETh(WSTETH).unwrap(_value)
        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, 0)
        return (outputValueA, 0, False)

@internal
def _withdraw(_value: uint256, _outputAssetA: AztecAsset) -> (uint256, uint256, bool):
    amounts: uint256[2] = ICurvePool(CURVE_POOL).remove_liquidity(_value, [0, 0])
    wstEth: uint256 = IWstETh(WSTETH).wrap(amounts[1])
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
    self.onlyRollup()

    # Eth or wsteth in -> lp out
    deposit: bool = ((_inputAssetA.assetType == 1) or (_inputAssetA.assetType == 2 and _inputAssetA.erc20Address == WSTETH)) and _outputAssetA.assetType == 2 and _outputAssetA.erc20Address == LP_TOKEN

    # lp in -> eth + wsteth out
    withdraw: bool = _inputAssetA.assetType == 2 and _inputAssetA.erc20Address == LP_TOKEN and _outputAssetA.    assetType == 1 and _outputAssetB.assetType == 2 and _outputAssetB.erc20Address == WSTETH

    if not((deposit or withdraw) and not(deposit and withdraw)):
        raise "Invalid assets"

    if deposit:
        return self._deposit(_totalInputValue, _outputAssetA, _inputAssetA.assetType == 1)
    return self._withdraw(_totalInputValue, _outputAssetA)