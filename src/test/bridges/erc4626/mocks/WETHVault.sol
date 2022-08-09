// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract WETHVault is
    ERC20("WETH vault", "vWETH"),
    ERC4626(IERC20Metadata(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2))
{}
