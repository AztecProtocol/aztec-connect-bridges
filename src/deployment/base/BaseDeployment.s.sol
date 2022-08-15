// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {Test} from "forge-std/Test.sol";

abstract contract BaseDeployment is Test {
    /**
     * @notice Enum used as part of the configuration, defines what network and addresses to use.
     */
    enum Network {
        INVALID,
        MAINNET,
        TESTNET,
        DEVNET
    }

    /**
     * @notice Enum used as part of the configuration, defines how to send transactions.
     */
    enum Mode {
        INVALID,
        SIMULATE,
        BROADCAST
    }

    address private constant DEVNET_ROLLUP = 0xE33d8C775eCf4a2F6857053068e2E36d1dAdE63F;
    address private constant TESTNET_ROLLUP = 0x4598038EF8E9fE4284EA211521eD3067640F550F;

    address private constant MAINNET_MS = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    address private constant DEVNET_MS = 0x7095057A08879e09DC1c0a85520e3160A0F67C96;
    address private constant TESTNET_MS = 0x7095057A08879e09DC1c0a85520e3160A0F67C96;

    /* solhint-disable var-name-mixedcase */

    Network internal NETWORK;
    Mode internal MODE;
    address internal ROLLUP_PROCESSOR;
    address internal TO_IMPERSONATE;

    /* solhint-enable var-name-mixedcase */

    /**
     * @notice Configures the storage variables based on NETWORK and MODE values.
     * @dev require --ffi to fetch mainnet
     */
    function configure() public {
        (ROLLUP_PROCESSOR, TO_IMPERSONATE) = getRollupProcessorAndLister();
    }

    /**
     * @notice Get the address of the rollup processor and lister
     * @dev require --ffi to fetch mainnet
     * @return The address of the rollup processor (proxy)
     * @return The address of the lister
     */
    function getRollupProcessorAndLister() public returns (address, address) {
        if (NETWORK == Network.INVALID || MODE == Mode.INVALID) {
            revert("Invalid configuration");
        }

        uint256 chainId = getChainId();

        if (chainId == 1 && NETWORK == Network.MAINNET) {
            return (getMainnetRollupProcessor(), MAINNET_MS);
        } else if (chainId == 0xa57ec && NETWORK == Network.TESTNET) {
            return (TESTNET_ROLLUP, TESTNET_MS);
        } else if (chainId == 0xa57ec && NETWORK == Network.DEVNET) {
            return (DEVNET_ROLLUP, DEVNET_MS);
        } else {
            revert("Invalid configuration");
        }
    }

    /**
     * @notice Fetches the mainnet rollup address from the ENS domain `rollup.aztec.eth`
     * @return The address of the rollup processor
     */
    function getMainnetRollupProcessor() public returns (address) {
        string[] memory inputs = new string[](3);
        inputs[0] = "cast";
        inputs[1] = "resolve-name";
        inputs[2] = "rollup.aztec.eth";
        bytes memory res = vm.ffi(inputs);

        address temp;
        //solhint-disable-next-line
        assembly {
            temp := shr(96, mload(add(res, 0x20)))
        }
        return temp;
    }

    /**
     * @notice Helper to fetch the chain id
     * @dev Emits the current chain id
     * @return The chain id of the current chain
     */
    function getChainId() public returns (uint256) {
        emit log_named_uint("Current chain id", block.chainid);
        return block.chainid;
    }

    /**
     * @notice Helper to list a `_bridge` on the rollup with the given `_gasLimit`
     * @dev If MODE == Mode.SIMULATE it impersonates the lister, otherwise broadcasts
     * @param _bridge The address of the bridge
     * @param _gasLimit The gasLimit to list the bridge with
     */
    function listBridge(address _bridge, uint256 _gasLimit) public {
        if (MODE == Mode.SIMULATE) {
            vm.prank(TO_IMPERSONATE);
        } else {
            vm.broadcast();
        }
        IRollupProcessor(ROLLUP_PROCESSOR).setSupportedBridge(_bridge, _gasLimit);
    }

    /**
     * @notice Helper to list an `_asset` on the rollup with the given `_gasLimit`
     * @dev Only lists the asset if not listed already
     * @dev If MODE == Mode.SIMULATE it impersonates the lister, otherwise broadcasts
     * @param _asset The address of the bridge
     * @param _gasLimit The gasLimit to list the bridge with
     */
    function listAsset(address _asset, uint256 _gasLimit) public {
        if (_isSupportedAsset(_asset)) {
            emit log_named_address("Asset already listed", _asset);
        } else {
            if (MODE == Mode.SIMULATE) {
                vm.prank(TO_IMPERSONATE);
            } else {
                vm.broadcast();
            }
            IRollupProcessor(ROLLUP_PROCESSOR).setSupportedAsset(_asset, _gasLimit);
            emit log_named_address("LISTED", _asset);
        }
    }

    /**
     * @notice Get the number of bridges on the given rollup
     * @return The number of bridges
     */
    function bridgesLength() public view returns (uint256) {
        return IRollupProcessor(ROLLUP_PROCESSOR).getSupportedBridgesLength();
    }

    /**
     * @notice Fetch whether an `_asset` is supported or not on the rollup
     */
    function _isSupportedAsset(address _asset) private view returns (bool) {
        if (_asset == address(0)) {
            return true;
        }
        uint256 length = IRollupProcessor(ROLLUP_PROCESSOR).getSupportedAssetsLength();
        for (uint256 i = 1; i <= length; i++) {
            address fetched = IRollupProcessor(ROLLUP_PROCESSOR).getSupportedAsset(i);
            if (fetched == _asset) {
                return true;
            }
        }
        return false;
    }
}
