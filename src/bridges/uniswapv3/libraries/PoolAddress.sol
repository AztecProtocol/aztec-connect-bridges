// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.10 <=0.8.10;

///note: @dev of Aztec Connect Uniswap V3 Bridge for LP. This library has been modified to conform to version 0.8.x of solidity.
///the change is in lines 37-38, which were originally an explicit type conversion from uint256 to address like thus:
///address( uint256 ( .... )) 
/// certain kinds of explicit type conversions have been disallowed in solidity versions 0.8.x
///the fix for this is to change line 37-38 from address(uint256(...)) to address(uint160(uint256(...))), i.e. add an intermediate type conversion
///see https://docs.soliditylang.org/en/v0.8.11/080-breaking-changes.html
///this is the only change in the entire file
/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(                                    //this line has been modified from the original Uniswap V3 library
                uint256( 
                    keccak256(
                        abi.encodePacked(
                            hex'ff',
                            factory,
                            keccak256(abi.encode(key.token0, key.token1, key.fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}