// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";

import {ISetToken} from "./interfaces/ISetToken.sol";
import {IController} from "./interfaces/IController.sol";
import {IExchangeIssuance} from "./interfaces/IExchangeIssuance.sol";

import "../../test/console.sol";

contract IssuanceBridge is IDefiBridge {
    using SafeMath for uint256;

    address public immutable rollupProcessor;

    IExchangeIssuance exchangeIssuance;
    IController setController; // used to check if address is SetToken

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
     * @notice Function that allows to ISSUE or REDEEM SetToken in exchange for ETH or ERC20
     * @param inputAssetA    - If ISSUE SET: ETH or ERC20        | If REDEEM SET: SetToken
     * @param outputAssetA   - If ISSUE SET: setToken            | If REDEEM SET: ETH or ERC20
     * @param inputValue     - If ISSUE SET: ETH or ERC20 amount | If REDEEM SET: SetToken amount
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
        address rollupBeneficiary
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
        require(
            msg.sender == rollupProcessor,
            "IssuanceBridge: INVALID_CALLER"
        );
        require(inputValue > 0, "IssuanceBridge: INVALID_INPUT_VALUE");

        isAsync = false;

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
            console.log("BRIDGE: Redeem SET and receive ETH or ERC20");
            // Check that spending of the given SetToken is approved
            require(
                IERC20(inputAssetA.erc20Address).approve(
                    address(exchangeIssuance),
                    inputValue
                ),
                "IssuanceBridge: APPROVE_FAILED"
            );

            // user wants to receive ETH
            // TODO this does not work.
            // The transaction reverts in AaveTokenV2Mintalbe.sol with error:
            // "Address: unable to send value, recipient may have reverted"
            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                console.log("BRIDGE: Redeem SET and receive ETH ");
                outputValueA = exchangeIssuance.redeemExactSetForETH(
                    ISetToken(address(inputAssetA.erc20Address)),
                    inputValue, // _amountSetToken
                    0 // __minEthOut
                );
            }

            // user wants to receive ERC20
            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                console.log("BRIDGE: Redeem SET and receive ERC20 ");
                outputValueA = exchangeIssuance.redeemExactSetForToken(
                    ISetToken(address(inputAssetA.erc20Address)), // _setToken,
                    IERC20(address(outputAssetA.erc20Address)), // _outputToken,
                    inputValue, //  _amountSetToken,
                    0 //  _minOutputReceive
                );

                // approve the transfer of funds back to the rollup contract
                require(
                    IERC20(outputAssetA.erc20Address).approve(
                        rollupProcessor,
                        outputValueA
                    ),
                    "IssuanceBridge: APPROVE_FAILED"
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
            console.log("BRIDGE: Issue SET for ERC20");
            // Check that spending of the ERC20 is approved
            require(
                IERC20(inputAssetA.erc20Address).approve(
                    address(exchangeIssuance),
                    inputValue
                ),
                "IssuanceBridge: APPROVE_FAILED"
            );

            outputValueA = exchangeIssuance.issueSetForExactToken(
                ISetToken(address(outputAssetA.erc20Address)),
                IERC20(address(inputAssetA.erc20Address)),
                inputValue, //  _amountInput
                0 // _minSetReceive
            );

            // approve the transfer of funds back to the rollup contract
            require(
                IERC20(outputAssetA.erc20Address).approve(
                    rollupProcessor,
                    outputValueA
                ),
                "IssuanceBridge: APPROVE_FAILED"
            );
        }
        // ISSUE: User wants to issue SetToken for ETH
        // inputAssetA: ETH
        // outputAssetA: SetToken
        else if (
            inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            setController.isSet(address(outputAssetA.erc20Address))
        ) {
            console.log("BRIDGE: Issue SET for ETH");
            // issue SetTokens for a given amount of ETH (=inputValue)
            outputValueA = exchangeIssuance.issueSetForExactETH{
                value: inputValue
            }(
                ISetToken(address(outputAssetA.erc20Address)),
                0 // _minSetReceive
            );

            // approve the transfer of funds back to the rollup contract
            require(
                IERC20(outputAssetA.erc20Address).approve(
                    rollupProcessor,
                    outputValueA
                ),
                "IssuanceBridge: APPROVE_FAILED"
            );
        } else {
            console.log(
                "INCOMPATIBLE_ASSET_PAIR - transaction will be reverted"
            );
            revert("IssuanceBridge: INCOMPATIBLE_ASSET_PAIR");
        }
    }
    
    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    ) external payable override returns (uint256, uint256, bool) {
        require(false, "IssuanceBridge: ASYNC_MODE_DISABLED");
    }
}
