// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AztecTypes } from "../../aztec/AztecTypes.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { ISetToken } from "./interfaces/ISetToken.sol";
import { IController } from "./interfaces/IController.sol";
import { IExchangeIssuance } from "./interfaces/IExchangeIssuance.sol";
import { IRollupProcessor } from "../../interfaces/IRollupProcessor.sol";

contract IssuanceBridge is IDefiBridge {
    address public immutable rollupProcessor;

    IExchangeIssuance exchangeIssuance;
    IController setController; // used to check if address is SetToken

    error ApproveFailed(address token);
    error InvalidCaller();
    error ZeroInputValue();
    error IncompatibleAssetPair();
    error AsyncModeDisabled();

    constructor(
        address _rollupProcessor,
        address _exchangeIssuance,
        address _setController
    ) public {
        rollupProcessor = _rollupProcessor;
        exchangeIssuance = IExchangeIssuance(_exchangeIssuance);
        setController = IController(_setController);
    }

    /**
     * @notice Sets all the important approvals.
     * @dev This bridge never holds any ERC20s after or before an invocation of any of its functions.
     * For this reason the following is not a security risk and makes the convert() function more gas efficient.
     */
    function approveTokens(address[] calldata tokens) external {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength; ) {
            if (!IERC20(tokens[i]).approve(rollupProcessor, type(uint256).max)) revert ApproveFailed(tokens[i]);
            if (!IERC20(tokens[i]).approve(address(exchangeIssuance), type(uint256).max)) revert ApproveFailed(tokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Function that allows to ISSUE or REDEEM SetToken in exchange for ETH or ERC20
     * @param inputAssetA    - If ISSUE SET: ETH or ERC20        | If REDEEM SET: SetToken
     * @param outputAssetA   - If ISSUE SET: setToken            | If REDEEM SET: ETH or ERC20
     * @param inputValue     - If ISSUE SET: ETH or ERC20 amount | If REDEEM SET: SetToken amount
     * @param auxData -
     * @return outputValueA  - If ISSUE SET: SetToken amount     | If REDEEM SET: ETH or ERC20 amount
     * @return isAsync a flag to toggle if this bridge interaction will return assets at a later
            date after some third party contract has interacted with it via finalise()
     */

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address 
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        // Only Rollup Processor can call this function
        if (msg.sender != rollupProcessor) revert InvalidCaller();
        if (inputValue == 0) revert ZeroInputValue();

        // -----------------------------------------------------------------------------------------
        // Check if the user wants to ISSUE or REDEEM SetToken based on the input/output asset types
        // -----------------------------------------------------------------------------------------

        // REDEEM SET: User wants to redeem SetToken and receive ETH or ERC20
        // inputAssetA: SetToken
        // outputAssetA ERC20 or ETH
        if (
            setController.isSet(address(inputAssetA.erc20Address)) &&
            (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH ||
                outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20)
        ) {
            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // user wants to receive ETH
                outputValueA = exchangeIssuance.redeemExactSetForETH(
                    ISetToken(address(inputAssetA.erc20Address)),
                    inputValue, // _amountSetToken
                    auxData // __minEthOut
                );
                // Send ETH to rollup processor
                IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
            } else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                // user wants to receive ERC20
                outputValueA = exchangeIssuance.redeemExactSetForToken(
                    ISetToken(address(inputAssetA.erc20Address)), // _setToken,
                    IERC20(address(outputAssetA.erc20Address)), // _outputToken,
                    inputValue, //  _amountSetToken,
                    auxData //  _minOutputReceive
                );
            }
        }
        // ISSUE SET: User wants to issue SetToken in for ERC20
        // inputAssetA: ERC20 (but not SetToken)
        // outputAssetA: SetToken
        else if (
            inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            !setController.isSet(address(inputAssetA.erc20Address)) &&
            setController.isSet(address(outputAssetA.erc20Address))
        ) {
            outputValueA = exchangeIssuance.issueSetForExactToken(
                ISetToken(address(outputAssetA.erc20Address)),
                IERC20(address(inputAssetA.erc20Address)),
                inputValue, //  _amountInput
                auxData // _minSetReceive
            );
        }
        // ISSUE: User wants to issue SetToken for ETH
        // inputAssetA: ETH
        // outputAssetA: SetToken
        else if (
            inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            setController.isSet(address(outputAssetA.erc20Address))
        ) {
            // issue SetTokens for a given amount of ETH (=inputValue)
            outputValueA = exchangeIssuance.issueSetForExactETH{
                value: inputValue
            }(
                ISetToken(address(outputAssetA.erc20Address)),
                auxData // _minSetReceive
            );
        } else {
            revert IncompatibleAssetPair();
        }
    }

    // Empty fallback function in order to receive ETH 
    receive() external payable {}
    
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    ) external payable override returns (uint256, uint256, bool) {
        revert AsyncModeDisabled();
    }
}
