// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {MinHeap} from "../../../bridges/element/MinHeap.sol";

contract HeapTestContract {
    using MinHeap for MinHeap.MinHeapData;

    MinHeap.MinHeapData private heap;

    constructor(uint32 _initialSize) {
        heap.initialise(_initialSize);
    }

    function add(uint64 _value) public {
        heap.add(_value);
    }

    function remove(uint64 _value) public {
        heap.remove(_value);
    }

    function pop() public {
        heap.pop();
    }

    function min() public view returns (uint64) {
        return heap.min();
    }

    function size() public view returns (uint256) {
        return heap.size();
    }
}
