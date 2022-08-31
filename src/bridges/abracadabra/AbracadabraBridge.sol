// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Aztec Connect Bridge for deposit, mint/borrow and repay loan
 * @author Thomas
 * @notice You can use this contract to deposit tokens, borrow MIM and repay loan
 */
contract AbracadabraBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}

    mapping(address => address) public underlyingAToken;

    /**
     * @notice Add the underlying asset to the set of supported assets
     * @dev For the underlying to be accepted, the asset must be supported in Abracadabra
     * @param _underlyingAsset The address of the underlying asset
     * @param _aTokenAddress The address of the aToken
     */
    function setUnderlyingAToken(address _underlyingAsset, address _aTokenAddress)
        external
    {
        require(underlyingAToken[_underlyingAsset] == address(0), 'AToken already exists');
        require(_aTokenAddress != address(0), 'aToken address is invalid');
        require(_aTokenAddress != _underlyingAsset, 'aToken is invalid');
        
        IERC20Metadata aToken = IERC20Metadata(_aTokenAddress);

        string memory name = string(abi.encodePacked("A-", aToken.name()));
        string memory symbol = string(abi.encodePacked("A-", aToken.symbol()));

        address AToken = address(new AccountingToken(name, symbol, aToken.decimals()));

        underlyingAToken[_underlyingAsset] = AToken;

        performApprovals(_underlyingAsset);

        emit UnderlyingAssetListed(_underlyingAsset, AToken);
    }

    /**
     * @param _underlyingAsset The address of the underlying asset
     */
    function Approve(address _underlyingAsset) public {
        address AToken = underlyingAToken[_underlyingAsset];
        require(underlyingAToken[_underlyingAsset] != address(0), 'AToken does not exist');

        IERC20(AToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
        IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, 0);
        IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
    }

    /**
     * @param _inputAssetA The input asset, accepts Eth or ERC20 if supported underlying or AToken
     * @param _inputAssetB Unused input asset, reverts if different from NOT_USED
     * @param _outputAssetA The output asset, accepts Eth or ERC20 if supported underlying or AToken
     * @param _outputAssetB Unused output asset, reverts if different from NOT_USED
     * @param _totalInputValue The input amount of inputAssetA
     * @param _interactionNonce The interaction nonce of the call
     * @return outputValueA The output amount of outputAssetA
     * @return outputValueB The ouput amount of outputAssetB
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        address inputAsset = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : _inputAssetA.erc20Address;
        address outputAsset = _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : _outputAssetA.erc20Address;
        address underlying;
        address AToken;
        if (underlyingAToken[inputAsset] == address(0)) {
            underlying = outputAsset;
            AToken = underlyingAToken[underlying];
        } else {
            underlying = inputAsset;
            AToken = underlyingAToken[inputAsset];
        }

        if (inputAsset == underlying) {
            outputValueA = _enter(underlyingAddress, ATokenAddress, _totalInputValue);
        } else {
            outputValueA = _exit(underlyingAddress, ATokenAddress, _totalInputValue, _interactionNonce);
        }

        return (outputValueA, 0, false);
    }

    /**
     * @param _underlyingAsset The address of the underlying asset
     * @param _ATokenAddress The address of the representative AToken
     * @param _amount The amount of underlying asset to deposit
     * @return The amount of AToken that was minted by the deposit
     */
    function deposit(
        address _underlyingAsset,
        address _ATokenAddress,
        uint256 _amount
    ) internal returns (uint256) {
        ILendingPool pool = ILendingPool(0x5C084075c9A57f8F235c22AA44697F579d34B823);

        pool.deposit(_underlyingAsset, _amount, address(this), 0);

        IAccountingToken AToken = IAccountingToken(_ATokenAddress);
        AToken.mint(address(this), scaledAmount);

        return scaledAmount;
    }

    /**
     * @param _underlyingAsset The address of the underlying asset
     * @param _ATokenAddress The address of the representative AToken
     * @param _scaledAmount The amount of AToken to burn, used to derive underlying amount
     */
    function repay(
        address _underlyingAsset,
        address _ATokenAddress,
        uint256 _scaledAmount
    ) internal returns (uint256) {
        IAccountingToken(_ATokenAddress).burn(_scaledAmount);

        ILendingPool pool = ILendingPool(0x5C084075c9A57f8F235c22AA44697F579d34B823);
        uint256 outputValue = pool.withdraw(_underlyingAsset, _scaledAmount, address(this));

        return outputValue;
    }
}
