// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IAaveLendingBridgeConfigurator} from './interfaces/IAaveLendingBridgeConfigurator.sol';
import {IAaveLendingBridge} from './interfaces/IAaveLendingBridge.sol';
import {ILendingPool} from './../imports/interfaces/ILendingPool.sol';
import {IPool} from './../imports/interfaces/IPool.sol';

/**
 * @notice AaveLendingBridgeConfigurator implementation that is used to add new listings to the AaveLendingBridge
 * permissionlessly deposit and withdraw funds into the listed reserves. Configurator cannot remove nor update listings
 * @author Lasse Herskind
 */
contract AaveLendingBridgeConfigurator is IAaveLendingBridgeConfigurator, Ownable {
    function addNewPool(
        address lendingBridge,
        address underlyingAsset,
        address aTokenAddress
    ) public override(IAaveLendingBridgeConfigurator) onlyOwner {
        IAaveLendingBridge(lendingBridge).setUnderlyingToZkAToken(underlyingAsset, aTokenAddress);
    }

    function addPoolFromV2(address lendingBridge, address underlyingAsset)
        external
        override(IAaveLendingBridgeConfigurator)
        onlyOwner
    {
        IAaveLendingBridge bridge = IAaveLendingBridge(lendingBridge);
        ILendingPool pool = ILendingPool(bridge.ADDRESSES_PROVIDER().getLendingPool());

        address aTokenAddress = pool.getReserveData(underlyingAsset).aTokenAddress;

        addNewPool(lendingBridge, underlyingAsset, aTokenAddress);
    }

    function addPoolFromV3(address lendingBridge, address underlyingAsset)
        external
        override(IAaveLendingBridgeConfigurator)
        onlyOwner
    {
        IAaveLendingBridge bridge = IAaveLendingBridge(lendingBridge);
        IPool pool = IPool(bridge.ADDRESSES_PROVIDER().getLendingPool());

        address aTokenAddress = pool.getReserveData(underlyingAsset).aTokenAddress;

        addNewPool(lendingBridge, underlyingAsset, aTokenAddress);
    }
}
