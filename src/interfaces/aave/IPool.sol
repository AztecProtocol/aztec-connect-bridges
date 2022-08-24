// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.4;

import {DataTypes} from "./../../libraries/aave/DataTypes.sol";

/**
 * @notice Minimal interface for the Aave IPool for V3. Assuming that V3 will update the ReserveData struct
 */
interface IPool {
    function getReserveData(address asset) external view returns (DataTypes.ReserveDataV3 memory);
}
