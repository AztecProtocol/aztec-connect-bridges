export enum AztecAssetType {
  NOT_USED,
  ETH,
  ERC20,
  VIRTUAL,
}

export interface AztecAsset {
  id?: number;
  assetType?: AztecAssetType;
  erc20Address?: string;
}