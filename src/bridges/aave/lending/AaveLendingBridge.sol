// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import {ILendingPoolAddressesProvider} from './../imports/interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from './../imports/interfaces/ILendingPool.sol';
import {IPool} from './../imports/interfaces/IPool.sol';
import {IScaledBalanceToken} from './../imports/interfaces/IScaledBalanceToken.sol';
import {IAaveIncentivesController} from './../imports/interfaces/IAaveIncentivesController.sol';
import {IAccountingToken} from './../imports/interfaces/IAccountingToken.sol';
import {IWETH9} from './../imports/interfaces/IWETH9.sol';

import {WadRayMath} from './../imports/libraries/WadRayMath.sol';
import {DataTypes} from './../imports/libraries/DataTypes.sol';

import {IRollupProcessor} from '../../../interfaces/IRollupProcessor.sol';
import {IDefiBridge} from '../../../interfaces/IDefiBridge.sol';
import {AztecTypes} from '../../../aztec/AztecTypes.sol';

import {IAaveLendingBridge} from './interfaces/IAaveLendingBridge.sol';

import {Errors} from './libraries/Errors.sol';
import {AccountingToken} from './../AccountingToken.sol';

/**
 * @notice AaveLendingBridge implementation that allow a configurator to "list" a reserve and then anyone can
 * permissionlessly deposit and withdraw funds into the listed reserves. Configurator cannot remove nor update listings
 * @dev Only assets with large volume should be listed to ensure
 * @author Lasse Herskind
 */
contract AaveLendingBridge is IAaveLendingBridge, IDefiBridge {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public immutable ROLLUP_PROCESSOR;
    ILendingPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    address public immutable REWARDS_BENEFICIARY;
    address public immutable CONFIGURATOR;

    /// Mapping underlying assets to the zk aToken used for accounting
    mapping(address => address) public underlyingToZkAToken;
    /// Mapping underlying assets to the aToken in Aave
    mapping(address => address) public underlyingToAToken;

    modifier onlyConfigurator() {
        require(msg.sender == CONFIGURATOR, Errors.INVALID_CALLER);
        _;
    }

    receive() external payable {}

    constructor(
        address _rollupProcessor,
        address _addressesProvider,
        address _rewardsBeneficiary,
        address _configurator
    ) {
        ROLLUP_PROCESSOR = _rollupProcessor;
        /// @dev addressesProvider is used to fetch pool, used in case Aave governance update pool proxy
        ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(_addressesProvider);
        REWARDS_BENEFICIARY = _rewardsBeneficiary;
        CONFIGURATOR = _configurator;
    }

    /**
     * @notice Add the underlying asset to the set of supported assets
     * @dev For the underlying to be accepted, the asset must be supported in Aave
     * @dev Underlying assets that already is supported cannot be added again.
     */
    function setUnderlyingToZkAToken(address underlyingAsset, address aTokenAddress) external onlyConfigurator {
        require(underlyingToZkAToken[underlyingAsset] == address(0), Errors.ZK_TOKEN_ALREADY_SET);
        require(aTokenAddress != address(0), Errors.INVALID_ATOKEN);
        require(aTokenAddress != underlyingAsset, Errors.INVALID_ATOKEN);

        IERC20Metadata aToken = IERC20Metadata(aTokenAddress);

        string memory name = string(abi.encodePacked('ZK-', aToken.name()));
        string memory symbol = string(abi.encodePacked('ZK-', aToken.symbol()));

        underlyingToZkAToken[underlyingAsset] = address(new AccountingToken(name, symbol, aToken.decimals()));
        underlyingToAToken[underlyingAsset] = address(aToken);
    }

    /**
     * @notice Convert function called by rollup processor, will enter or exit Aave lending position
     * @dev Only callable by the rollup processor when also satisfying asset sanity checks
     * @param inputAssetA The input asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if inputAssetA is ETH, will wrap to WETH and supply to Aave
     * @param inputAssetB Unused input asset, reverts if different from NOT_USED
     * @param outputAssetA The output asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if outputAssetA is ETH, will unwrap WETH and transfer ETH
     * @param outputAssetB Unused output asset, reverts if different from NOT_USED
     * @param totalInputValue The input amount of inputAssetA
     * @param interactionNonce The interaction nonce of the call
     * @param auxData Unused auxiliary information
     * @return outputValueA The output amount of outputAssetA
     * @return outputValueB The ouput amount of outputAssetB
     * @return isAsync Always false for this bridge
     */
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        (bool enter, address underlyingAddress, address zkATokenAddress, bool isEth) = _sanityConvert(
            inputAssetA,
            inputAssetB,
            outputAssetA,
            outputAssetB
        );

        if (enter) {
            outputValueA = _enter(underlyingAddress, zkATokenAddress, totalInputValue, isEth);
        } else {
            outputValueA = _exit(underlyingAddress, zkATokenAddress, totalInputValue, interactionNonce, isEth);
        }

        return (outputValueA, 0, false);
    }

    /**
     * @notice Deposit into Aave with `amount` of `underlyingAsset` and return the corresponding amount of zkATokens
     * @param underlyingAsset The address of the underlying asset
     * @param amount The amount of underlying asset to deposit
     * @return The amount of zkAToken that was minted by the deposit
     */
    function _enter(
        address underlyingAsset,
        address zkATokenAddress,
        uint256 amount,
        bool isEth
    ) internal returns (uint256) {
        if (isEth) {
            // 0. Wrap ETH if necessary
            WETH.deposit{value: amount}();
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        IScaledBalanceToken aToken = IScaledBalanceToken(underlyingToAToken[underlyingAsset]);

        IAccountingToken zkAToken = IAccountingToken(zkATokenAddress);

        // 1. Read the scaled balance
        uint256 scaledBalance = aToken.scaledBalanceOf(address(this));

        // 2. Approve totalInputValue to be deposited
        IERC20(underlyingAsset).safeApprove(address(pool), amount);

        // 3. Deposit totalInputValue of inputAssetA on AAVE lending pool
        pool.deposit(underlyingAsset, amount, address(this), 0);

        // 4. Mint the difference between the scaled balance at the start of the interaction and after the deposit as our zkAToken
        uint256 diff = aToken.scaledBalanceOf(address(this)).sub(scaledBalance);
        zkAToken.mint(address(this), diff);

        // 5. Approve processor to pull zk aTokens.
        zkAToken.approve(ROLLUP_PROCESSOR, diff);
        return diff;
    }

    /**
     * @notice Withdraw `underlyingAsset` from Aave
     * @param underlyingAsset The address of the underlying asset
     * @param scaledAmount The amount of zkAToken to burn, used to derive underlying amount
     * @return The underlying amount of tokens withdrawn
     */
    function _exit(
        address underlyingAsset,
        address zkATokenAddress,
        uint256 scaledAmount,
        uint256 interactionNonce,
        bool isEth
    ) internal returns (uint256) {
        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        // 1. Compute the amount from the scaledAmount supplied
        uint256 underlyingAmount = scaledAmount.rayMul(pool.getReserveNormalizedIncome(underlyingAsset));

        // 2. Burn the supplied amount of zkAToken as this has now been withdrawn
        IAccountingToken(zkATokenAddress).burn(scaledAmount);

        // 3. Lend totalInputValue of inputAssetA on AAVE lending pool and return the amount of tokens
        uint256 outputValue = pool.withdraw(underlyingAsset, underlyingAmount, address(this));

        if (isEth) {
            // 4. Withdraw ETH from WETH and send eth to ROLLUP_PROCESSOR
            WETH.withdraw(outputValue);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(interactionNonce);
        } else {
            // 4. Approve rollup to spend underlying
            IERC20(underlyingAsset).safeApprove(ROLLUP_PROCESSOR, outputValue);
        }

        return outputValue;
    }

    /**
     * @notice Claim liquidity mining rewards and transfer to the beneficiary
     */
    function claimLiquidityRewards(address incentivesController, address[] calldata assets) external returns (uint256) {
        // Just to have an initial claim rewards function
        // Don't like that we are accepting any contract from the users. Not obvious how they would abuse though.
        // Assets are approved to the lendingPool, but it does not have a claimRewards function that can be abused.
        // The malicious controller can be used to reenter. But limited what can be entered again as convert can only be entered by the processor.
        // To limit attack surface. Can pull incentives controller from assets and ensure that the assets are actually supported assets.
        return
            IAaveIncentivesController(incentivesController).claimRewards(
                assets,
                type(uint256).max,
                REWARDS_BENEFICIARY
            );
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
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false, 'Not implemented');
        return (0, 0, false);
    }

    /**
     * @notice sanity checks of the caller and inputs to the convert function
     * @param inputAssetA The input asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if inputAssetA is ETH, will wrap to WETH and supply to Aave
     * @param inputAssetB Unused input asset, reverts if different from NOT_USED
     * @param outputAssetA The output asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if outputAssetA is ETH, will unwrap WETH and transfer ETH
     * @param outputAssetB Unused output asset, reverts if different from NOT_USED
     * @return True if input asset == underlying asset, false otherwise
     * @return The address of the underlying asset, WETH if supplying or exiting with ETH
     * @return The address of the zkAToken
     * @return True if wrap/unwrap to/from ETH is needed, false otherwise
     */
    function _sanityConvert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB
    )
        internal
        view
        returns (
            bool,
            address,
            address,
            bool
        )
    {
        require(msg.sender == ROLLUP_PROCESSOR, Errors.INVALID_CALLER);
        require(
            !(inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
                outputAssetA.assetType == AztecTypes.AztecAssetType.ETH),
            Errors.INPUT_ASSET_A_AND_OUTPUT_ASSET_A_IS_ETH
        );
        require(
            inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                inputAssetA.assetType == AztecTypes.AztecAssetType.ETH,
            Errors.INPUT_ASSET_A_NOT_ERC20_OR_ETH
        );
        require(
            outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                outputAssetA.assetType == AztecTypes.AztecAssetType.ETH,
            Errors.OUTPUT_ASSET_A_NOT_ERC20_OR_ETH
        );
        require(inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED, Errors.INPUT_ASSET_B_NOT_EMPTY);
        require(outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED, Errors.OUTPUT_ASSET_B_NOT_EMPTY);

        address inputAsset = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : inputAssetA.erc20Address;

        address outputAsset = outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : outputAssetA.erc20Address;

        require(inputAsset != address(0), Errors.INPUT_ASSET_INVALID);
        require(outputAsset != address(0), Errors.OUTPUT_ASSET_INVALID);

        address underlying;
        address zkAToken;
        address zkATokenCandidate = underlyingToZkAToken[inputAsset];

        if (zkATokenCandidate == address(0)) {
            underlying = outputAsset;
            zkAToken = underlyingToZkAToken[underlying];
            require(inputAsset == zkAToken, Errors.INPUT_ASSET_NOT_EQ_ZK_ATOKEN);
        } else {
            underlying = inputAsset;
            zkAToken = zkATokenCandidate;
        }

        bool isEth = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH ||
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH;

        return (inputAsset == underlying, underlying, zkAToken, isEth);
    }
}
