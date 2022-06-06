// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAaveLendingBridgeConfigurator} from "./interfaces/IAaveLendingBridgeConfigurator.sol";
import {IAaveLendingBridge} from "./interfaces/IAaveLendingBridge.sol";
import {ILendingPool} from "./../imports/interfaces/ILendingPool.sol";
import {IPool} from "./../imports/interfaces/IPool.sol";

/**
 * @notice AaveLendingBridgeConfigurator implementation that is used to add new listings to the AaveLendingBridge
 * permissionlessly deposit and withdraw funds into the listed reserves. Configurator cannot remove nor update listings
 * @author Lasse Herskind
 */
contract AaveLendingBridgeConfigurator is IAaveLendingBridgeConfigurator, Ownable {
    function addPoolFromV2(address _lendingBridge, address _underlyingAsset)
        external
        override(IAaveLendingBridgeConfigurator)
    {
        IAaveLendingBridge bridge = IAaveLendingBridge(_lendingBridge);
        ILendingPool pool = ILendingPool(bridge.ADDRESSES_PROVIDER().getLendingPool());

        address aTokenAddress = pool.getReserveData(_underlyingAsset).aTokenAddress;

        addNewPool(_lendingBridge, _underlyingAsset, aTokenAddress);
    }

    function addPoolFromV3(address _lendingBridge, address _underlyingAsset)
        external
        override(IAaveLendingBridgeConfigurator)
    {
        IAaveLendingBridge bridge = IAaveLendingBridge(_lendingBridge);
        IPool pool = IPool(bridge.ADDRESSES_PROVIDER().getLendingPool());

        address aTokenAddress = pool.getReserveData(_underlyingAsset).aTokenAddress;

        addNewPool(_lendingBridge, _underlyingAsset, aTokenAddress);
    }

    function claimLiquidityRewards(
        address _lendingBridge,
        address _incentivesController,
        address[] calldata _assets,
        address _beneficiary
    ) external override(IAaveLendingBridgeConfigurator) onlyOwner returns (uint256) {
        return IAaveLendingBridge(_lendingBridge).claimLiquidityRewards(_incentivesController, _assets, _beneficiary);
    }

    function addNewPool(
        address _lendingBridge,
        address _underlyingAsset,
        address _aTokenAddress
    ) public override(IAaveLendingBridgeConfigurator) onlyOwner {
        IAaveLendingBridge(_lendingBridge).setUnderlyingToZkAToken(_underlyingAsset, _aTokenAddress);
    }
}
