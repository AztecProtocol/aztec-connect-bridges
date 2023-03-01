// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.7;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract DCAHubSwapperMock {

  struct TokenInSwap {
    address token;
    uint256 reward;
    uint256 toProvide;
    uint256 platformFee;
  }

  // solhint-disable-next-line func-name-mixedcase
  function DCAHubSwapCall(
    address,
    TokenInSwap[] calldata _tokens,
    uint256[] calldata,
    bytes calldata
  ) external {

    for (uint256 i; i < _tokens.length; i++) {
      uint256 _amountToProvide = _tokens[i].toProvide;
      if (_amountToProvide > 0) {
        IERC20(_tokens[i].token).transfer(msg.sender, _amountToProvide);
      }
    }
  }
}
