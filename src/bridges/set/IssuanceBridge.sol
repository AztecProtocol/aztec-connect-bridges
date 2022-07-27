// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {ISetToken} from "../../interfaces/set/ISetToken.sol";
import {IController} from "../../interfaces/set/IController.sol";
import {IExchangeIssuance} from "../../interfaces/set/IExchangeIssuance.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";

contract IssuanceBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IExchangeIssuance public constant EXCHANGE_ISSUANCE = IExchangeIssuance(0xc8C85A3b4d03FB3451e7248Ff94F780c92F884fD);
    IController public constant SET_CONTROLLER = IController(0xa4c8d221d8BB851f83aadd0223a8900A6921A349);

    /**
     * @notice Sets the addresses of RollupProcessor
     * @param _rollupProcessor Address of the RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    // Empty receive function for the contract to be able to receive ETH
    receive() external payable {}

    /**
     * @notice Sets all the important approvals.
     * @param _tokens An array of token addresses to set approvals for.
     * @dev This bridge never holds any ERC20s before or after an invocation of any of its functions.
     * For this reason the following is not a security risk and makes the convert() function more gas efficient.
     */
    function approveTokens(address[] calldata _tokens) external {
        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength; ) {
            IERC20(_tokens[i]).safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
            IERC20(_tokens[i]).safeIncreaseAllowance(address(EXCHANGE_ISSUANCE), type(uint256).max);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Function that allows to ISSUE or REDEEM SetToken in exchange for ETH or ERC20
     * @param _inputAssetA    - If ISSUE SET: ETH or ERC20        | If REDEEM SET: SetToken
     * @param _outputAssetA   - If ISSUE SET: setToken            | If REDEEM SET: ETH or ERC20
     * @param _inputValue     - If ISSUE SET: ETH or ERC20 amount | If REDEEM SET: SetToken amount
     * @param _auxData        - minimum token amount received during redemption or minting
     * @return outputValueA  - If ISSUE SET: SetToken amount     | If REDEEM SET: ETH or ERC20 amount
     * @return isAsync a flag to toggle if this bridge interaction will return assets at a later
            date after some third party contract has interacted with it via finalise()
     */

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
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
        if (_inputValue == 0) revert ErrorLib.InvalidInput();

        if (SET_CONTROLLER.isSet(address(_inputAssetA.erc20Address))) {
            // User wants to redeem the underlying asset
            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // redeem in exchange for ETH
                outputValueA = EXCHANGE_ISSUANCE.redeemExactSetForETH(
                    ISetToken(address(_inputAssetA.erc20Address)),
                    _inputValue, // _amountSetToken
                    _auxData // __minEthOut
                );
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                // redeem in exchange for ERC20
                outputValueA = EXCHANGE_ISSUANCE.redeemExactSetForToken(
                    ISetToken(address(_inputAssetA.erc20Address)), // _setToken,
                    IERC20(address(_outputAssetA.erc20Address)), // _outputToken,
                    _inputValue, //  _amountSetToken,
                    _auxData //  _minOutputReceive
                );
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else if (SET_CONTROLLER.isSet(address(_outputAssetA.erc20Address))) {
            // User wants to issue SetToken
            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // User supplies ETH
                outputValueA = EXCHANGE_ISSUANCE.issueSetForExactETH{value: _inputValue}(
                    ISetToken(address(_outputAssetA.erc20Address)),
                    _auxData // _minSetReceive
                );
            } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                // User supplies ERC20
                outputValueA = EXCHANGE_ISSUANCE.issueSetForExactToken(
                    ISetToken(address(_outputAssetA.erc20Address)),
                    IERC20(address(_inputAssetA.erc20Address)),
                    _inputValue, // _amountInput
                    _auxData // _minSetReceive
                );
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else {
            revert ErrorLib.InvalidInputA();
        }
    }
}
