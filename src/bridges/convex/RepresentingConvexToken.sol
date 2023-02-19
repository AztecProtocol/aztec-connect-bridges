// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @notice ERC20 token deployed for a specific pool to represent pool specific Convex LP token.
 * @dev Convex LP token : Curve LP token -> always 1:1
 * @dev RCT is proportionally minted to the amount of staked and bridge owned Curve LP tokens.
 * @dev RCT : Curve LP tokens = 1e10 : 1.
 * @dev RCT is only minted for the owner (the bridge) by the owner -> is fully owned by the bridge.
 * @dev RCT is an ERC20 upgradable token which allows initialization after the time it was deployed.
 * @dev RCT implementation is deployed on bridge deployment.
 * @dev RCT is a proxied contract and is called via a clone that is created for each loaded pool.
 * @dev Clone is tied to the RCT implementation by calling the `initialize` function.
 */
contract RepresentingConvexToken is ERC20Upgradeable, OwnableUpgradeable {
    function initialize(string memory _tokenName, string memory _tokenSymbol) public initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(_msgSender());
    }

    function mint(uint256 _amount) public onlyOwner {
        _mint(_msgSender(), _amount);
    }

    function burn(uint256 _amount) public onlyOwner {
        _burn(_msgSender(), _amount);
    }
}
