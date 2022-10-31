// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IStableMaster} from "../../interfaces/angle/IStableMaster.sol";
import {IPoolManager, IStrategy} from "../../interfaces/angle/IPoolManager.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";

/**
 * @title Angle Protocol bridge contract.
 * @author Angle Protocol Team
 * @notice Allows a user to deposit/withdraw his tokens to/from Angle Protocol
 * @dev Enter Angle Protocol as an SLP by depositing authorized tokens
 */
contract AngleSLPBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IStableMaster public constant STABLE_MASTER = IStableMaster(0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87);

    address public constant POOLMANAGER_DAI = 0xc9daabC677F3d1301006e723bD21C60be57a5915;
    address public constant POOLMANAGER_USDC = 0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD;
    address public constant POOLMANAGER_WETH = 0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2;
    address public constant POOLMANAGER_FRAX = 0x6b4eE7352406707003bC6f6b96595FD35925af48;

    address public constant SANDAI = 0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450;
    address public constant SANUSDC = 0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad;
    address public constant SANWETH = 0x30c955906735e48D73080fD20CB488518A6333C8;
    address public constant SANFRAX = 0xb3B209Bb213A5Da5B947C56f2C770b3E1015f1FE;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 internal constant DUST = 1;

    /**
     * @notice Set address of rollup processor and approves all poolManagers
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _preApprove(POOLMANAGER_DAI);
        _preApprove(POOLMANAGER_USDC);
        _preApprove(POOLMANAGER_WETH);
        _preApprove(POOLMANAGER_FRAX);

        uint256[] memory criterias = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        criterias[0] = 0;
        criterias[1] = 1;

        gasUsage[0] = 180000;
        gasUsage[1] = 210000;

        // Min gas per minute set in such a way that bridge call gets subsidized fully if not executed in 2 days
        // 180k / (24 * 60) / 2 ~ 65
        minGasPerMinute[0] = 65;
        // 210k / (24 * 60) / 2 ~ 75
        minGasPerMinute[1] = 75;

        SUBSIDY.setGasUsageAndMinGasPerMinute(criterias, gasUsage, minGasPerMinute);
    }

    receive() external payable {}

    /**
     * @notice Deposit tokens into Angle Protocol as an SLP and receive sanTokens (yield bearing)
     * @param _inputAssetA - ERC20/ETH (deposit), or sanToken (withdraw)
     * @param _outputAssetA - sanToken (deposit), or ERC20/ETH (withdraw)
     * @param _totalInputValue - amount of ERC20/ETH to deposit, or the amount of sanToken to withdraw
     * @param _auxData - 0 (deposit), 1 (withdraw)
     * @return outputValueA - the amount of output asset to return
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address _rollupBeneficiary
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
        address inputAssetA;
        address outputAssetA;

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            inputAssetA = _inputAssetA.erc20Address;
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: _totalInputValue}();
            inputAssetA = address(WETH);
        } else {
            revert ErrorLib.InvalidInputA();
        }

        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            outputAssetA = _outputAssetA.erc20Address;
        } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            outputAssetA = address(WETH);
        } else {
            revert ErrorLib.InvalidOutputA();
        }

        if (_totalInputValue < 10) revert ErrorLib.InvalidInputAmount();

        if (_auxData == 0) {
            (address poolManager, address sanToken) = getPoolManagerAndSanToken(inputAssetA);
            if (poolManager == address(0) || sanToken == address(0)) revert ErrorLib.InvalidInputA();
            if (sanToken != outputAssetA) revert ErrorLib.InvalidOutputA();

            STABLE_MASTER.deposit(_totalInputValue, address(this), poolManager);
        } else if (_auxData == 1) {
            (address poolManager, address sanToken) = getPoolManagerAndSanToken(outputAssetA);
            if (poolManager == address(0) || sanToken == address(0)) revert ErrorLib.InvalidOutputA();
            if (sanToken != inputAssetA) revert ErrorLib.InvalidInputA();

            _withdraw(poolManager, _totalInputValue, outputAssetA);
        } else {
            revert ErrorLib.InvalidAuxData();
        }

        outputValueA = IERC20(outputAssetA).balanceOf(address(this)) - DUST;

        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.withdraw(outputValueA);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }

        SUBSIDY.claimSubsidy(_auxData, _rollupBeneficiary);
    }

    function computeCriteria(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint64 _auxData
    ) public pure override(BridgeBase) returns (uint256) {
        if (_auxData > 1) {
            revert ErrorLib.InvalidAuxData();
        }
        return _auxData;
    }

    /**
     * @notice Returns the PoolManager address and the SanToken address associated with a collateral
     * @param _collateral Address of the collateral
     * @return poolManager - address of the poolManager
     * @return sanToken - address of the sanToken
     */
    function getPoolManagerAndSanToken(address _collateral)
        public
        pure
        returns (address poolManager, address sanToken)
    {
        if (_collateral == DAI) {
            poolManager = POOLMANAGER_DAI;
            sanToken = SANDAI;
        } else if (_collateral == USDC) {
            poolManager = POOLMANAGER_USDC;
            sanToken = SANUSDC;
        } else if (_collateral == address(WETH)) {
            poolManager = POOLMANAGER_WETH;
            sanToken = SANWETH;
        } else if (_collateral == FRAX) {
            poolManager = POOLMANAGER_FRAX;
            sanToken = SANFRAX;
        }
    }

    /**
     * @notice Withdraw underlying ERC20 from Angle Protocol
     * @param _poolManager Address of the poolManager
     * @param _amount Amount of sanToken to withdraw
     * @param _outputAssetA Address of the underlying ERC20
     */
    function _withdraw(
        address _poolManager,
        uint256 _amount,
        address _outputAssetA
    ) internal {
        // we check if we need to harvest or not
        (, , , , , uint256 sanRate, , , ) = STABLE_MASTER.collateralMap(_poolManager);
        uint256 estimatedOutputValue = (_amount * sanRate) / 1e18;
        uint256 currentBalance = IERC20(_outputAssetA).balanceOf(address(_poolManager));

        // if there is enough liquidity -> no need to harvest
        if (estimatedOutputValue < currentBalance) {
            STABLE_MASTER.withdraw(_amount, address(this), address(this), _poolManager);
        } else {
            // we withdraw what we can (98% of the current balance), then harvest, then withdraw the rest
            uint256 toWithdraw = (((currentBalance * 1e18) / sanRate) * 98) / 100;
            STABLE_MASTER.withdraw(toWithdraw, address(this), address(this), _poolManager);

            // Harvest the main strategy to free funds and make them available to withdraw
            IStrategy strategy = IStrategy(IPoolManager(_poolManager).strategyList(0));
            strategy.harvest();
            STABLE_MASTER.withdraw(_amount - toWithdraw, address(this), address(this), _poolManager);
        }
    }

    /**
     * @notice Pre-approval of all tokens related to a poolManager, should be done in the constructor
     * @param _poolManager Address of the poolManager
     */
    function _preApprove(address _poolManager) private {
        (IERC20 token, address sanToken, , , , , , , ) = STABLE_MASTER.collateralMap(_poolManager);

        uint256 allowance = token.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            token.safeApprove(ROLLUP_PROCESSOR, 0);
            token.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }
        allowance = token.allowance(address(this), address(STABLE_MASTER));
        if (allowance != type(uint256).max) {
            token.safeApprove(address(STABLE_MASTER), 0);
            token.safeApprove(address(STABLE_MASTER), type(uint256).max);
        }

        allowance = IERC20(sanToken).allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            IERC20(sanToken).safeApprove(ROLLUP_PROCESSOR, 0);
            IERC20(sanToken).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }
    }
}
