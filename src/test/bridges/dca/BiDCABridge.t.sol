// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {BiDCABridge} from "../../../bridges/dca/BiDCABridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/**
 * @notice ERC20 token implementation that allow the owner to mint tokens and let anyone burn their own tokens
 * or token they have allowance to.
 * @dev The owner is immutable and therefore cannot be updated
 * @author Lasse Herskind
 */
contract Testtoken is ERC20 {
    error InvalidCaller();

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {}

    /**
     * @notice Mint tokens to address
     * @dev Only callable by the owner
     * @param _to The receiver of tokens
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract BiDCATest is Test {
    BiDCABridge internal bridge;
    IERC20 internal assetA;
    IERC20 internal assetB;

    //IERC20 public constant assetA = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    //IERC20 public constant assetB = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        Testtoken a = new Testtoken("TokenA", "A", 18);
        Testtoken b = new Testtoken("TokenB", "B", 18);

        bridge = new BiDCABridge(address(this), address(a), address(b), 1 days);

        assetA = IERC20(address(a));
        assetB = IERC20(address(b));
    }

    function testSmallFlow() public {
        emit log("START");
        bridge.pokeNextTicks(30);

        bridge.deposit(0, 300 ether, 7, true);
        vm.warp(block.timestamp + 1 days);
        bridge.deposit(1, 700 ether, 7, true);
        bridge.deposit(2, 1400 ether, 14, false);

        printAvailable();

        vm.warp(block.timestamp + 5 days);
        printAvailable();

        uint256 start = bridge.lastTickAvailableA();

        emit log("---");
        for (uint256 i = start; i < start + 3; i++) {
            printTick(i);
        }

        emit log("--- Available");
        printAvailable();
        printDCA(0);

        emit log("--- Rebalance");
        emit log_named_decimal_uint("Price", bridge.getPrice(), 18);
        bridge.rebalanceAndfill(0, 0);

        for (uint256 i = start; i < start + 3; i++) {
            printTick(i);
        }

        emit log("--- Available");
        printAvailable();
        printDCA(0);

        /*

        {
            (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(5 ether);

            emit log_named_decimal_uint("bought", bought, 18);
            emit log_named_decimal_uint("sold", sold, 18);
            emit log_named_decimal_uint("refund", refund, 18);

            for (uint256 i = start; i < start + 8; i++) {
                printTick(i);
            }
        }
        emit log("---");
        {
            (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(5 ether);

            emit log_named_decimal_uint("bought", bought, 18);
            emit log_named_decimal_uint("sold", sold, 18);
            emit log_named_decimal_uint("refund", refund, 18);

            for (uint256 i = start; i < start + 8; i++) {
                printTick(i);
            }
        }
        for (uint256 i = 0; i < 3; i++) {
            (uint256 accumulated, bool ready) = bridge.getAccumulated(i);
            emit log_named_decimal_uint("accumulated", accumulated, 18);
            if (ready) {
                emit log("Ready for harvest");
            } else {
                emit log("Not ready");
            }
        }
        emit log("---");
        vm.warp(block.timestamp + 10 days);
        (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(30 ether);

        for (uint256 i = 0; i < 3; i++) {
            (uint256 accumulated, bool ready) = bridge.getAccumulated(i);
            emit log_named_decimal_uint("accumulated", accumulated, 18);
            if (ready) {
                emit log("Ready for harvest");
            } else {
                emit log("Not ready");
            }
        }*/
    }

    function printDCA(uint256 _nonce) public returns (BiDCABridge.DCA memory) {
        (uint256 accumulated, bool ready) = bridge.getAccumulated(_nonce);
        BiDCABridge.DCA memory dca = bridge.getDCA(_nonce);
        emit log_named_uint("DCA at nonce", _nonce);
        emit log_named_decimal_uint("Total ", dca.total, 18);
        emit log_named_uint("start ", dca.start);
        emit log_named_uint("end   ", dca.end);
        if (dca.assetA) {
            emit log_named_decimal_uint("accumB", accumulated, 18);
        } else {
            emit log_named_decimal_uint("accumA", accumulated, 18);
        }
        if (ready) {
            emit log("Ready for harvest");
        }
    }

    function printAvailable() public {
        (uint256 a, uint256 b) = bridge.available();
        emit log_named_decimal_uint("Available A", a, 18);
        emit log_named_decimal_uint("Available B", b, 18);
    }

    function printTick(uint256 _tick) public returns (BiDCABridge.Tick memory) {
        BiDCABridge.Tick memory tick = bridge.getTick(_tick);

        emit log_named_uint("Tick number", _tick);
        emit log_named_decimal_uint("availableA", tick.availableA, 18);
        emit log_named_decimal_uint("availableB", tick.availableB, 18);
        emit log_named_decimal_uint("price aToB", tick.priceAToB, 18);

        emit log_named_decimal_uint("A sold    ", tick.assetA.sold, 18);
        emit log_named_decimal_uint("A bought  ", tick.assetA.bought, 18);

        emit log_named_decimal_uint("B sold    ", tick.assetB.sold, 18);
        emit log_named_decimal_uint("B bought  ", tick.assetB.bought, 18);

        return tick;
    }
}
