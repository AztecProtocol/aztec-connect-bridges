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
import {IAccountingToken} from "../interfaces/IAccountingToken.sol";
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
     * @param _underlyingAsset The address of the underlying asset
     * @param _aTokenAddress The address of the aToken, only used to define name, symbol and decimals for the zkatoken.
     */
    function setUnderlyingToZkAToken(address _underlyingAsset, address _aTokenAddress)
        external
        override(IAaveLendingBridge)
        onlyConfigurator
    {
        if (underlyingToZkAToken[_underlyingAsset] != address(0)) {
            revert ZkTokenAlreadyExists();
        }
        if (_aTokenAddress == address(0)) {
            revert InvalidAToken();
        }
        if (_aTokenAddress == _underlyingAsset) {
            revert InvalidAToken();
        }

        IERC20Metadata aToken = IERC20Metadata(_aTokenAddress);

        string memory name = string(abi.encodePacked("ZK-", aToken.name()));
        string memory symbol = string(abi.encodePacked("ZK-", aToken.symbol()));

        address zkAToken = address(new AccountingToken(name, symbol, aToken.decimals()));

        underlyingToZkAToken[_underlyingAsset] = zkAToken;

        performApprovals(_underlyingAsset);

        emit UnderlyingAssetListed(_underlyingAsset, zkAToken);
    }

    /**
     * @notice Approve Aave and RollupProcessor to pull underlying assets
     * And RollupProcessor to pull zkAToken accounting token
     * @dev The contract is not expected to hold any underlying assets while not inside convert.
     * Therefore we can infinite approve the used parties to save gas of future calls.
     * @dev Will revert if the underlying asset do not have a matching zkAToken
     * @param _underlyingAsset The address of the underlying asset
     */
    function performApprovals(address _underlyingAsset) public override(IAaveLendingBridge) {
        address zkAToken = underlyingToZkAToken[_underlyingAsset];
        if (underlyingToZkAToken[_underlyingAsset] == address(0)) {
            revert ZkTokenDontExist();
        }

        // SafeApprove not needed because we know the zkAToken follows IERC20;
        IERC20(zkAToken).approve(ROLLUP_PROCESSOR, type(uint256).max);

        // Approve the Aave Pool Proxy to pull underlying asset, using safeApproval to handle non ERC20 compliant tokens
        address pool = ADDRESSES_PROVIDER.getLendingPool();
        IERC20(_underlyingAsset).safeApprove(pool, 0);
        IERC20(_underlyingAsset).safeApprove(pool, type(uint256).max);

        // Approve the RollupProcessor to pull underlying asset, using safeApproval to handle non ERC20 compliant tokens
        IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, 0);
        IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
    }

    /**
     * @notice Convert function called by rollup processor, will enter or exit Aave lending position
     * @dev Only callable by the rollup processor when also satisfying asset sanity checks
     * @param _inputAssetA The input asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if inputAssetA is ETH, will wrap to WETH and supply to Aave
     * @param _inputAssetB Unused input asset, reverts if different from NOT_USED
     * @param _outputAssetA The output asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if outputAssetA is ETH, will unwrap WETH and transfer ETH
     * @param _outputAssetB Unused output asset, reverts if different from NOT_USED
     * @param _totalInputValue The input amount of inputAssetA
     * @param _interactionNonce The interaction nonce of the call
     * @return outputValueA The output amount of outputAssetA
     * @return outputValueB The ouput amount of outputAssetB
     * @return isAsync Always false for this bridge
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
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        (bool enter, address underlyingAddress, address zkATokenAddress, bool isEth) = _sanityConvert(
            _inputAssetA,
            _inputAssetB,
            _outputAssetA,
            _outputAssetB
        );

        if (enter) {
            outputValueA = _enter(underlyingAddress, zkATokenAddress, _totalInputValue, isEth);
        } else {
            outputValueA = _exit(underlyingAddress, zkATokenAddress, _totalInputValue, _interactionNonce, isEth);
        }

        return (outputValueA, 0, false);
    }

    /**
     * @notice Deposit into Aave with `amount` of `underlyingAsset` and return the corresponding amount of zkATokens
     * @param _underlyingAsset The address of the underlying asset
     * @param _zkATokenAddress The address of the representative zkAToken
     * @param _amount The amount of underlying asset to deposit
     * @param _isEth A flag that is true eth is deposited and false otherwise
     * @return The amount of zkAToken that was minted by the deposit
     */
    function _enter(
        address _underlyingAsset,
        address _zkATokenAddress,
        uint256 _amount,
        bool _isEth
    ) internal returns (uint256) {
        /**
         * Interaction flow:
         * 0. If receiving ETH, wrap it such that WETH can be deposited
         * 1. Fetch current liquidity index from Aave and compute scaled amount
         * 2. Deposit assets into Aave (receives aUnderlyingAsset in return)
         * 3. Mint zkATokens equal to scaled amount
         */

        if (_isEth) {
            WETH.deposit{value: _amount}();
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        // Compute scaledAmount rounded down. Aave uses rayDiv which can round up and down (at 0.5).
        // For consistency we round down.
        uint256 scaledAmount = (_amount * 1e27) / pool.getReserveNormalizedIncome(_underlyingAsset);
        if (scaledAmount == 0) {
            revert ZeroValue();
        }

        pool.deposit(_underlyingAsset, _amount, address(this), 0);

        IAccountingToken zkAToken = IAccountingToken(_zkATokenAddress);
        zkAToken.mint(address(this), scaledAmount);

        return scaledAmount;
    }

    /**
     * @notice Withdraw `underlyingAsset` from Aave
     * @param _underlyingAsset The address of the underlying asset
     * @param _zkATokenAddress The address of the representative zkAToken
     * @param _scaledAmount The amount of zkAToken to burn, used to derive underlying amount
     * @param _interactionNonce The nonce for the DeFi interaction
     * @param _isEth A flag that is true eth is to be withdrawn and false otherwise
     * @return The underlying amount of tokens withdrawn
     */
    function _exit(
        address _underlyingAsset,
        address _zkATokenAddress,
        uint256 _scaledAmount,
        uint256 _interactionNonce,
        bool _isEth
    ) internal returns (uint256) {
        /**
         * Interaction flow:
         * 0. Burn zkATokens equal to scaledAmount
         * 1. Compute the amount of underlying assets to withdraw
         * 2. Withdraw from the Aave pool
         * 3. If underlyingAsset is supposed to be ETH, unwrap WETH
         * Exit may fail if insufficient liquidity is available in the Aave pool.
         */

        IAccountingToken(_zkATokenAddress).burn(_scaledAmount);

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        // Compute the underlying amount rounded down. Aave uses rayMul which can round up and down (at 0.5)
        // For consistency we round down. Will leave aToken dust.
        uint256 underlyingAmount = (_scaledAmount * pool.getReserveNormalizedIncome(_underlyingAsset)) / 1e27;
        if (underlyingAmount == 0) {
            revert ZeroValue();
        }

        /// Return value by pool::withdraw() equal to underlyingAmount, unless underlying amount == type(uint256).max;
        uint256 outputValue = pool.withdraw(_underlyingAsset, underlyingAmount, address(this));

        if (_isEth) {
            WETH.withdraw(outputValue);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
        }

        return outputValue;
    }

    /**
     * @notice Claim liquidity mining rewards and transfer to the beneficiary
     * @dev Only callable by the configurator
     * @param _incentivesController The address of the incentives controller
     * @param _assets The list of assets to claim rewards for
     * @param _beneficiary The address to receive the rewards
     * @return The amount of rewards claimed
     */
    function claimLiquidityRewards(
        address _incentivesController,
        address[] calldata _assets,
        address _beneficiary
    ) external onlyConfigurator returns (uint256) {
        return IAaveIncentivesController(_incentivesController).claimRewards(_assets, type(uint256).max, _beneficiary);
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
     * @param _inputAssetA The input asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if inputAssetA is ETH, will wrap to WETH and supply to Aave
     * @param _inputAssetB Unused input asset, reverts if different from NOT_USED
     * @param _outputAssetA The output asset, accepts Eth or ERC20 if supported underlying or zkAToken
     * @dev if outputAssetA is ETH, will unwrap WETH and transfer ETH
     * @param _outputAssetB Unused output asset, reverts if different from NOT_USED
     * @return True if input asset == underlying asset, false otherwise
     * @return The address of the underlying asset, WETH if supplying or exiting with ETH
     * @return The address of the zkAToken
     * @return True if wrap/unwrap to/from ETH is needed, false otherwise
     */
    function _sanityConvert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _inputAssetB,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory _outputAssetB
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
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            revert InputAssetAAndOutputAssetAIsEth();
        }
        if (
            !(_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            revert InputAssetANotERC20OrEth();
        }
        if (
            !(_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            revert OutputAssetANotERC20OrEth();
        }
        if (_inputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED) {
            revert InputAssetBNotEmpty();
        }
        if (_outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED) {
            revert OutputAssetBNotEmpty();
        }

        address inputAsset = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : _inputAssetA.erc20Address;

        address outputAsset = _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ? address(WETH)
            : _outputAssetA.erc20Address;

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

        bool isEth = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH ||
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH;

        return (inputAsset == underlying, underlying, zkAToken, isEth);
    }
}
