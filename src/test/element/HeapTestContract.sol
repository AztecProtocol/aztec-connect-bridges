pragma solidity 0.8.10;

import {MinHeap} from "../../bridges/element/MinHeap.sol";
import "../../../lib/ds-test/src/test.sol";

import {console} from "forge-std/console.sol";

contract HeapTestContract {
    using MinHeap for MinHeap.MinHeapData;

    MinHeap.MinHeapData heap;

    constructor(uint32 initialSize) {
        heap.initialise(initialSize);
    }

    function add(uint64 value) public {
        heap.add(value);
    }

    function min() public view returns (uint64) {
        return heap.min();
    }

    function remove(uint64 value) public {
        heap.remove(value);
    }

    function pop() public {
        heap.pop();
    }

    function size() public view returns (uint256) {
        return heap.size();
    }
}
