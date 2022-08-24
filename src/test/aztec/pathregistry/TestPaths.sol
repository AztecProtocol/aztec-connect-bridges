// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IPathRegistry} from "../../../aztec/interfaces/IPathRegistry.sol";

contract TestPaths {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    address private constant RANDOM_ADDRESS = 0xd2f4F51e80E2e857E32Dd8e7e2fcB30e498F71F0;

    function getPath1() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        // Optimal ETH -> LUSD path for amounts in <0, 40> ETH range
        subPaths = new IPathRegistry.SubPath[](1);

        subPaths[0] = IPathRegistry.SubPath({
            percent: 100,
            path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), LUSD)
        });
    }

    function getPath2() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        // Optimal ETH -> LUSD path for amounts in <40, 320> ETH range
        subPaths = new IPathRegistry.SubPath[](1);

        subPaths[0] = IPathRegistry.SubPath({
            percent: 100,
            path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), FRAX, uint24(500), LUSD)
        });
    }

    function getPath3() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        // Optimal ETH -> LUSD path for amounts in <320, 900> ETH range
        subPaths = new IPathRegistry.SubPath[](2);

        subPaths[0] = IPathRegistry.SubPath({
            percent: 65,
            path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), FRAX, uint24(500), LUSD)
        });

        subPaths[1] = IPathRegistry.SubPath({
            percent: 35,
            path: abi.encodePacked(WETH, uint24(3000), USDC, uint24(100), DAI, uint24(500), LUSD)
        });
    }

    function getPath4() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        // Optimal ETH -> LUSD path for amounts in <900, 2000> ETH range
        subPaths = new IPathRegistry.SubPath[](3);

        subPaths[0] = IPathRegistry.SubPath({
            percent: 55,
            path: abi.encodePacked(WETH, uint24(500), USDC, uint24(100), DAI, uint24(500), LUSD)
        });

        subPaths[1] = IPathRegistry.SubPath({
            percent: 25,
            path: abi.encodePacked(WETH, uint24(3000), USDC, uint24(500), FRAX, uint24(500), LUSD)
        });

        subPaths[2] = IPathRegistry.SubPath({percent: 20, path: abi.encodePacked(WETH, uint24(3000), LUSD)});
    }

    function getBrokenPathUniV3() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        subPaths = new IPathRegistry.SubPath[](1);

        subPaths[0] = IPathRegistry.SubPath({
            percent: 100,
            path: abi.encodePacked(WETH, uint24(500), RANDOM_ADDRESS, uint24(500), LUSD)
        });
    }

    function getPathNoEthPool() internal pure returns (IPathRegistry.SubPath[] memory subPaths) {
        subPaths = new IPathRegistry.SubPath[](1);

        subPaths[0] = IPathRegistry.SubPath({percent: 100, path: abi.encodePacked(WETH, uint24(500), RANDOM_ADDRESS)});
    }
}
