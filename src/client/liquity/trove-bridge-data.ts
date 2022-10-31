import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { ITroveManager, ITroveManager__factory, TroveBridge__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

export class TroveBridgeData implements BridgeDataFieldGetters {
  public readonly LUSD = EthAddress.fromString("0x5f98805A4E8be255a32880FDeC7F6728C6568bA0");
  public readonly MAX_FEE = 2 * 10 ** 16; // 2 % borrowing fee

  protected constructor(
    protected ethersProvider: Web3Provider,
    protected tb: EthAddress,
    protected troveManager: ITroveManager,
  ) {}

  static create(provider: EthereumProvider, tb: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const troveManager = ITroveManager__factory.connect("0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", ethersProvider);
    return new TroveBridgeData(ethersProvider, tb, troveManager);
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData is only used when borrowing and represent max borrowing fee",
    },
  ];

  /**
   * @dev Returns 2 percent borrowing fee when the input/output asset combination corresponds to borrowing. Return
   *      value is always 0 otherwise.
   * @dev I decided to return 2 % because it seems to be a reasonable value which should not cause revert
   *      in the future (Liquity's borrowing fee is currently 0.5 % and I don't expect it to rise above 2 %)
   */
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    if (
      inputAssetA.assetType === AztecAssetType.ETH &&
      inputAssetB.assetType === AztecAssetType.NOT_USED &&
      outputAssetA.erc20Address.equals(this.tb) &&
      outputAssetB.erc20Address.equals(this.LUSD)
    ) {
      return [this.MAX_FEE];
    }
    return [0];
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    const bridge = TroveBridge__factory.connect(this.tb.toString(), this.ethersProvider);
    if (
      inputAssetA.assetType === AztecAssetType.ETH &&
      inputAssetB.assetType === AztecAssetType.NOT_USED &&
      outputAssetA.erc20Address.equals(this.tb) &&
      outputAssetB.erc20Address.equals(this.LUSD)
    ) {
      const amountOut = await bridge.callStatic.computeAmtToBorrow(inputValue);
      // Borrowing
      return [amountOut.toBigInt()];
    } else if (
      inputAssetA.erc20Address.equals(this.tb) &&
      inputAssetB.erc20Address.equals(this.LUSD) &&
      outputAssetA.assetType === AztecAssetType.ETH
    ) {
      // Repaying
      const tbTotalSupply = await bridge.totalSupply();

      const { debt, coll, pendingLUSDDebtReward, pendingETHReward } = await this.troveManager.getEntireDebtAndColl(
        this.tb.toString(),
      );

      if (inputAssetB.erc20Address.equals(this.LUSD)) {
        const collateralToWithdraw = (inputValue * coll.toBigInt()) / tbTotalSupply.toBigInt();
        if (outputAssetB.erc20Address.equals(this.LUSD)) {
          const debtToRepay = (inputValue * debt.toBigInt()) / tbTotalSupply.toBigInt();
          const lusdReturned = inputValue - debtToRepay;
          return [collateralToWithdraw, lusdReturned];
        } else if (outputAssetB.erc20Address.equals(this.tb)) {
          // Repaying after redistribution flow
          // Note: this code assumes the flash swap doesn't fail (if it would fail some tb would get returned)
          return [collateralToWithdraw, 0n];
        }
      } else if (
        inputAssetB.assetType === AztecAssetType.NOT_USED &&
        outputAssetB.assetType === AztecAssetType.NOT_USED
      ) {
        // Redeeming
        // Fetching bridge's ETH balance because it's possible the collateral was already claimed
        const ethHeldByBridge = (await this.ethersProvider.getBalance(this.tb.toString())).toBigInt();
        const collateralToWithdraw = (inputValue * (coll.toBigInt() + ethHeldByBridge)) / tbTotalSupply.toBigInt();
        return [collateralToWithdraw, 0n];
      }
    }
    throw "Incorrect combination of input/output assets.";
  }
}
