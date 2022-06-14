// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../aztec/AztecTypes.sol";

import {ICoinJoin} from "./interfaces/ICoinJoin.sol";
import {IEthJoin} from "./interfaces/IEthJoin.sol";
import {ISafeEngine} from "./interfaces/ISafeEngine.sol";
import {ISafeManager} from "./interfaces/ISafeManager.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

// NOTE:
// 1. Theres a minimum amount of RAI to be borrowed in the first call, which is currently 1469 RAI
// 2. You can find the readme for the contract here: https://gist.github.com/realdiganta/2c73f86820bf7310bd934184fa960e3d

contract RaiBridge is ERC20, BridgeBase {
    using SafeMath for uint256;

    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x4ad7B025127e89263242aB68F0f9c4E5C033B489);
    address public constant SAFE_ENGINE = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
    address public constant SAFE_MANAGER = 0xEfe0B4cA532769a3AE758fD82E1426a03A94F185;
    address public constant COIN_JOIN = 0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45;
    address public constant ETH_JOIN = 0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant RAI = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;

    address public immutable SAFE_HANDLER;
    uint256 public immutable safeId;
    bool private isInitialized;

    constructor(
        address _rollupProcessor,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) BridgeBase(_rollupProcessor) {
        // OPEN THE SAFE
        safeId = ISafeManager(SAFE_MANAGER).openSAFE(
            0x4554482d41000000000000000000000000000000000000000000000000000000,
            address(this)
        );

        SAFE_HANDLER = ISafeManager(SAFE_MANAGER).safes(safeId);

        // do all one off approvals
        require(IWETH(WETH).approve(ETH_JOIN, type(uint256).max), "Weth approve failed");
        require(IWETH(WETH).approve(ROLLUP_PROCESSOR, type(uint256).max), "Weth approve failed");
        require(IERC20(RAI).approve(COIN_JOIN, type(uint256).max), "Rai approve failed");
        require(IERC20(RAI).approve(ROLLUP_PROCESSOR, type(uint256).max), "Rai approve failed");
        ISafeEngine(SAFE_ENGINE).approveSAFEModification(COIN_JOIN);
    }

    /// @return collateralRatio = Ongoing collateral ratio of the current safe in BPS
    /// @return raiToEth = Ratio of rai to ETH
    /// @return safe = totalCollateral & totalDebt of this safe
    function getSafeData()
        public
        view
        returns (
            uint256 collateralRatio,
            uint256 raiToEth,
            ISafeEngine.SAFE memory safe
        )
    {
        safe = ISafeEngine(SAFE_ENGINE).safes(
            0x4554482d41000000000000000000000000000000000000000000000000000000,
            SAFE_HANDLER
        );
        // rai to Eth Ratio
        (, int256 x, , , ) = priceFeed.latestRoundData();
        raiToEth = uint256(x);
        if (safe.lockedCollateral != 0 || safe.generatedDebt != 0) {
            collateralRatio = safe.lockedCollateral.mul(1e22).div(raiToEth).div(safe.generatedDebt);
        } else {
            collateralRatio = 0;
        }
    }

    function convert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
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
        if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            // transfer to weth
            IWETH(WETH).deposit{value: msg.value}();
        }

        if (isInitialized) {
            (uint256 collateralRatio, uint256 raiToEth, ISafeEngine.SAFE memory safe) = getSafeData();
            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && outputAssetA.erc20Address == RAI) {
                require(
                    outputAssetB.assetType == AztecTypes.AztecAssetType.ERC20 &&
                        outputAssetB.erc20Address == address(this)
                );
                // deposit weth output RAI
                outputValueA = _addCollateral(totalInputValue, collateralRatio, raiToEth);
                outputValueB = outputValueA;
                _mint(address(this), outputValueB);
            } else if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && inputAssetA.erc20Address == RAI) {
                _burn(address(this), totalInputValue);
                // deposit RAI output weth
                outputValueA = _removeCollateral(totalInputValue, safe);
                if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                    // change weth to eth
                    IWETH(WETH).withdraw(outputValueA);
                    IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(interactionNonce);
                }
            }
        } else {
            // CONTRACT INITIALIZATION
            require(auxData > 0, "no collateral ratio provided");
            require(
                outputAssetB.assetType == AztecTypes.AztecAssetType.ERC20 && outputAssetB.erc20Address == address(this)
            );
            isInitialized = true;

            require(IERC20(address(this)).approve(ROLLUP_PROCESSOR, type(uint256).max), "BridgeTokens approve failed");

            (, int256 raiToEth, , , ) = priceFeed.latestRoundData();

            // minimum amount of RAI to be borrowed at initialization is 1469 RAI
            // please provide enough ETH/WETH for that or this method will revert
            outputValueA = _addCollateral(totalInputValue, auxData, uint256(raiToEth));
            outputValueB = outputValueA;
            _mint(address(this), outputValueB);
        }
    }

    // ------------------------------- INTERNAL FUNCTIONS -------------------------------------------------

    function _addCollateral(
        uint256 _wethAmount,
        uint256 _collateralRatio,
        uint256 _raiToEth
    ) internal returns (uint256 outputRai) {
        IEthJoin(ETH_JOIN).join(SAFE_HANDLER, _wethAmount);

        // expected RAI amount = eth_amount * (1e18/raiToEthPrice) * (1/collateralRatio)
        outputRai = _wethAmount.mul(1e22).div(_raiToEth).div(_collateralRatio);

        ISafeManager(SAFE_MANAGER).modifySAFECollateralization(safeId, int256(_wethAmount), int256(outputRai));

        ISafeManager(SAFE_MANAGER).transferInternalCoins(safeId, address(this), outputRai * 10**27);

        ICoinJoin(COIN_JOIN).exit(address(this), outputRai);
    }

    function _removeCollateral(uint256 _raiAmount, ISafeEngine.SAFE memory safe) internal returns (uint256 outputWeth) {
        ICoinJoin(COIN_JOIN).join(SAFE_HANDLER, _raiAmount);

        outputWeth = safe.lockedCollateral.mul(_raiAmount).div(safe.generatedDebt);

        ISafeManager(SAFE_MANAGER).modifySAFECollateralization(safeId, -int256(outputWeth), -int256(_raiAmount));
        ISafeManager(SAFE_MANAGER).transferCollateral(safeId, address(this), outputWeth);
        IEthJoin(ETH_JOIN).exit(address(this), outputWeth);
    }

    fallback() external payable {}

    receive() external payable {}
}
