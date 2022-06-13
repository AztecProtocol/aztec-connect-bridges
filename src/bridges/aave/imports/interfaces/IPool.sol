// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {DataTypes} from "./../libraries/DataTypes.sol";

/**
 * @notice Minimal interface for the Aave IPool for V3. Assuming that V3 will update the ReserveData struct
 */
interface IPool {
    function getReserveData(address asset) external view returns (DataTypes.ReserveDataV3 memory);
}
