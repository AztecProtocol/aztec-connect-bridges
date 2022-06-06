// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILendingPoolAddressesProvider} from "./../imports/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "./../imports/interfaces/ILendingPool.sol";
import {IPool} from "./../imports/interfaces/IPool.sol";
import {IScaledBalanceToken} from "./../imports/interfaces/IScaledBalanceToken.sol";
import {IAaveIncentivesController} from "./../imports/interfaces/IAaveIncentivesController.sol";
import {IAccountingToken} from "./../imports/interfaces/IAccountingToken.sol";
import {IWETH9} from "./../imports/interfaces/IWETH9.sol";

import {DataTypes} from "./../imports/libraries/DataTypes.sol";

import {IRollupProcessor} from "../../../interfaces/IRollupProcessor.sol";
import {IDefiBridge} from "../../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../../aztec/AztecTypes.sol";

import {IAaveLendingBridge} from "./interfaces/IAaveLendingBridge.sol";

import {AccountingToken} from "./../AccountingToken.sol";

/**
 * @notice AaveLendingBridge implementation that allow a configurator to "list" a reserve and then anyone can
 * permissionlessly deposit and withdraw funds into the listed reserves. Configurator cannot remove nor update listings
 * @dev Only assets with large volume should be listed to ensure sufficiently large privacy sets
 * @author Lasse Herskind
 */
contract AaveLendingBridge is IAaveLendingBridge, IDefiBridge {
    using SafeERC20 for IERC20;

    error InvalidCaller();
    error InputAssetAAndOutputAssetAIsEth();
    error InputAssetANotERC20OrEth();
    error OutputAssetANotERC20OrEth();
    error InputAssetBNotEmpty();
    error OutputAssetBNotEmpty();
    error InputAssetInvalid();
    error OutputAssetInvalid();
    error InputAssetNotEqZkAToken();
    error InvalidAToken();
    error ZkTokenAlreadyExists();
    error ZkTokenDontExist();
    error ZeroValue();
    error AsyncDisabled();

    event UnderlyingAssetListed(address underlyingAsset, address zkAToken);

    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public immutable ROLLUP_PROCESSOR;
    ILendingPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    address public immutable CONFIGURATOR;

    /// Mapping underlying assets to the zk aToken used for accounting
    mapping(address => address) public underlyingToZkAToken;

    modifier onlyConfigurator() {
        if (msg.sender != CONFIGURATOR) {
            revert InvalidCaller();
        }
        _;
    }

    /// Need to be able to receive ETH for WETH unwrapping
    receive() external payable {}

    constructor(
        address _rollupProcessor,
        address _addressesProvider,
        address _configurator
    ) {
        ROLLUP_PROCESSOR = _rollupProcessor;
        /// @dev addressesProvider is used to fetch pool, used in case Aave governance update pool proxy
        ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(_addressesProvider);
        CONFIGURATOR = _configurator;
    }

    /**
     * @notice Add the underlying asset to the set of supported assets
     * @dev For the underlying to be accepted, the asset must be supported in Aave.
     * Also, the underlying asset MUST NOT be a rebasing token, as scaled balance computation differs from standard.
     * These properties must be enforced by the configurator.
     * @dev Underlying assets that already is supported cannot be added again.
     * @dev Approving RollupProcessor and Aave to pull listed asset and zkAToken
     * @param underlyingAsset The address of the underlying asset
     * @param aTokenAddress The address of the aToken, only used to define name, symbol and decimals for the zkatoken.
     */
    function setUnderlyingToZkAToken(address underlyingAsset, address aTokenAddress)
        external
        override(IAaveLendingBridge)
        onlyConfigurator
    {
        if (underlyingToZkAToken[underlyingAsset] != address(0)) {
            revert ZkTokenAlreadyExists();
        }
        if (aTokenAddress == address(0)) {
            revert InvalidAToken();
        }
        if (aTokenAddress == underlyingAsset) {
            revert InvalidAToken();
        }

        IERC20Metadata aToken = IERC20Metadata(aTokenAddress);

        string memory name = string(abi.encodePacked("ZK-", aToken.name()));
        string memory symbol = string(abi.encodePacked("ZK-", aToken.symbol()));

        address zkAToken = address(new AccountingToken(name, symbol, aToken.decimals()));

        underlyingToZkAToken[underlyingAsset] = zkAToken;

        performApprovals(underlyingAsset);

        emit UnderlyingAssetListed(underlyingAsset, zkAToken);
    }

    /**
     * @notice Approve Aave and RollupProcessor to pull underlying assets
     * And RollupProcessor to pull zkAToken accounting token
     * @dev The contract is not expected to hold any underlying assets while not inside convert.
     * Therefore we can infinite approve the used parties to save gas of future calls.
     * @dev Will revert if the underlying asset do not have a matching zkAToken
     * @param underlyingAsset The address of the underlying asset
     */
    function performApprovals(address underlyingAsset) public override(IAaveLendingBridge) {
        address zkAToken = underlyingToZkAToken[underlyingAsset];
        if (underlyingToZkAToken[underlyingAsset] == address(0)) {
            revert ZkTokenDontExist();
        }

        // SafeApprove not needed because we know the zkAToken follows IERC20;
        IERC20(zkAToken).approve(ROLLUP_PROCESSOR, type(uint256).max);

        // Approve the Aave Pool Proxy to pull underlying asset, using safeApproval to handle non ERC20 compliant tokens
        address pool = ADDRESSES_PROVIDER.getLendingPool();
        IERC20(underlyingAsset).safeApprove(pool, 0);
        IERC20(underlyingAsset).safeApprove(pool, type(uint256).max);

        // Approve the RollupProcessor to pull underlying asset, using safeApproval to handle non ERC20 compliant tokens
        IERC20(underlyingAsset).safeApprove(ROLLUP_PROCESSOR, 0);
        IERC20(underlyingAsset).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
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
        uint64 auxData,
        address rollupBeneficiary
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
     * @param zkATokenAddress The address of the representative zkAToken
     * @param amount The amount of underlying asset to deposit
     * @param isEth A flag that is true eth is deposited and false otherwise
     * @return The amount of zkAToken that was minted by the deposit
     */
    function _enter(
        address underlyingAsset,
        address zkATokenAddress,
        uint256 amount,
        bool isEth
    ) internal returns (uint256) {
        /**
         * Interaction flow:
         * 0. If receiving ETH, wrap it such that WETH can be deposited
         * 1. Fetch current liquidity index from Aave and compute scaled amount
         * 2. Deposit assets into Aave (receives aUnderlyingAsset in return)
         * 3. Mint zkATokens equal to scaled amount
         */

        if (isEth) {
            WETH.deposit{value: amount}();
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        // Compute scaledAmount rounded down. Aave uses rayDiv which can round up and down (at 0.5).
        // For consistency we round down.
        uint256 scaledAmount = (amount * 1e27) / pool.getReserveNormalizedIncome(underlyingAsset);
        if (scaledAmount == 0) {
            revert ZeroValue();
        }

        pool.deposit(underlyingAsset, amount, address(this), 0);

        IAccountingToken zkAToken = IAccountingToken(zkATokenAddress);
        zkAToken.mint(address(this), scaledAmount);

        return scaledAmount;
    }

    /**
     * @notice Withdraw `underlyingAsset` from Aave
     * @param underlyingAsset The address of the underlying asset
     * @param zkATokenAddress The address of the representative zkAToken
     * @param scaledAmount The amount of zkAToken to burn, used to derive underlying amount
     * @param isEth A flag that is true eth is to be withdrawn and false otherwise
     * @return The underlying amount of tokens withdrawn
     */
    function _exit(
        address underlyingAsset,
        address zkATokenAddress,
        uint256 scaledAmount,
        uint256 interactionNonce,
        bool isEth
    ) internal returns (uint256) {
        /**
         * Interaction flow:
         * 0. Burn zkATokens equal to scaledAmount
         * 1. Compute the amount of underlying assets to withdraw
         * 2. Withdraw from the Aave pool
         * 3. If underlyingAsset is supposed to be ETH, unwrap WETH
         * Exit may fail if insufficient liquidity is available in the Aave pool.
         */

        IAccountingToken(zkATokenAddress).burn(scaledAmount);

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        // Compute the underlying amount rounded down. Aave uses rayMul which can round up and down (at 0.5)
        // For consistency we round down. Will leave aToken dust.
        uint256 underlyingAmount = (scaledAmount * pool.getReserveNormalizedIncome(underlyingAsset)) / 1e27;
        if (underlyingAmount == 0) {
            revert ZeroValue();
        }

        /// Return value by pool::withdraw() equal to underlyingAmount, unless underlying amount == type(uint256).max;
        uint256 outputValue = pool.withdraw(underlyingAsset, underlyingAmount, address(this));

        if (isEth) {
            WETH.withdraw(outputValue);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(interactionNonce);
        }

        return outputValue;
    }

    /**
     * @notice Claim liquidity mining rewards and transfer to the beneficiary
     * @dev Only callable by the configurator
     * @param incentivesController The address of the incentives controller
     * @param assets The list of assets to claim rewards for
     * @param beneficiary The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function claimLiquidityRewards(
        address incentivesController,
        address[] calldata assets,
        address beneficiary
    ) external onlyConfigurator returns (uint256) {
        return IAaveIncentivesController(incentivesController).claimRewards(assets, type(uint256).max, beneficiary);
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
        revert AsyncDisabled();
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
        if (msg.sender != ROLLUP_PROCESSOR) {
            revert InvalidCaller();
        }
        if (
            inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            revert InputAssetAAndOutputAssetAIsEth();
        }
        if (
            !(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                inputAssetA.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            revert InputAssetANotERC20OrEth();
        }
        if (
            !(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                outputAssetA.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            revert OutputAssetANotERC20OrEth();
        }
        if (inputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED) {
            revert InputAssetBNotEmpty();
        }
        if (outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED) {
            revert OutputAssetBNotEmpty();
        }

        address inputAsset = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : inputAssetA.erc20Address;

        address outputAsset = outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : outputAssetA.erc20Address;

        if (inputAsset == address(0)) {
            revert InputAssetInvalid();
        }
        if (outputAsset == address(0)) {
            revert OutputAssetInvalid();
        }

        address underlying;
        address zkAToken;
        address zkATokenCandidate = underlyingToZkAToken[inputAsset];

        if (zkATokenCandidate == address(0)) {
            underlying = outputAsset;
            zkAToken = underlyingToZkAToken[underlying];
            if (inputAsset != zkAToken) {
                revert InputAssetNotEqZkAToken();
            }
        } else {
            underlying = inputAsset;
            zkAToken = zkATokenCandidate;
        }

        bool isEth = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH ||
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH;

        return (inputAsset == underlying, underlying, zkAToken, isEth);
    }
}
