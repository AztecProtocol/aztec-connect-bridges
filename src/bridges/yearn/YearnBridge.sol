// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IYearnRegistry} from "../../interfaces/yearn/IYearnRegistry.sol";
import {IYearnVault} from "../../interfaces/yearn/IYearnVault.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Aztec Connect Bridge for depositing on Uniswap v3
 * @author Majorfi
 * @notice You can use this contract to deposit tokens on compatible Yearn Vaults
 * @dev This bridge demonstrates the flow of assets in the convert function. This bridge simply returns what has been
 *      sent to it.
 */
contract YearnBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IYearnRegistry public constant YEARN_REGISTRY = IYearnRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    error InvalidOutputANotLatest();


    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}


    /**
     * @notice Set all the necessary approvals for all the latests vaults for the tokens supported by Yearn
     */
    function preApproveAll() external {
        uint256 numTokens = YEARN_REGISTRY.numTokens();
        for (uint256 i; i < numTokens; ) {
            address token = YEARN_REGISTRY.tokens(i);
            address vault = YEARN_REGISTRY.latestVault(token);
            _preApprove(vault);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set all the necessary approvals for a given vault and its underlying.
     * @param _vault - vault address
     */
    function preApprove(address _vault) external {
       _preApprove(_vault);
    }

    /**
     * @notice A function which returns an _inputValue amount of _inputAssetA
     * @param _inputAssetA - Arbitrary ERC20 token
     * @param _outputAssetA - Equal to _inputAssetA
     * @return outputValueA - the amount of output asset to return
     * @dev In this case _outputAssetA equals _inputAssetA
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_auxData == 0) {
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                outputValueA = _zapETH(msg.value, _outputAssetA);
            } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                outputValueA = _depositERC20(_inputValue, _inputAssetA, _outputAssetA);
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else if (_auxData == 1) {
            if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                outputValueA = _unzapETH(_inputValue, _interactionNonce, _inputAssetA);
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                outputValueA = _withdrawERC20(_inputValue, _inputAssetA, _outputAssetA);
            } else {
                revert ErrorLib.InvalidOutputA();
            }
        } else {
            revert ErrorLib.InvalidAuxData();
        }
        return (outputValueA, 0, false);
    }

    /**
     * @notice Wrap _inputValue ETH to wETH and deposit theses wETH to the latests yvETH vault.
     * @dev we can deposit only to the latest yvETH vault.
     * @param _inputValue - Amount of shares to withdraw
     * @param _outputAssetA - Vault we want to deposit to
     */
    function _zapETH(
        uint256 _inputValue,
        AztecTypes.AztecAsset memory _outputAssetA
    ) private returns (uint256 outputValue) {
        IYearnVault vault = IYearnVault(_outputAssetA.erc20Address);
        address underlyingToken = vault.token();
        if (underlyingToken != WETH) {
            //Error: not a yvETH vault
            revert ErrorLib.InvalidOutputA();
        }

        if (_outputAssetA.erc20Address != YEARN_REGISTRY.latestVault(underlyingToken)) {
            //Error: not the latest vault for ETH
            revert InvalidOutputANotLatest();
        }

        IWETH(WETH).deposit{value: _inputValue}();
        uint256 _amount = IERC20(WETH).balanceOf(address(this));
        vault.deposit(_amount);
        outputValue = IERC20(address(vault)).balanceOf(address(this));
    }

    /**
     * @notice Withdraw _inputValue from a yvETH vault, unwrap the wETH received to ETH and reclaim them.
     * @dev we can withdraw from any yvETH vault, not only the latest one.
     * @param _inputValue - Amount of shares to withdraw
     * @param _interactionNonce - Azteck nonce of the interaction
     */
    function _unzapETH(
        uint256 _inputValue,
        uint256 _interactionNonce,
        AztecTypes.AztecAsset memory _inputAssetA
    ) private returns (uint256 outputValue) {
        IYearnVault vault = IYearnVault(_inputAssetA.erc20Address);
        if (vault.token() != WETH) {
            revert ErrorLib.InvalidInputA();
        }
        uint256 wethAmount = vault.withdraw(_inputValue);
        if (wethAmount == 0) {
            revert ErrorLib.InvalidInputA();
        }
        IWETH(WETH).withdraw(wethAmount);
        outputValue = address(this).balance;
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }

    /**
     * @notice Deposit an ERC20 token to the latest compatible vault.
     * @dev You can only deposit to the latest version of the vault
     * @param _inputValue - amount to deposit
     * @param _inputAssetA - Data about the token to deposit
     * @param _inputAssetA - Data about the token to receive
     */
    function _depositERC20(
        uint256 _inputValue,
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA
    ) private returns (uint256 outputValue) {
        IYearnVault yVault = IYearnVault(YEARN_REGISTRY.latestVault(_inputAssetA.erc20Address));
        if (address(yVault) != _outputAssetA.erc20Address) revert ErrorLib.InvalidOutputA();
        outputValue = yVault.deposit(_inputValue);
    }

    /**
     * @notice Withdraw a specified amount of shares from the specified vault.
     * @param _inputValue - amount to deposit
     * @param _inputAssetA - Data about the token to deposit
     * @param _inputAssetA - Data about the token to receive
     */
    function _withdrawERC20(
        uint256 _inputValue,
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA
    ) private returns (uint256 outputValue) {
        IYearnVault yVault = IYearnVault(_inputAssetA.erc20Address);
        if (yVault.token() != _outputAssetA.erc20Address) revert ErrorLib.InvalidOutputA();
        outputValue = yVault.withdraw(_inputValue);
    }

    /**
     * @notice Perform all the necessary approvals for a given vault and its underlying.
     * @param _vault - address of the vault to work with
     */
    function _preApprove(address _vault) private {
        IYearnVault yVault = IYearnVault(_vault);
        IERC20 underlying = IERC20(yVault.token());

        uint256 allowance = yVault.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance < type(uint256).max) {
            yVault.approve(ROLLUP_PROCESSOR, type(uint256).max - allowance);
        }

        // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
        allowance = underlying.allowance(address(this), address(yVault));
        if (allowance != type(uint256).max) {
            // Resetting allowance to 0 in order to avoid issues with USDT
            underlying.safeApprove(address(yVault), 0);
            underlying.safeApprove(address(yVault), type(uint256).max);
        }
        allowance = underlying.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            // Resetting allowance to 0 in order to avoid issues with USDT
            underlying.safeApprove(ROLLUP_PROCESSOR, 0);
            underlying.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }
    }
}
