// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "./../../bridges/example/ExampleBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";


import "../../../lib/ds-test/src/test.sol";


contract ExampleTest is DSTest {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    ExampleBridgeContract exampleBridge;

    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);


    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        exampleBridge = new ExampleBridgeContract(
            address(rollupProcessor)
        );

        _setTokenBalance(address(dai), address(0xdead), 42069);
    }


    function testExampleBridge() public {
       uint256 depositAmount = 15000;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount);


        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(exampleBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                0
            );

        uint256 rollupDai = dai.balanceOf(address(rollupProcessor));

        assertEq(
            depositAmount,
            rollupDai,
            "Balances must match"
        );

    }


    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }


    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 2; // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }



}
