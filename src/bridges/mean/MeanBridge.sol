// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using EnumerableSet for EnumerableSet.AddressSet;

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IDCAHub public immutable DCA_HUB;
    ITransformerRegistry public immutable TRANSFORMER_REGISTRY;
    mapping(uint256 => uint256) public positionByNonce;
    address private immutable THIS_ADDRESS;

    // Note: Mean supports yield-while-DCAing and we want to support it here too. The thing
    // is that a specific token (for example DAI) can have multiple source platforms. Each platform
    // is supported by a ERC4626 wrapper. Since we can't pass the wrapper's address, we have created a
    // a wrapper registry. This will allow us to assign a unique id to each address, and we can pass 
    // said id as part of the aux data
    EnumerableSet.AddressSet internal tokenWrapperRegistry;

    event NewWrappersSupported(address[] wrappers);

    /**
     * @notice Sets address of rollup processor and Subsidy-related info
     * @param _hub The address of the DCA Hub
     * @param _owner The account that will own the bridge
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(IDCAHub _hub, ITransformerRegistry _transformerRegistry, address _owner, address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _transferOwnership(_owner);
        DCA_HUB = _hub;
        TRANSFORMER_REGISTRY = _transformerRegistry;
        THIS_ADDRESS = address(this);
    }

    // Note: we need to be able to receive ETH to deposit as WETH
    receive() external payable {}

    /**
     * @notice A function which will allow the user to create DCA positions on Mean Finance
     * @param _inputAssetA - ETH or ERC20 token to deposit and start swapping
     * @param _outputAssetA - ETH or ERC20 token to swap funds into
     * @param _outputAssetB - Same as input asset A
     * @param _inputValue - Amount to deposit
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @param _auxData - The amount of swaps, swap interval and wrappers encoded together
     * @param _rollupBeneficiary - Address which receives subsidy if the call is eligible for it
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address _rollupBeneficiary
    ) external payable override(BridgeBase) onlyRollup returns (uint256, uint256, bool) {
        if (_inputAssetA.assetType != _outputAssetB.assetType || _inputAssetA.erc20Address != _outputAssetB.erc20Address) {
            // We are making sure that input asset A = output asset B. We do this so that, if we need to, we can close the 
            // position while it's still being swapped
            revert ErrorLib.InvalidOutputB();
        }

        // Wrap the input asset (if needed) and deposit into the DCA Hub
        (uint256 _positionId, uint256 _criteria) = _wrapAndDeposit(_inputAssetA, _outputAssetA, _inputValue, _auxData);

        // Associate nonce to position
        positionByNonce[_interactionNonce] = _positionId;

        // Accumulate subsidy to _rollupBeneficiary
        SUBSIDY.claimSubsidy(_criteria, _rollupBeneficiary);
        
        return (0, 0, true);
    }

    /**
     * @notice A function which will allow the users to close their DCA positions on Mean Finance
     * @param _outputAssetA - ETH or ERC20 token that the position had swapped funds into
     * @param _outputAssetB - ETH or ERC20 token that had been deposited by the user
     * @param _interactionNonce - Unique identifier for this DeFi interaction
     * @return _outputValueA - The amount of swapped funds
     * @return _outputValueB - The amount of unswapped funds
     * @return _interactionComplete - This will always be true
     */
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _interactionNonce,
        uint64
    )
        external
        payable
        virtual
        override(BridgeBase)
        onlyRollup
        returns (uint256 _outputValueA, uint256 _outputValueB, bool _interactionComplete)
    {
        // Get position from nonce
        uint256 _positionId = positionByNonce[_interactionNonce];
        IDCAHub.UserPosition memory _position = DCA_HUB.userPosition(_positionId);

        // Terminate position and clean things up
        delete positionByNonce[_interactionNonce];
        (uint256 _unswapped, uint256 _swapped) = DCA_HUB.terminate(_positionId, THIS_ADDRESS, THIS_ADDRESS);

        if (_unswapped > 0) {
            if (!DCA_HUB.paused()) {
                // If there are still unswapped funds, then we will only allow closing the DCA position
                // if swaps have been paused
                revert MeanErrorLib.PositionStillOngoing();
            }

            _unwrapIfNeeded(_outputAssetB, _unswapped, _position.from, _interactionNonce, false);
        }

        _unwrapIfNeeded(_outputAssetA, _swapped, _position.to, _interactionNonce, true);
        
        return (_swapped, _unswapped, true);
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
     * @notice Registers wrappers internally, so that they can be referenced by an index instead of the full address
     * @dev Anyone can call this method, it's not permissioned
     * @param _wrappers The wrappers to register
     */
    function registerWrappers(address[] calldata _wrappers) external {
        for (uint i; i < _wrappers.length; ) {
            address _wrapper = _wrappers[i];
            if (!DCA_HUB.allowedTokens(_wrapper)) {
                revert MeanErrorLib.TokenNotAllowed(_wrapper);
            } 
            // Note: we could check that the address is indeed a wrapper, but we don't think it's necessary
            // We check that the addresses are wrappers when we use them, and we have enough slots to add 
            // non-wrapper tokens. So we just don't check it here and save gas
            // Also, we know that we can only support 2**16 tokens on the registry, but we are not checking that
            // here. We won't ever support that many tokens on our contract
            bool _added = tokenWrapperRegistry.add(_wrapper);
            if (!_added) {
                revert MeanErrorLib.TokenAlreadyRegistered(_wrapper);
            }

            _maxApprove(IERC20(_wrapper), address(DCA_HUB));
            _maxApprove(IERC20(_wrapper), address(TRANSFORMER_REGISTRY));

            unchecked{
                ++i;
            }
        }
        emit NewWrappersSupported(_wrappers);
    }    

    /**
     * @notice Set all the necessary approvals for the DCA hub, the transformer registry and the rollup processor
     * @param _tokens - The tokens to approve
     */
    function maxApprove(IERC20[] calldata _tokens) external {
        for (uint i; i < _tokens.length; ) {
            IERC20 _token = _tokens[i];
            _maxApprove(_token, address(DCA_HUB));
            _maxApprove(_token, address(TRANSFORMER_REGISTRY));
            _maxApprove(_token, address(ROLLUP_PROCESSOR));
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the id of the given wrapper, or zero if it has no id
     * @return The id of the given wrapper, or zero if it has no id
     */
    function getWrapperId(address _wrapper) external view returns(uint16) {
        return uint16(tokenWrapperRegistry._inner._indexes[bytes32(uint256(uint160(_wrapper)))]);
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy
     * @param _inputAssetA - ETH or ERC20 token to deposit and start swapping
     * @param _outputAssetA - ETH or ERC20 token to swap funds into
     * @param _auxData - The amount of swaps, swap interval and wrappers encoded together
     * @return The criteria
     */
    function computeCriteria(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint64 _auxData
    ) public view override(BridgeBase) returns (uint256) {
        (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) = _mapToPositionData(_inputAssetA, _outputAssetA, _auxData);
        return computeCriteriaForPosition(_from, _to, _amountOfSwaps, _swapInterval);
    }

    /**
     * @notice Computes the criteria that for a given position
     * @param _from - The "from" token
     * @param _to - The "to" token
     * @param _amountOfSwaps - The amount to swaps for the position
     * @param _swapInterval - The positions's swap interval
     * @return The criteria
     */
    function computeCriteriaForPosition(address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_from, _to, _amountOfSwaps, _swapInterval)));
    }

    function _wrapAndDeposit(
        AztecTypes.AztecAsset memory _inputAssetA, 
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _inputValue,
        uint64 _auxData
    ) internal returns(uint256 _positionId, uint256 _criteria) {
        // Calculate input params
        (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) = _mapToPositionData(_inputAssetA, _outputAssetA, _auxData);

        // Wrap input asset if needed
        uint256 _amountToDeposit = _wrapIfNeeded(_inputAssetA, _from, _inputValue);

        // Make the actual deposit
        _positionId = DCA_HUB.deposit(
            _from,
            _to,
            _amountToDeposit,
            _amountOfSwaps,
            _swapInterval,
            THIS_ADDRESS,
            new IDCAHub.PermissionSet[](0)
        );

        // Compute the criteria for this position
        _criteria = computeCriteriaForPosition(_from, _to, _amountOfSwaps, _swapInterval);
    }

    function _wrapIfNeeded(AztecTypes.AztecAsset memory _inputAsset, address _hubToken, uint256 _amountToWrap) internal returns (uint256 _wrappedAmount) {
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: _amountToWrap}();            
        } else if (_inputAsset.erc20Address != _hubToken) {
            ITransformer.UnderlyingAmount[] memory _underlying = new ITransformer.UnderlyingAmount[](1);
            _underlying[0] = ITransformer.UnderlyingAmount({underlying: _inputAsset.erc20Address, amount: _amountToWrap});
            return TRANSFORMER_REGISTRY.transformToDependent(
                _hubToken,
                _underlying,
                THIS_ADDRESS,
                0, // We can't set slippage amount through Aztec, so we set the min to zero. Would be the same as calling `deposit` on a ERC4626
                block.timestamp
            );        
        }
        return _amountToWrap;
    }

    function _unwrapIfNeeded(
        AztecTypes.AztecAsset memory _outputAsset, 
        uint256 _amountToUnwrap, 
        address _hubToken, 
        uint256 _interactionNonce,
        bool _isOutputAssetA
    ) internal returns (uint256 _unwrappedAmount) {
        if (_outputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.withdraw(_amountToUnwrap);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: _amountToUnwrap}(_interactionNonce);
        } else if (_outputAsset.erc20Address != _hubToken) {
            ITransformer.UnderlyingAmount[] memory _underlying = TRANSFORMER_REGISTRY.transformToUnderlying(
                _hubToken, 
                _amountToUnwrap, 
                THIS_ADDRESS,
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
            return _underlying[0].amount;
        }
        return _amountToUnwrap;
    }

    function _maxApprove(IERC20 _token, address _target) internal {
        // Using safeApprove(...) instead of approve(...) and first setting the allowance to 0 because underlying
        // can be Tether
        IERC20(_token).safeApprove(_target, 0);
        IERC20(_token).safeApprove(_target, type(uint256).max);
    }

    function _mapToPositionData(
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset,
        uint64 _auxData
    ) internal view returns (address _from, address _to, uint32 _amountOfSwaps, uint32 _swapInterval) {
        _amountOfSwaps = uint24(_auxData);
        _swapInterval = MeanSwapIntervalDecodingLib.calculateSwapInterval(uint8(_auxData >> 24));
        _from = _mapAssetToAddress(_inputAsset, _auxData, 32);
        _to = _mapAssetToAddress(_outputAsset, _auxData, 48);
    }

    function _mapAssetToAddress(AztecTypes.AztecAsset memory _asset, uint64 _auxData, uint256 _shift) internal view returns(address _address) {
        if (_asset.assetType == AztecTypes.AztecAssetType.ETH) {
            return address(WETH);
        } else {
            uint256 _wrapperId = uint16(_auxData >> _shift);
            return _wrapperId == 0 
                ? _asset.erc20Address
                : tokenWrapperRegistry.at(_wrapperId - 1);
        }
    }    

}
