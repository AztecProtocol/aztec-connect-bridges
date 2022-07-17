// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IWrappedfCashFactory} from "./interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCash} from "./interfaces/notional/IWrappedfCash.sol";

contract NotionalBridgeContract is BridgeBase {
    IWrappedfCashFactory public fcashFactory;
    mapping(address => uint16) public currencyIds;
    constructor(address _rollupProcessor, address _fcashFactory) BridgeBase(_rollupProcessor) {
        fcashFactory = IWrappedfCashFactory(_fcashFactory);
    }

    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 auxData,
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
        if (currencyIds[_inputAssetA.address] != 0) {
            (,outputValueA) = _enter(_inputAssetA.address, _inputValue, uint40(maturity));
        } else{
            (,outputValueA) =  _exit(_inputAssetA.address, _inputValue);
        }
        if (_outputAssetA.assetType == AztecTypes.ERC20){
            IERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, outputValueA);
        } else if(_outputAssetA.assetType == AztecAssetType.ETH) {
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }
    }

    function _enter(
        address inputToken,
        uint256 amount,
        uint40 maturity
    ) internal returns (address, uint256) {
        uint16 currencyId = currencyIds[inputToken];
        IWrappedfCash fcash = fcashFactory.computeAddress(currencyId, maturity);
        IERC20(inputToken).approve(fcash, amount);
        if (inputToken == address(0)){
            fcash.mintViaUnderlying(amount, amount, address(this), 5e9){value: amount};
        } else {
            fcash.mintViaUnderlying(amount, amount, address(this), 5e9);
        }
        return (fcash, amount);
    }

    function _exit(address inputToken, uint256 amount) internal returns (address, uint256) {
        (IERC20 underlyingToken, ) = IWrappedfCash(inputToken).getUnderlyingToken();
        bool isETH = address(underlyingToken) == address(0);
        uint256 prevBalance =  isETH? address(this).balance : underlyingToken.balanceOf(address(this));
        IWrappedfCash(inputToken).redeemToUnderlying(amount, address(this), 0);
        uint256 currBalance = isETH? address(this).balance : underlyingToken.balanceOf(address(this));
        return (address(underlyingToken), currBalance - prevBalance);
    }
}
