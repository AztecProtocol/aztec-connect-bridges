// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract BaseDeployment is Test {
    using stdJson for string;
    /**
     * @notice Enum used as part of the configuration, defines what network and addresses to use.
     */

    enum Network {
        INVALID,
        MAINNET,
        TESTNET,
        DEVNET,
        DONT_CARE
    }

    /**
     * @notice Enum used as part of the configuration, defines how to send transactions.
     */
    enum Mode {
        INVALID,
        SIMULATE_ADMIN,
        BROADCAST
    }

    address private constant MAINNET_MS = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    address private constant DEVNET_MS = 0x7095057A08879e09DC1c0a85520e3160A0F67C96;
    address private constant TESTNET_MS = 0x7095057A08879e09DC1c0a85520e3160A0F67C96;

    /* solhint-disable var-name-mixedcase */

    Network private NETWORK;
    Mode private MODE;
    address internal ROLLUP_PROCESSOR;
    address internal LISTER;

    function setRollupProcessor(address _rollupProcessor) public {
        ROLLUP_PROCESSOR = _rollupProcessor;
    }

    function setLister(address _lister) public {
        LISTER = _lister;
    }

    /* solhint-enable var-name-mixedcase */

    function setUp() public virtual {
        // Read from the .env
        string memory networkKey = "network";

        string memory envNetwork = vm.envString(networkKey);
        bytes32 envNetworkHash = keccak256(abi.encodePacked(envNetwork));

        if (envNetworkHash == keccak256(abi.encodePacked("mainnet"))) {
            NETWORK = Network.MAINNET;
        } else if (envNetworkHash == keccak256(abi.encodePacked("devnet"))) {
            NETWORK = Network.DEVNET;
        } else if (envNetworkHash == keccak256(abi.encodePacked("testnet"))) {
            NETWORK = Network.TESTNET;
        } else {
            NETWORK = Network.DONT_CARE;
            MODE = Mode.BROADCAST;
            require(ROLLUP_PROCESSOR != address(0), "RollupProcessor address resolved to 0");
            require(LISTER != address(0), "Lister address resolved to 0");
            emit log_named_address("Rollup at", ROLLUP_PROCESSOR);
            emit log_named_address("Lister at", LISTER);
            return;
        }

        string memory modeKey = "simulateAdmin";
        bool envMode = vm.envBool(modeKey);
        MODE = envMode ? Mode.SIMULATE_ADMIN : Mode.BROADCAST;

        if (MODE == Mode.BROADCAST) {
            emit log_named_string("broadcasting", envNetwork);
        } else {
            emit log_named_string("simulating", envNetwork);
        }

        (ROLLUP_PROCESSOR, LISTER) = getRollupProcessorAndLister();
        /* solhint-disable custom-error-over-require */
        require(ROLLUP_PROCESSOR != address(0), "RollupProcessor address resolved to 0");
        require(LISTER != address(0), "Lister address resolved to 0");
        emit log_named_address("Rollup at", ROLLUP_PROCESSOR);
        emit log_named_address("Lister at", LISTER);
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
            return (getTestnetRollupProcessor(), TESTNET_MS);
        } else if (chainId == 3567 && NETWORK == Network.DEVNET) {
            return (getDevnetRollupProcessor(), DEVNET_MS);
        } else {
            revert("Invalid configuration");
        }
    }

    /**
     * @notice Fetches the testnet rollup processor from the status endpoint
     * @return The address of the rollup processor
     */
    function getTestnetRollupProcessor() public returns (address) {
        return _fetchFromStatus("https://api.aztec.network/aztec-connect-testnet/falafel/status");
    }

    /**
     * @notice Fetches the devnet rollup processor from the status endpoint
     * @return The address of the rollup processor
     */
    function getDevnetRollupProcessor() public returns (address) {
        return _fetchFromStatus("https://api.aztec.network/aztec-connect-dev/falafel/status");
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
     * @dev If MODE == Mode.SIMULATE_ADMIN it impersonates the lister, otherwise broadcasts
     * @param _bridge The address of the bridge
     * @param _gasLimit The gasLimit to list the bridge with
     * @return The bridgeAddressId for the bridge
     */
    function listBridge(address _bridge, uint256 _gasLimit) public returns (uint256) {
        if (MODE == Mode.SIMULATE_ADMIN) {
            vm.prank(LISTER);
        } else {
            vm.broadcast();
        }
        IRollupProcessor(ROLLUP_PROCESSOR).setSupportedBridge(_bridge, _gasLimit);
        return bridgesLength();
    }

    /**
     * @notice Helper to list an `_asset` on the rollup with the given `_gasLimit`
     * @dev Only lists the asset if not listed already
     * @dev If MODE == Mode.SIMULATE_ADMIN it impersonates the lister, otherwise broadcasts
     * @param _asset The address of the bridge
     * @param _gasLimit The gasLimit to list the bridge with
     * @return The assetId
     */
    function listAsset(address _asset, uint256 _gasLimit) public returns (uint256) {
        (bool supported, uint256 id) = _isSupportedAsset(_asset);
        if (supported) {
            emit log_named_uint("Asset already listed with id", id);
            return id;
        } else {
            if (MODE == Mode.SIMULATE_ADMIN) {
                vm.prank(LISTER);
            } else {
                vm.broadcast();
            }
            IRollupProcessor(ROLLUP_PROCESSOR).setSupportedAsset(_asset, _gasLimit);
            emit log_named_address("LISTED", _asset);
            emit log_named_uint("With id", assetLength());
            return assetLength();
        }
    }

    /**
     * @notice Get the number of bridges on the given rollup
     * @return The number of bridges
     */
    function bridgesLength() public view returns (uint256) {
        return IRollupProcessor(ROLLUP_PROCESSOR).getSupportedBridgesLength();
    }

    function assetLength() public view returns (uint256) {
        return IRollupProcessor(ROLLUP_PROCESSOR).getSupportedAssetsLength();
    }

    function _fetchFromStatus(string memory _url) private returns (address) {
        string[] memory inputs = new string[](3);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = _url;
        bytes memory res = vm.ffi(inputs);
        string memory json = string(res);
        return json.readAddress(".blockchainStatus.rollupContractAddress");
    }

    /**
     * @notice Fetch whether an `_asset` is supported or not on the rollup
     */
    function _isSupportedAsset(address _asset) private view returns (bool, uint256) {
        if (_asset == address(0)) {
            return (true, 0);
        }
        uint256 length = IRollupProcessor(ROLLUP_PROCESSOR).getSupportedAssetsLength();
        for (uint256 i = 1; i <= length; i++) {
            address fetched = IRollupProcessor(ROLLUP_PROCESSOR).getSupportedAsset(i);
            if (fetched == _asset) {
                return (true, i);
            }
        }
        return (false, 0);
    }
}
