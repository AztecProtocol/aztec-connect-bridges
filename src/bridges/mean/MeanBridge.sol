// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {IDCAHub} from "../../interfaces/mean/IDCAHub.sol";
import {ITransformerRegistry} from "../../interfaces/mean/ITransformerRegistry.sol";
import {ITransformer} from "../../interfaces/mean/ITransformer.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {MeanErrorLib} from "./MeanErrorLib.sol";
import {MeanSwapIntervalDecodingLib} from "./MeanSwapIntervalDecodingLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title Aztec Connect Bridge for creating DCA positions on Mean Finance
 * @author NChamo
 * @notice You can use this contract to deposit and withdraw on Mean Finance
 */
contract MeanBridge is BridgeBase, Ownable2Step {

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice A position's id, and the aux data used to create said position
    struct PositionData {
        uint192 positionId;
        uint64 auxData;
    }

    /// @notice The known funds for a specific position
    struct PositionFunds {
        // Marks if the funds were already extracted from the DCA Hub, or if we still need to
        bool wereFundsExtracted;
        // The position's swapped funds when it was terminated
        uint248 swappedFunds;
        // The position's unswapped funds when it was terminated
        uint256 unswappedFunds;
    }

    /// @notice Whether the action is a deposit, or a withdraw
    enum Action {
        DEPOSIT,
        WITHDRAW
    }

    uint256 public constant VIRTUAL_SHARES_PER_POSITION = type(uint128).max;
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IDCAHub public immutable DCA_HUB;
    ITransformerRegistry public immutable TRANSFORMER_REGISTRY;
    mapping(uint256 => PositionData) public positionByNonce; // interaction nonce => position data
    mapping(uint256 => PositionFunds) public fundsByPositionId; // position id => funds

    // Note: the idea here is simple. All tokens that we want to DCA, need to be registered here. This
    // only includes tokens that will be deposited and swapped on the DCA Hub. ETH, for example, is never
    // deposited directly to the Hub, since it's first converted to WETH, so we wouldn't need to register it.abi
    // Why are we doing this? 
    // - In the case of yield-while-DCAing, one token (for example DAI) can have multiple yield platforms. 
    // Each platform is supported by a ERC4626 wrapper but, we can't pass the wrapper's address directly. 
    // However, this registry will allow us to assign a unique id to each address, and we can pass 
    // said id as part of the aux data
    // - Since we want to store a position's tokens, it's cheaper to store a 16 bits id than a 20 bytes address
    EnumerableSet.AddressSet internal tokenRegistry;

    event NewTokensSupported(address[] tokens);

    /**
     * @notice Sets address of rollup processor and Mean contracts
     * @param _hub - The address of the DCA Hub
     * @param _transformerRegistry - The address of the Transformer Registry
     * @param _owner - The account that will own the bridge
     * @param _rollupProcessor - Address of rollup processor
     */
    constructor(IDCAHub _hub, ITransformerRegistry _transformerRegistry, address _owner, address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _transferOwnership(_owner);
        DCA_HUB = _hub;
        TRANSFORMER_REGISTRY = _transformerRegistry;
    }

    // Note: we need to be able to receive ETH to deposit as WETH
    receive() external payable {}

    /**
     * @notice A function which will allow the caller to deposit or withdraw from Mean Finance
     * @param _inputAssetA - ETH or ERC20 token to deposit / virtual asset in the case of a withdraw
     * @param _outputAssetA - Virtual asset in the case of deposit / ERC or ERC20 to withdraw
     * @param _outputAssetB - Should only be used in the case of an emergency withdraw, and it should have the ETH or ERC20 token that was deposited
     * @param _inputValue - Amount of `inputAssetA` to deposit/withdraw
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @param _auxData - The amount of swaps, swap interval and token ids encoded together
     * @param _rollupBeneficiary - Address which receives subsidy if the call is eligible for it
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address _rollupBeneficiary
    ) external payable override(BridgeBase) onlyRollup returns (uint256, uint256, bool) {
        // Execute deposit or withdraw, depending on the input asset
        (uint256 _outputValueA, uint256 _outputValueB, uint256 _criteria) = (_inputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL)
            ? _deposit(_inputAssetA, _outputAssetA, _inputValue, _interactionNonce, _auxData)
            : _withdraw(_inputAssetA, _outputAssetA, _outputAssetB, _inputValue, _interactionNonce, _auxData);

        // Accumulate subsidy to _rollupBeneficiary
        SUBSIDY.claimSubsidy(_criteria, _rollupBeneficiary);
        
        return (_outputValueA, _outputValueB, false);
    }

    /**
     * @notice Defines subsidies for DCA pairs
     * @dev Can only be called by the contract's owner
     */
    function setSubsidies(
        uint256[] calldata _criteria,
        uint32[] calldata _gasUsage,
        uint32[] calldata _minGasPerMinute) external onlyOwner {
        SUBSIDY.setGasUsageAndMinGasPerMinute(_criteria, _gasUsage, _minGasPerMinute);
    }

    /**
     * @notice Registers tokens internally, so that they can be referenced by an index instead of the full address.
     *         This function also executes max approvals for the given tokens
     * @dev Anyone can call this method, it's not permissioned
     * @param _tokens - The tokens to register
     */
    function registerTokens(address[] calldata _tokens) external {
        for (uint i; i < _tokens.length; ) {
            address _token = _tokens[i];
            if (!DCA_HUB.allowedTokens(_token)) {
                revert MeanErrorLib.TokenNotAllowed(_token);
            } 
            // Note: we know that we can only support 2**16 tokens on the registry, but we are not checking that
            // here. This is because Mean won't ever support that many tokens
            bool _added = tokenRegistry.add(_token);
            if (!_added) {
                revert MeanErrorLib.TokenAlreadyRegistered(_token);
            }

            _maxApprove(_token, address(DCA_HUB));
            _maxApprove(_token, address(TRANSFORMER_REGISTRY));
            _maxApprove(_token, address(ROLLUP_PROCESSOR));

            unchecked {
                ++i;
            }
        }

        emit NewTokensSupported(_tokens);
    }    

    /**
     * @notice Set all the necessary approvals for the DCA hub, the transformer registry and the rollup processor
     * @param _tokens - The tokens to approve
     */
    function maxApprove(address[] calldata _tokens) external {
        for (uint i; i < _tokens.length; ) {
            address _token = _tokens[i];
            _maxApprove(_token, address(DCA_HUB));
            _maxApprove(_token, address(TRANSFORMER_REGISTRY));
            _maxApprove(_token, address(ROLLUP_PROCESSOR));
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the id of the given token, or zero if it has no id
     * @return The id of the given token, or zero if it has no id
     */
    function getTokenId(address _token) external view returns(uint16) {
        return uint16(tokenRegistry._inner._indexes[bytes32(uint256(uint160(_token)))]);
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy
     * @param _inputAssetA - ETH or ERC20 token to deposit, or a virtual asset if we are talking about a withdraw
     * @param _auxData - The amount of swaps, swap interval and token ids encoded together
     * @return - The criteria
     */
    function computeCriteria(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint64 _auxData
    ) public view override(BridgeBase) returns (uint256) {
        Action _action = _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL ? Action.WITHDRAW : Action.DEPOSIT;
        (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) = _decodeAuxData(_auxData);
        return computeCriteriaForPosition(_action, _from, _to, _amountOfSwaps, _swapInterval);
    }

    /**
     * @notice Computes the criteria for a given position and action
     * @param _action - Whether it's a deposit or a withdraw
     * @param _from - The "from" token
     * @param _to - The "to" token
     * @param _amountOfSwaps - The amount to swaps for the position
     * @param _swapInterval - The positions's swap interval
     * @return - The criteria
     */
    function computeCriteriaForPosition(Action _action, address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_action, _from, _to, _amountOfSwaps, _swapInterval)));
    }    

    /**
     * @notice Creates a position on Mean Finance
     * @param _inputAsset - ETH or the ERC20 token to deposit
     * @param _outputAsset - The virtual asset to return
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @param _auxData - The amount of swaps, swap interval and token ids encoded together
     * @param _outputValueA - The amount of shares generated
     * @param _outputValueB - Always zero
     * @param _depositCriteria - The criteria for the deposit
     */
    function _deposit(
        AztecTypes.AztecAsset calldata _inputAsset,
        AztecTypes.AztecAsset calldata _outputAsset,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData
    ) internal returns (uint256 _outputValueA, uint256 _outputValueB, uint256 _depositCriteria) {
        if (_inputAsset.assetType != AztecTypes.AztecAssetType.ERC20 && _inputAsset.assetType != AztecTypes.AztecAssetType.ETH) {
            // Input asset must be ETH or ERC20
            revert ErrorLib.InvalidInputA();
        } else if (_outputAsset.assetType != AztecTypes.AztecAssetType.VIRTUAL || _outputAsset.id != _interactionNonce) {
            // Output asset must be virtual
            revert ErrorLib.InvalidOutputA();
        }

        // Decode aux data
        (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) = _decodeAuxData(_auxData);

        // Wrap input asset if needed
        uint256 _amountToDeposit = _wrapIfNeeded(_inputAsset, _from, _inputValue);

        // Make the actual deposit
        uint256 _positionId = DCA_HUB.deposit(
            _from,
            _to,
            _amountToDeposit,
            _amountOfSwaps,
            _swapInterval,
            address(this),
            new IDCAHub.PermissionSet[](0)
        );

        // Associate nonce to position
        positionByNonce[_interactionNonce] = PositionData({positionId: _positionId.toUint192(), auxData: _auxData });

        // Compute the criteria for this position
        _depositCriteria = computeCriteriaForPosition(Action.DEPOSIT, _from, _to, _amountOfSwaps, _swapInterval);

        return (VIRTUAL_SHARES_PER_POSITION, 0, _depositCriteria);
    }

    /**
     * @notice A function which will allow the users to close their DCA positions on Mean Finance
     * @dev Positions can only be withdrawn if one of the following is true:
     *      - Position has been fully swapped
     *      - Swaps are paused
     *      - "From" token is no longer supported
     *      - "To" token is no longer supported
     * @param _inputAssetA - The virtual asset that represents the position
     * @param _outputAssetA - ETH or ERC20 token that the position had swapped funds into
     * @param _outputAssetB - ETH or ERC20 token that had been deposited by the user
     * @param _inputValue - Amount of virtual shares to withdraw
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @return _outputValueA - The amount of swapped funds
     * @return _outputValueB - The amount of unswapped funds
     * @return _withdrawCriteria - The criteria for this withdraw
     */
    function _withdraw(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData
    ) internal returns (uint256 _outputValueA, uint256 _outputValueB, uint256 _withdrawCriteria) {
        (
            address _from, 
            address _to, 
            uint256 _unswapped,
            uint256 _swapped,
            uint256 _criteria
        ) = _extractFundsAndReturnData(_inputAssetA.id, _auxData);

        uint256 _toWithdrawUnswapped = Math.mulDiv(_unswapped, _inputValue, VIRTUAL_SHARES_PER_POSITION);
        uint256 _toWithdrawSwapped = Math.mulDiv(_swapped, _inputValue, VIRTUAL_SHARES_PER_POSITION);

        if (_toWithdrawSwapped > 0) {
            _outputValueA = _unwrapIfNeeded(_outputAssetA, _toWithdrawSwapped, _to, _interactionNonce, true);
        }

        if (_toWithdrawUnswapped > 0) {
            _outputValueB = _unwrapIfNeeded(_outputAssetB, _toWithdrawUnswapped, _from, _interactionNonce, false);
        }

        _withdrawCriteria = _criteria;
    }

    /**
     * @notice Extracts the position's funds from the DCA Hub, and returns the position's data
     * @param _depositNonce - The nonce of the position action
     * @param _auxData - The amount of swaps, swap interval and token ids encoded together
     * @return _from - The address of the "from" token
     * @return _to - The address of the "to" token
     * @return _unswapped - The amount of unswapped funds when the position was terminated
     * @return _swapped - The amount of swapped funds when the position was terminated
     * @return _withdrawCriteria - The criteria for this withdraw
     */
    function _extractFundsAndReturnData(uint256 _depositNonce, uint64 _auxData) internal returns (
        address _from, 
        address _to, 
        uint256 _unswapped,
        uint256 _swapped,
        uint256 _withdrawCriteria
    ) {
        PositionData memory _data = positionByNonce[_depositNonce];
        if (_data.auxData != _auxData) revert ErrorLib.InvalidAuxData();
        uint32 _amountOfSwaps; 
        uint32 _swapInterval;
        (_from, _to, _amountOfSwaps, _swapInterval) = _decodeAuxData(_auxData);
        (_unswapped, _swapped) = _extractFundsIfNecessary(_data.positionId, _from, _to);
        _withdrawCriteria = computeCriteriaForPosition(
            Action.WITHDRAW, 
            _from,
            _to,
            _amountOfSwaps,
            _swapInterval
        );
    }

    /**
     * @notice Extracts the position's funds from the DCA Hub and stores the amounts that were extracted for a future request
     * @param _positionId - The position's id
     * @param _from - The address of the "from" token
     * @param _to - The address of the "to" token
     * @return _unswappedFunds - The amount of unswapped funds when the position was terminated
     * @return _swappedFunds - The amount of swapped funds when the position was terminated
     */
    function _extractFundsIfNecessary(uint256 _positionId, address _from, address _to) internal returns (uint256 _unswappedFunds, uint256 _swappedFunds) {
        PositionFunds memory _funds = fundsByPositionId[_positionId];
        if (!_funds.wereFundsExtracted) {
            // We haven't terminated the position yet. We'll terminate it and store the amount of funds
            (_unswappedFunds, _swappedFunds) = DCA_HUB.terminate(_positionId, address(this), address(this));

            // If there are still unswapped funds, then we will only allow users to close their DCA position 
            // if one of the following options is met:
            // - Swaps have been paused
            // - One of the tokens is no longer allowed on the platform
            if (_unswappedFunds > 0 && !DCA_HUB.paused() && DCA_HUB.allowedTokens(_from) && DCA_HUB.allowedTokens(_to)) {                
                revert MeanErrorLib.PositionStillOngoing();
            }

            fundsByPositionId[_positionId] = PositionFunds({
                wereFundsExtracted: true, 
                swappedFunds: _swappedFunds.toUint248(),
                unswappedFunds: _unswappedFunds
            });
        } else {
            (_unswappedFunds, _swappedFunds) = (_funds.unswappedFunds, _funds.swappedFunds);
        }
    }

    /**
     * @notice Wraps the input asset, if needed
     * @param _inputAsset - The input asset
     * @param _hubToken - The token that needs to be deposited into Mean Finance
     * @param _amountToWrap - How much to wrap
     */
    function _wrapIfNeeded(AztecTypes.AztecAsset memory _inputAsset, address _hubToken, uint256 _amountToWrap) internal returns (uint256 _wrappedAmount) {
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: _amountToWrap}();            
            _inputAsset.erc20Address = address(WETH);
        } 
        if (_inputAsset.erc20Address != _hubToken) {
            ITransformer.UnderlyingAmount[] memory _underlying = new ITransformer.UnderlyingAmount[](1);
            _underlying[0] = ITransformer.UnderlyingAmount({underlying: _inputAsset.erc20Address, amount: _amountToWrap});
            return TRANSFORMER_REGISTRY.transformToDependent(
                _hubToken,
                _underlying,
                address(this),
                0, // We can't set slippage amount through Aztec, so we set the min to zero. Would be the same as calling `deposit` on a ERC4626
                block.timestamp
            );        
        }
        return _amountToWrap;
    }

    /**
     * Unwraps the position's "to" token into the output asset, if necessary
     * @dev If the output asset is ETH, then it will transferred to the rollup
     * @param _outputAsset - The expected asset
     * @param _amountToUnwrap - How much to unwrap
     * @param _hubToken - The position's "to" token
     * @param _interactionNonce - The nonce
     * @param _isOutputAssetA - If the asset if output A or output B
     */
    function _unwrapIfNeeded(
        AztecTypes.AztecAsset memory _outputAsset, 
        uint256 _amountToUnwrap, 
        address _hubToken, 
        uint256 _interactionNonce,
        bool _isOutputAssetA
    ) internal returns (uint256 _unwrappedAmount) {
        if (_outputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            _outputAsset.erc20Address = address(WETH);
        }

        if (_outputAsset.erc20Address != _hubToken) {
            ITransformer.UnderlyingAmount[] memory _underlying = TRANSFORMER_REGISTRY.transformToUnderlying(
                _hubToken, 
                _amountToUnwrap, 
                address(this),
                new ITransformer.UnderlyingAmount[](1), // We can't set slippage amount through Aztec, so we set the min to zero. Would be the same as calling `redeem` on a ERC4626
                block.timestamp
            );        
            if (_outputAsset.erc20Address != _underlying[0].underlying) {
                if (_isOutputAssetA) {
                    revert ErrorLib.InvalidOutputA();
                } else {
                    revert ErrorLib.InvalidOutputB();
                }
            }
            _unwrappedAmount = _underlying[0].amount;
        } else {
            _unwrappedAmount = _amountToUnwrap;
        }

        if (_outputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.withdraw(_unwrappedAmount);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: _unwrappedAmount}(_interactionNonce);
        }        
    }

    /**
     * @notice Executed a max approve for the given target
     * @param _token - The token to approve
     * @param _target - The spender
     */
    function _maxApprove(address _token, address _target) internal {
        // Using safeApprove(...) instead of approve(...) and first setting the allowance to 0 because underlying
        // can be Tether
        IERC20(_token).safeApprove(_target, 0);
        IERC20(_token).safeApprove(_target, type(uint256).max);
    }

    /**
     * @notice Decodes the given aux data into the position's data
     */
    function _decodeAuxData(uint64 _auxData) internal view returns (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) {
        _from = _getTokenFromAuxData(_auxData, 32);
        _to = _getTokenFromAuxData( _auxData, 48);
        _amountOfSwaps = uint24(_auxData);
        _swapInterval = MeanSwapIntervalDecodingLib.calculateSwapInterval(uint8(_auxData >> 24));
    }

    /**
     * @notice Calculates the DCAHub's token based on the given aux data
     */
    function _getTokenFromAuxData(uint64 _auxData, uint256 _shift) internal view returns(address _address) {
        uint256 _tokenId = uint16(_auxData >> _shift);
        return tokenRegistry.at(_tokenId - 1);
    }    

}
