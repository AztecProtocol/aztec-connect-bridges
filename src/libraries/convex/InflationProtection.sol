// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library InflationProtection {
    using Math for uint256;

    /**
     * @notice Calculate the shares using the current assets to shares ratio (offset)
     * @dev To prevent reseting the ratio due to withdrawal of all shares, we start with
     * 1 asset/1e10 shares already burned. This also starts with a 1 : 1e10 ratio which
     * functions like 10 decimal fixed point math. This prevents ratio attacks or inaccuracy
     * due to 'gifting' or rebasing tokens. (Up to a certain degree)
     */
    function _convertToShares(uint256 _assets, uint256 _totalShares, uint256 _totalAssets)
        internal
        pure
        returns (uint256 shares)
    {
        uint256 offset = 1e10;

        shares = _assets.mulDiv(_totalShares + offset, _totalAssets + 1);
    }

    /**
     * @notice Calculate the assets using the current assets to shares ratio (offset)
     * @dev To prevent reseting the ratio due to withdrawal of all shares, we start with
     * 1 asset/1e10 shares already burned. This also starts with a 1 : 1e10 ratio which
     * functions like 10 decimal fixed point math. This prevents ratio attacks or inaccuracy
     * due to 'gifting' or rebasing tokens. (Up to a certain degree)
     */
    function _convertToAssets(uint256 _shares, uint256 _totalShares, uint256 _totalAssets)
        internal
        pure
        returns (uint256 assets)
    {
        uint256 offset = 1e10;

        assets = _shares.mulDiv(_totalAssets + 1, _totalShares + offset);
    }
}
