// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ElementBridge} from "./../../bridges/element/ElementBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";

import "../../../lib/ds-test/src/test.sol";

contract ElementTest is DSTest {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    ElementBridge elementBridge;

    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 byteCodeHash = 0xf481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d;
    address trancheFactoryAddress = 0x62F161BF3692E4015BefB05A03a94A40f520d1c0;


    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        elementBridge = new ElementBridge(
            address(rollupProcessor),
            trancheFactoryAddress,
            byteCodeHash,
            balancer
        );

        _setTokenBalance(address(dai), address(0xdead), 42069);
    }




    function testElementBridge() public {
       uint256 depositAmount = 15000;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount);

        elementBridge
        .registerConvergentPoolAddress(
          0xEdf085f65b4F6c155e13155502Ef925c9a756003,
          0x21BbC083362022aB8D7e42C18c47D484cc95C193,
          1651275535
        );

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

        uint256 balancerBefore = dai.balanceOf(address(balancer));


        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(elementBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                1651275535
            );

        uint256 balancerAfter = dai.balanceOf(address(balancer));

        assertEq(
            balancerBefore + depositAmount,
            balancerAfter,
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
