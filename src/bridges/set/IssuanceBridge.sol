// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {AztecTypes} from '../../aztec/AztecTypes.sol';

import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';
import {ISetToken} from './interfaces/ISetToken.sol';
import {IController} from './interfaces/IController.sol';
import {IExchangeIssuance} from './interfaces/IExchangeIssuance.sol';
import {IRollupProcessor} from '../../interfaces/IRollupProcessor.sol';

contract IssuanceBridge is IDefiBridge {
    using SafeERC20 for IERC20;

    IExchangeIssuance public constant EXCHANGE_ISSUANCE = IExchangeIssuance(0xc8C85A3b4d03FB3451e7248Ff94F780c92F884fD);
    IController public constant SET_CONTROLLER = IController(0xa4c8d221d8BB851f83aadd0223a8900A6921A349);

    address public immutable rollupProcessor;

    error ApproveFailed(address token);
    error InvalidCaller();
    error ZeroInputValue();
    error IncorrectInput();
    error AsyncModeDisabled();

    /**
     * @notice Sets the addresses of RollupProcessor
     * @param _rollupProcessor Address of the RollupProcessor.sol
     */
    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
    }

    // Empty receive function for the contract to be able to receive ETH
    receive() external payable {}

    /**
     * @notice Sets all the important approvals.
     * @dev This bridge never holds any ERC20s after or before an invocation of any of its functions.
     * For this reason the following is not a security risk and makes the convert() function more gas efficient.
     */
    function approveTokens(address[] calldata tokens) external {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength; ) {
            IERC20(tokens[i]).safeIncreaseAllowance(rollupProcessor, type(uint256).max);
            IERC20(tokens[i]).safeIncreaseAllowance(address(EXCHANGE_ISSUANCE), type(uint256).max);
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
     * @param auxData        - minimum token amount received during redemption or minting
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
            bool
        )
    {
        if (msg.sender != rollupProcessor) revert InvalidCaller();
        if (inputValue == 0) revert ZeroInputValue();

        if (SET_CONTROLLER.isSet(address(inputAssetA.erc20Address))) {
            // User wants to redeem the underlying asset
            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // redeem in exchange for ETH
                outputValueA = EXCHANGE_ISSUANCE.redeemExactSetForETH(
                    ISetToken(address(inputAssetA.erc20Address)),
                    inputValue, // _amountSetToken
                    auxData // __minEthOut
                );
                IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
            } else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                // redeem in exchange for ERC20
                outputValueA = EXCHANGE_ISSUANCE.redeemExactSetForToken(
                    ISetToken(address(inputAssetA.erc20Address)), // _setToken,
                    IERC20(address(outputAssetA.erc20Address)), // _outputToken,
                    inputValue, //  _amountSetToken,
                    auxData //  _minOutputReceive
                );
            } else {
                revert IncorrectInput();
            }
        } else if (SET_CONTROLLER.isSet(address(outputAssetA.erc20Address))) {
            // User wants to issue SetToken
            if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // User supplies ETH
                outputValueA = EXCHANGE_ISSUANCE.issueSetForExactETH{value: inputValue}(
                    ISetToken(address(outputAssetA.erc20Address)),
                    auxData // _minSetReceive
                );
            } else if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                // User supplies ERC20
                outputValueA = EXCHANGE_ISSUANCE.issueSetForExactToken(
                    ISetToken(address(outputAssetA.erc20Address)),
                    IERC20(address(inputAssetA.erc20Address)),
                    inputValue, // _amountInput
                    auxData // _minSetReceive
                );
            } else {
                revert IncorrectInput();
            }
        } else {
            revert IncorrectInput();
        }
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
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
        revert AsyncModeDisabled();
    }
}
