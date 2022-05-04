// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';

import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import {AztecTypes} from '../../aztec/AztecTypes.sol';
import './Interfaces/IBeefyVault.sol';

contract BeefyBridge is IDefiBridge, Ownable {
    using SafeMath for uint256;

    address public immutable rollupProcessor;
  \

    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
    }

    /**     function registerVaultTokenPair(address v, address t) public onlyOwner {
        require(address(IBeefyVault(v).want()) == t, 'invalid vault token pair');
        tokenToVault[t] = v;
        vaultToToken[v] = t;
    }
    **/
    function convert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address rollupBeneficiary
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        // // ### INITIALIZATION AND SANITY CHECKS
        require(msg.sender == rollupProcessor, 'ExampleBridge: INVALID_CALLER');

        // case 1 output is beefy vault share token (ENTER)
        bool validVaultOutputPair = (address(IBeefyVault(outputAssetA.erc20Address).want()) ==
            inputAssetA.erc20Address);
        // case 2 input a vault share token receive underlying asser (EXIT)
        bool validVaultInputPair = (address(IBeefyVault(inputAssetA.erc20Address).want()) == outputAssetA.erc20Address);

        if (validVaultOutputPair) {
            outputValueA = enter(outputAssetA.erc20Address, inputAssetA.erc20Address, totalInputValue);
        } else if (validVaultInputPair) {
            outputValueA = exit(inputAssetA.erc20Address, outputAssetA.erc20Address, totalInputValue);
        } else {
            revert('invalid vault token pair address');
        }
    }

    function enter(
        address vault,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        IERC20 depositToken = IERC20(token);
        depositToken.approve(vault, amount);
        uint256 prev = IBeefyVault(vault).balanceOf(address(this));
        IBeefyVault(vault).deposit(amount);
        uint256 _after = IBeefyVault(vault).balanceOf(address(this));
        IBeefyVault(vault).approve(rollupProcessor, _after.sub(prev));
        return _after.sub(prev);
    }

    function exit(
        address vault,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        IERC20 withdrawToken = IERC20(token);
        uint256 prev = withdrawToken.balanceOf(address(this));
        IBeefyVault(vault).withdraw(amount);
        uint256 _after = withdrawToken.balanceOf(address(this));
        withdrawToken.approve(rollupProcessor, _after.sub(prev));
        return _after.sub(prev);
    }

    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false);
    }
}
