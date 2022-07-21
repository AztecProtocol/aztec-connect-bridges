// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
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
 * @title Aztec Connect Bridge for depositing on Yearn
 * @author Majorfi
 * @notice You can use this contract to deposit tokens on compatible Yearn Vaults
 */
contract YearnBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IYearnRegistry public constant YEARN_REGISTRY = IYearnRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    error InvalidOutputANotLatest();
    error InvalidWETHAmount();
    error InvalidOutputVault();

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
            _preApprove(vault, token);

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
        address token = IYearnVault(_vault).token();
        _preApprove(_vault, token);
    }

    /**
     * @notice A function which will allow the user to deposit/withdraw a given amount of a given token to a given vault.
     * @param _inputAssetA - Arbitrary ERC20 token
     * @param _outputAssetA - Equal to _inputAssetA
     * @param _inputValue - Amount to deposit or withdraw
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @param _auxData - Special value to indicate a deposit (0) or a withdraw (1)
     * @return outputValueA - the amount of output asset to return
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
        if (_inputValue == 0) {
            revert ErrorLib.InvalidInputAmount();
        }
        if (_auxData == 0) {
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) {
                revert ErrorLib.InvalidOutputA();
            }

            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                outputValueA = _zapETH(msg.value, _outputAssetA);
            } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                outputValueA = IYearnVault(_outputAssetA.erc20Address).deposit(_inputValue);
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else if (_auxData == 1) {
            if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) {
                revert ErrorLib.InvalidInputA();
            }

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                outputValueA = _unzapETH(_inputValue, _interactionNonce, _inputAssetA);
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                outputValueA = IYearnVault(_inputAssetA.erc20Address).withdraw(_inputValue);
            } else {
                revert ErrorLib.InvalidOutputA();
            }
        } else {
            revert ErrorLib.InvalidAuxData();
        }
        return (outputValueA, 0, false);
    }

    /**
     * @notice Wrap _inputValue ETH to wETH and deposit theses wETH to the provided yvETH vault.
     * @param _inputValue - Amount of shares to deposit
     * @param _outputAssetA - Vault we want to deposit to
     * @return outputValue - Amount of shares received after deposit
     */
    function _zapETH(uint256 _inputValue, AztecTypes.AztecAsset memory _outputAssetA)
        private
        returns (uint256 outputValue)
    {
        IYearnVault yVault = IYearnVault(_outputAssetA.erc20Address);
        address underlyingToken = yVault.token();
        if (underlyingToken != WETH) {
            revert ErrorLib.InvalidOutputA();
        }

        IWETH(WETH).deposit{value: _inputValue}();
        IERC20(WETH).balanceOf(address(this));

        outputValue = yVault.deposit(_inputValue);
    }

    /**
     * @notice Withdraw _inputValue from a yvETH vault, unwrap the wETH received to ETH and reclaim them.
     * @dev we can withdraw from any yvETH vault, not only the latest one.
     * @param _inputValue - Amount of shares to withdraw
     * @param _interactionNonce - Aztec nonce of the interaction
     */
    function _unzapETH(
        uint256 _inputValue,
        uint256 _interactionNonce,
        AztecTypes.AztecAsset memory _inputAssetA
    ) private returns (uint256 outputValue) {
        IYearnVault yVault = IYearnVault(_inputAssetA.erc20Address);
        if (yVault.token() != WETH) {
            revert ErrorLib.InvalidInputA();
        }

        uint256 wethAmount = yVault.withdraw(_inputValue);
        if (wethAmount == 0) {
            revert InvalidWETHAmount();
        }

        IWETH(WETH).withdraw(wethAmount);
        outputValue = address(this).balance;
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }

    /**
     * @notice Perform all the necessary approvals for a given vault and its underlying.
     * @param _vault - vault we are working with
     * @param _token - address of the token to approve
     */
    function _preApprove(address _vault, address _token) private {
        // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
        uint256 allowance = IERC20(_token).allowance(address(this), _vault);
        if (allowance != type(uint256).max) {
            // Resetting allowance to 0 in order to avoid issues with USDT
            IERC20(_token).safeApprove(_vault, 0);
            IERC20(_token).safeApprove(_vault, type(uint256).max);
        }

        allowance = IERC20(_token).allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            // Resetting allowance to 0 in order to avoid issues with USDT
            IERC20(_token).safeApprove(ROLLUP_PROCESSOR, 0);
            IERC20(_token).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }

        IERC20(_vault).approve(ROLLUP_PROCESSOR, type(uint256).max);
    }
}
