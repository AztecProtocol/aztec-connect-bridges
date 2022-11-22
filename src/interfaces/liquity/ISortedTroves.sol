// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface ISortedTroves {
    function getLast() external view returns (address);

    function getNext(address _id) external view returns (address);

    function getPrev(address _id) external view returns (address);

    function findInsertPosition(uint256 _ICR, address _prevId, address _nextId)
        external
        view
        returns (address, address);
}
