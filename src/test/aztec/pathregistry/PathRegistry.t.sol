// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PathRegistry} from "../../../aztec/PathRegistry.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";
import {TestPaths} from "./TestPaths.sol";

contract PathRegistryTest is Test, TestPaths {
    PathRegistry private pathRegistry;

    function setUp() public {
        pathRegistry = new PathRegistry();
    }

    function testRegisterPathWith0Amount() public {
        // Test the "if" execution path
        try pathRegistry.registerPath(getPath1(0)) {
            assertTrue(false, "registerPath(..) has to revert when initializing a path with zero amount.");
        } catch Error(string memory reason) {
            assertEq(reason, "AS");
        }

        // Test the "else if" execution path
        pathRegistry.registerPath(getPath1(1e18));
        try pathRegistry.registerPath(getPath1(0)) {
            assertTrue(false, "registerPath(..) has to revert when initializing a path with zero amount.");
        } catch Error(string memory reason) {
            assertEq(reason, "AS");
        }

        // "else" execution path can't be reached with a path with 0 amount
    }

    function testRegisterPath() public {
        // 1ST PATH REGISTRATION
        pathRegistry.registerPath(getPath1(3e17));

        // Test whether firstPathIndex was correctly set to 1
        uint256 firstPathIndex = pathRegistry.firstPathIndices(WETH, LUSD);
        assertEq(firstPathIndex, 1);

        (uint256 amount1, uint256 next1) = pathRegistry.allPaths(1);
        assertEq(amount1, 3e17);
        assertEq(next1, 0);

        // 2ND PATH REGISTRATION - should be inserted at the end
        // Index order should be 1, 2
        pathRegistry.registerPath(getPath3(32e19));

        // First path index should stay the same
        firstPathIndex = pathRegistry.firstPathIndices(WETH, LUSD);
        assertEq(firstPathIndex, 1);

        (amount1, next1) = pathRegistry.allPaths(1);
        assertEq(amount1, 3e17);
        assertEq(next1, 3);

        (uint256 amount2, uint256 next2) = pathRegistry.allPaths(2);
        assertEq(amount2, 32e19);
        assertEq(next2, 0);

        // 3RD PATH REGISTRATION - should be inserted before the last one
        // Index order should be 1, 3, 2
        pathRegistry.registerPath(getPath2(4e19));

        // First path index should stay the same
        firstPathIndex = pathRegistry.firstPathIndices(WETH, LUSD);
        assertEq(firstPathIndex, 1);

        (amount1, next1) = pathRegistry.allPaths(1);
        assertEq(amount1, 3e17);
        assertEq(next1, 3);

        (amount2, next2) = pathRegistry.allPaths(2);
        assertEq(amount2, 32e19);
        assertEq(next2, 0);

        (uint256 amount3, uint256 next3) = pathRegistry.allPaths(3);
        assertEq(amount3, 4e19);
        assertEq(next3, 2);
    }

    /**
     * @notice A test testing whether a path gets replaced by a new one (instead of inserting the new one before
     * the original one). This should happen when the new path is better at both newPath.amount and oldPath.amount
     */
    function testFirstPathReplacement() public {
        pathRegistry.registerPath(getPath3(1e17));
        pathRegistry.registerPath(getPath1(1e16));

        (uint256 amount1, uint256 next1) = pathRegistry.allPaths(1);
        assertEq(amount1, 1e16);
        assertEq(next1, 0);
    }

    function testFailRegisterBrokenPathUniV3() public {
        pathRegistry.registerPath(getPath1(0));
        pathRegistry.registerPath(getBrokenPathUniV3(1e18));
    }

    function testEthPoolHasToExist() public {
        try pathRegistry.registerPath(getPathNoEthPool(1e17)) {
            assertTrue(false, "registerPath(..) has to revert when ETH pool doesn't exist.");
        } catch (bytes memory reason) {
            // Verify that the selector encoded in reason corresponds to NonExistentEthPool
            assertEq(PathRegistry.NonExistentEthPool.selector, bytes4(reason));
        }
    }

    function testPathPruning() public {
        // TODO
    }

    function testSwapFuzz(uint96 amountIn) public {
        pathRegistry.registerPath(getPath1(3e17));
        pathRegistry.registerPath(getPath2(4e19));
        pathRegistry.registerPath(getPath3(32e19));

        // give amountIn WEI to address(1337) and call the next function with msg.origin = address(1337)
        hoax(address(1337), amountIn);

        if (amountIn == 0) {
            try pathRegistry.swap{value: amountIn}(WETH, LUSD, amountIn, 0) {
                assertTrue(false, "swap(..) should revert with amountIn = 0.");
            } catch Error(string memory reason) {
                assertEq(reason, "INSUFFICIENT_INPUT_AMOUNT");
            }
        } else {
            pathRegistry.swap{value: amountIn}(WETH, LUSD, amountIn, 0);
        }
    }

    function testSwapERC20() public {
        pathRegistry.registerPath(getPath1(3e17));
        pathRegistry.registerPath(getPath4(1e22));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e18;

        startHoax(address(1337), amountIn);
        IWETH(WETH).deposit{value: amountIn}();
        IERC20(WETH).approve(address(pathRegistry), amountIn);

        pathRegistry.swap(WETH, LUSD, amountIn, 0);
        assertGt(IERC20(LUSD).balanceOf(address(1337)), 0);
    }

    function testSwapOnlyPathWithLargerAmountAvailable() public {
        pathRegistry.registerPath(getPath4(1e22));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e18;

        hoax(address(1337), amountIn);
        pathRegistry.swap{value: amountIn}(WETH, LUSD, amountIn, 0);
        assertGt(IERC20(LUSD).balanceOf(address(1337)), 0);
    }

    function testSwapMinAmountEnforced() public {
        pathRegistry.registerPath(getPath1(3e17));
        pathRegistry.registerPath(getPath4(1e22));

        // give 1 ETH to address(1337) and call the next function with msg.origin = address(1337)
        uint256 amountIn = 1e18;

        startHoax(address(1337), amountIn);
        IWETH(WETH).deposit{value: amountIn}();
        IERC20(WETH).approve(address(pathRegistry), amountIn);

        try pathRegistry.swap(WETH, LUSD, amountIn, type(uint256).max) {
            assertTrue(false, "swap(..) should revert when amountOut <  amountIn.");
        } catch (bytes memory reason) {
            // Verify that the selector encoded in reason corresponds to InsufficientAmountOut
            assertEq(PathRegistry.InsufficientAmountOut.selector, bytes4(reason));
        }
    }

    function testQuote() public {
        pathRegistry.registerPath(getPath4(3e17));

        uint256 quotedAmount = pathRegistry.quote(WETH, LUSD, 1e18);
        assertGt(quotedAmount, 0);
    }
}
