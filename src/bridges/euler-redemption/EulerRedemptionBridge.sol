// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";
import {IVault, IAsset, PoolSpecialization} from "../../interfaces/element/IVault.sol";

interface IMigrator {
    function migrate(uint256 _amount, bytes32 _acceptanceToken) external returns (uint256, uint256, uint256);

    function ERC4626Token() external view returns (address);
}

contract EulerRedemptionBridge is BridgeBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;

    error SlippageExceeded();

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IERC4626 public constant WEWETH = IERC4626(0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0);
    IERC4626 public constant WEDAI = IERC4626(0x4169Df1B7820702f566cc10938DA51F6F597d264);
    IERC4626 public constant WEWSTETH = IERC4626(0x60897720AA966452e8706e74296B018990aEc527);

    bytes32 public constant TERMS_AND_CONDITIONS_HASH =
        0x427a506ff6e15bd1b7e4e93da52c8ec95f6af1279618a2f076946e83d8294996;

    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IVault public constant BALANCER = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 public constant BALANCER_WSTETH_POOLID = 0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;

    IMigrator public immutable WETH_MIGRATOR;
    IMigrator public immutable DAI_MIGRATOR;
    IMigrator public immutable WSTETH_MIGRATOR;

    constructor(address _rollupProcessor, address _wethMigrator, address _daiMigrator, address _wstethMigrator)
        BridgeBase(_rollupProcessor)
    {
        WETH_MIGRATOR = IMigrator(_wethMigrator);
        DAI_MIGRATOR = IMigrator(_daiMigrator);
        WSTETH_MIGRATOR = IMigrator(_wstethMigrator);

        IERC20(WETH_MIGRATOR.ERC4626Token()).approve(address(WETH_MIGRATOR), type(uint256).max);
        IERC20(DAI_MIGRATOR.ERC4626Token()).approve(address(DAI_MIGRATOR), type(uint256).max);
        IERC20(WSTETH_MIGRATOR.ERC4626Token()).approve(address(WSTETH_MIGRATOR), type(uint256).max);

        WETH.approve(address(BALANCER), type(uint256).max);

        WETH.approve(address(ROUTER), type(uint256).max);
        DAI.approve(address(ROUTER), type(uint256).max);
        USDC.approve(address(ROUTER), type(uint256).max);

        DAI.approve(address(ROLLUP_PROCESSOR), type(uint256).max);
        WSTETH.approve(address(ROLLUP_PROCESSOR), type(uint256).max);
    }

    receive() external payable {}

    /**
     * @notice Redeems shares of Euler ERC4626 vaults for underlying assets
     * following the redemption scheme. Will take the assets received and swap it into
     * the expected underlying.
     * @param _inputAssetA - The input asset to redeem
     * @param _outputAssetA - The output asset to receive
     * @param _totalInputValue - The total amount of input asset to redeem
     * @param _interactionNonce - The nonce of the interaction
     * @param _auxData - The aux data of the interaction (minAmountPerFullShare)
     * @return outputValueA - The amount of output asset received
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    ) external payable override(BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
        if (_inputAssetA.erc20Address == address(WEWETH)) {
            return _exitWeweth(_totalInputValue, _outputAssetA.erc20Address, _interactionNonce, _auxData);
        } else if (_inputAssetA.erc20Address == address(WEDAI)) {
            return _exitDai(_totalInputValue, _outputAssetA.erc20Address, _auxData);
        } else if (_inputAssetA.erc20Address == address(WEWSTETH)) {
            return _exitWsteth(_totalInputValue, _outputAssetA.erc20Address, _auxData);
        } else {
            revert ErrorLib.InvalidInputA();
        }
    }

    /**
     * @notice Redeems shares of WEWETH vault for weth, dai, usdc
     * swaps assets to Eth
     * @param _totalInputValue - The total amount of input asset to redeem
     * @param _outputAssetA - The output asset to receive
     * @param _interactionNonce - The nonce of the interaction
     * @param _auxData - The aux data of the interaction (minAmountPerFullShare)
     * @return outputValueA - The amount of output asset received
     */
    function _exitWeweth(uint256 _totalInputValue, address _outputAssetA, uint256 _interactionNonce, uint64 _auxData)
        internal
        returns (uint256 outputValueA, uint256, bool)
    {
        if (_outputAssetA != address(0)) {
            revert ErrorLib.InvalidOutputA();
        }

        // Migrate the asset.
        (uint256 wethAmount, uint256 daiAmount, uint256 usdcAmount) =
            WETH_MIGRATOR.migrate(_totalInputValue, _acceptanceToken());

        // Swap dai for usdc on uniswap
        {
            if (daiAmount > 0) {
                bytes memory path = abi.encodePacked(address(DAI), uint24(100), address(USDC));
                usdcAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: daiAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // Swap usdc to weth
        {
            if (usdcAmount > 0) {
                bytes memory path = abi.encodePacked(address(USDC), uint24(500), address(WETH));
                wethAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: usdcAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // @todo slippage aux could be 1e16 precision if there are very high interest amounts.
        uint256 minExpected = _totalInputValue * _auxData / 1e18;
        if (wethAmount < minExpected) {
            revert SlippageExceeded();
        }

        IWETH(WETH).withdraw(wethAmount);
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: wethAmount}(_interactionNonce);
        return (wethAmount, 0, false);
    }

    /**
     * @notice Redeems shares of WEDAI vault for weth, dai, usdc
     * swaps assets to Dai
     * @param _totalInputValue - The total amount of input asset to redeem
     * @param _outputAssetA - The output asset to receive
     * @param _auxData - The aux data of the interaction (minAmountPerFullShare)
     * @return outputValueA - The amount of output asset received
     */
    function _exitDai(uint256 _totalInputValue, address _outputAssetA, uint64 _auxData)
        internal
        returns (uint256 outputValueA, uint256, bool)
    {
        if (_outputAssetA != address(DAI)) {
            revert ErrorLib.InvalidOutputA();
        }

        // Migrate the asset.
        (uint256 wethAmount, uint256 daiAmount, uint256 usdcAmount) =
            DAI_MIGRATOR.migrate(_totalInputValue, _acceptanceToken());

        // Swap weth to usdc
        {
            if (wethAmount > 0) {
                bytes memory path = abi.encodePacked(address(WETH), uint24(500), address(USDC));
                usdcAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: wethAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // Swap usdc for dai on uniswap
        {
            if (usdcAmount > 0) {
                bytes memory path = abi.encodePacked(address(USDC), uint24(100), address(DAI));
                daiAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: usdcAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // @todo slippage aux could be 1e16 precision if there are very high interest amounts.
        uint256 minExpected = _totalInputValue * _auxData / 1e18;
        if (daiAmount < minExpected) {
            revert SlippageExceeded();
        }

        return (daiAmount, 0, false);
    }

    /**
     * @notice Redeems shares of WEWESTETH vault for weth, dai, usdc
     * swaps assets to Wsteth
     * @param _totalInputValue - The total amount of input asset to redeem
     * @param _outputAssetA - The output asset to receive
     * @param _auxData - The aux data of the interaction (minAmountPerFullShare)
     * @return outputValueA - The amount of output asset received
     */
    function _exitWsteth(uint256 _totalInputValue, address _outputAssetA, uint64 _auxData)
        internal
        returns (uint256 outputValueA, uint256, bool)
    {
        if (_outputAssetA != address(WSTETH)) {
            revert ErrorLib.InvalidOutputA();
        }

        // Migrate the asset.
        (uint256 wethAmount, uint256 daiAmount, uint256 usdcAmount) =
            WSTETH_MIGRATOR.migrate(_totalInputValue, _acceptanceToken());
        // Swap dai for usdc on uniswap
        {
            if (daiAmount > 0) {
                bytes memory path = abi.encodePacked(address(DAI), uint24(100), address(USDC));
                usdcAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: daiAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // Swap usdc to weth
        {
            if (usdcAmount > 0) {
                bytes memory path = abi.encodePacked(address(USDC), uint24(500), address(WETH));
                wethAmount += ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: usdcAmount,
                        amountOutMinimum: 0
                    })
                );
            }
        }

        // Swap weth to wsteth
        uint256 wstethBal;
        {
            if (wethAmount > 0) {
                IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
                    poolId: BALANCER_WSTETH_POOLID,
                    kind: IVault.SwapKind.GIVEN_IN,
                    assetIn: IAsset(address(WETH)),
                    assetOut: IAsset(address(WSTETH)),
                    amount: wethAmount,
                    userData: "0x00"
                });
                IVault.FundManagement memory fundManagement = IVault.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(address(this)),
                    toInternalBalance: false
                });

                wstethBal = BALANCER.swap(singleSwap, fundManagement, 0, block.timestamp);
            }
        }

        // @todo slippage aux could be 1e16 precision if there are very high interest amounts.
        uint256 minExpected = _totalInputValue * _auxData / 1e18;
        if (wstethBal < minExpected) {
            revert SlippageExceeded();
        }

        return (wstethBal, 0, false);
    }

    /**
     * @notice Computes the acceptance token for the migration.
     * @return The acceptance token.
     */
    function _acceptanceToken() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), TERMS_AND_CONDITIONS_HASH));
    }
}
