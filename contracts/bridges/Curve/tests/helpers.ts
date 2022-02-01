import hre, { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { ERC20 } from "../../../../typechain-types";
import * as mainnet from './mainnet';

export async function fundERC20FromAccount(
  erc20: ERC20,
  from: string,
  to: string,
  amount: BigNumber
) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [from],
  });
  await hre.network.provider.send("hardhat_setBalance", [
    from,
    ethers.utils.hexStripZeros(ethers.utils.parseEther("100.0").toHexString()),
  ]);
  const holder = await ethers.getSigner(from);
  await erc20.connect(holder).transfer(to, amount);
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [from],
  });
}

export const tokenPairs = function* (swaps: string[][]) {
  for (let tokenSet of swaps) {
    for (let i = 0; i < tokenSet.length; i++) {
      for (let j = i + 1; j < tokenSet.length; j++) {
        const token1 = {
          name: tokenSet[i],
          address: mainnet.tokens[tokenSet[i]].address,
          holder: mainnet.tokens[tokenSet[i]].holder,
        };
        const token2 = {
          name: tokenSet[j],
          address: mainnet.tokens[tokenSet[j]].address,
          holder: mainnet.tokens[tokenSet[j]].holder,
        };
        yield [token1, token2];
        yield [token2, token1];
      }
    }
  }
};