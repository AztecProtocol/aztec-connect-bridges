import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import {
  IPriceFeed__factory,
  ITroveManager,
  ITroveManager__factory,
  TroveBridge,
  TroveBridge__factory,
} from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

export class TroveBridgeData implements BridgeDataFieldGetters {
  public readonly LUSD = EthAddress.fromString("0x5f98805A4E8be255a32880FDeC7F6728C6568bA0");
  public readonly MAX_FEE = 2 * 10 ** 16; // 2 % borrowing fee
  private price?: BigNumber;

  protected constructor(
    protected ethersProvider: Web3Provider,
    protected bridge: TroveBridge,
    protected troveManager: ITroveManager,
  ) {}

  /**
   * @param provider Ethereum provider
   * @param bridgeAddress Address of the bridge address (and the corresponding accounting token)
   */
  static create(provider: EthereumProvider, bridgeAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const troveManager = ITroveManager__factory.connect("0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", ethersProvider);
    const bridge = TroveBridge__factory.connect(bridgeAddress.toString(), ethersProvider);
    return new TroveBridgeData(ethersProvider, bridge, troveManager);
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
      outputAssetA.erc20Address.equals(EthAddress.fromString(this.bridge.address)) &&
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
    const bridge = TroveBridge__factory.connect(this.bridge.address, this.ethersProvider);
    if (
      inputAssetA.assetType === AztecAssetType.ETH &&
      inputAssetB.assetType === AztecAssetType.NOT_USED &&
      outputAssetA.erc20Address.equals(EthAddress.fromString(this.bridge.address)) &&
      outputAssetB.erc20Address.equals(this.LUSD)
    ) {
      const amountOut = await bridge.callStatic.computeAmtToBorrow(inputValue);
      // Borrowing
      return [amountOut.toBigInt()];
    } else if (
      inputAssetA.erc20Address.equals(EthAddress.fromString(this.bridge.address)) &&
      outputAssetA.assetType === AztecAssetType.ETH
    ) {
      // Repaying
      const tbTotalSupply = await bridge.totalSupply();

      const { debt, coll, pendingLUSDDebtReward, pendingETHReward } = await this.troveManager.getEntireDebtAndColl(
        this.bridge.address,
      );

      if (inputAssetB.erc20Address.equals(this.LUSD)) {
        const collateralToWithdraw = (inputValue * coll.toBigInt()) / tbTotalSupply.toBigInt();
        if (outputAssetB.erc20Address.equals(this.LUSD)) {
          const debtToRepay = (inputValue * debt.toBigInt()) / tbTotalSupply.toBigInt();
          const lusdReturned = inputValue - debtToRepay;
          return [collateralToWithdraw, lusdReturned];
        } else if (outputAssetB.erc20Address.equals(EthAddress.fromString(this.bridge.address))) {
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
        const ethHeldByBridge = (await this.ethersProvider.getBalance(this.bridge.address)).toBigInt();
        const collateralToWithdraw = (inputValue * (coll.toBigInt() + ethHeldByBridge)) / tbTotalSupply.toBigInt();
        return [collateralToWithdraw, 0n];
      }
    }
    throw "Incorrect combination of input/output assets.";
  }

  /**
   * @notice This function computes borrowing fee for a given borrow amount
   * @param borrowAmount An amount of LUSD borrowed
   * @return amount of fee to be paid for a given borrow amount (in LUSD)
   */
  async getBorrowingFee(borrowAmount: bigint): Promise<bigint> {
    const isRecoveryMode = await this.troveManager.checkRecoveryMode(await this.fetchPrice());
    if (isRecoveryMode) {
      return 0n;
    }

    const borrowingRate = await this.troveManager.getBorrowingRateWithDecay();
    return (borrowingRate.toBigInt() * borrowAmount) / 10n ** 18n;
  }

  /**
   * @notice Returns current collateral ratio of the bridge
   * @return Current collateral ratio of the bridge denominated in percents
   */
  async getCurrentCR(): Promise<bigint> {
    const cr = await this.troveManager.getCurrentICR(this.bridge.address, await this.fetchPrice());
    return cr.toBigInt() / 10n ** 16n;
  }

  /**
   * @notice Returns debt and collateral corresponding to a given accounting token amount (TB token)
   * @return Debt corresponding to a given accounting token amount
   * @return Collateral corresponding to a given accounting token amount
   */
  async getUserDebtAndCollateral(tbAmount: bigint): Promise<[bigint, bigint]> {
    const tbTotalSupply = await this.bridge.totalSupply();

    const { debt, coll, pendingLUSDDebtReward, pendingETHReward } = await this.troveManager.getEntireDebtAndColl(
      this.bridge.address,
    );

    const userDebt = (tbAmount * debt.toBigInt()) / tbTotalSupply.toBigInt();
    const userCollateral = (tbAmount * coll.toBigInt()) / tbTotalSupply.toBigInt();

    return [userDebt, userCollateral];
  }

  private async fetchPrice(): Promise<BigNumber> {
    if (this.price === undefined) {
      const priceFeedAddress = await this.troveManager.priceFeed();
      const priceFeed = IPriceFeed__factory.connect(priceFeedAddress, this.ethersProvider);
      this.price = await priceFeed.callStatic.fetchPrice();
    }

    return this.price;
  }
}
