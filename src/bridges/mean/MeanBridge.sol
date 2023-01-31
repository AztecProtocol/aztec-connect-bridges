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
    address private immutable THIS_ADDRESS;
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
            //       We check that the addresses are wrappers when we use them, and we have enough slots to 
            //       add non-wrapper tokens. So we just don't check it here and save gas
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
     * @notice Returns whether one wrapper 
     * @return All registered wrappers
     */
    function isWrapperSupported(address _wrapper) external view returns(bool) {
        return tokenWrapperRegistry.contains(_wrapper);
    }

    function _maxApprove(IERC20 _token, address _target) internal {
        // Using safeApprove(...) instead of approve(...) and first setting the allowance to 0 because underlying
        // can be Tether
        IERC20(_token).safeApprove(_target, 0);
        IERC20(_token).safeApprove(_target, type(uint256).max);
    }

}
