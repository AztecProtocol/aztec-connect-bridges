pragma solidity 0.8.10;

import { console } from '../../test/console.sol';

library MinHeap {
    using MinHeap for MinHeapData;

    error HEAP_EMPTY();

    uint64 internal constant MAX_INT = 2**64 - 1;

    struct MinHeapData {
        uint64[] heap;
        uint32 heapSize;
        uint32 heapStorageSize;
    }

    function initialise(MinHeapData storage self, uint32 initialSize) public {
        for (uint32 i = 0; i < initialSize; i++) {
            self.heap.push(MAX_INT);
        }
        self.heapStorageSize = initialSize;
        self.heapSize = 0;
    }

    function add(MinHeapData storage self, uint64 value) public {
        addToHeap(self, value);
    }

    function min(MinHeapData storage self) public returns (uint64) {
        if (size(self) == 0) {
            revert HEAP_EMPTY();
        }
        return self.heap[0];
    }

    function remove(MinHeapData storage self, uint64 value) public {
        removeExpiryFromHeap(self, value);
    }

    function pop(MinHeapData storage self) public {
        popFromHeap(self);
    }

    function size(MinHeapData storage self) public returns (uint256) {
        return self.heapSize;
    }

    // move an expiry up through the heap to the correct position
    function siftUp(MinHeapData storage self, uint256 index) internal {
        uint64 value = self.heap[index];
        while (index > 0) {
            uint256 parentIndex = (index - 1) / 2;
            if (self.heap[parentIndex] <= value) {
                break;
            }
            self.heap[index] = self.heap[parentIndex]; // update
            index = parentIndex;
        }
        self.heap[index] = value;
    }

    // add a new expiry to the heap
    function addToHeap(MinHeapData storage self, uint64 expiry) internal {
        // standard min-heap insertion
        // push to the end of the heap and sift up.
        // there is a high probability that the expiry being added will remain where it is
        // so this operation will end up being O(1)
        if (self.heapSize == self.heapStorageSize) {
            self.heap.push(expiry);        
            ++self.heapStorageSize;
        } else {
            self.heap[self.heapSize] = expiry;
        }
        uint256 index = self.heapSize++;
        siftUp(self, index);
    }

    // remove the root expiry from the heap
    function popFromHeap(MinHeapData storage self) internal {
        // if the heap is empty then nothing to do
        if (self.heapSize == 0) {
            return;
        }
        // read the value in the last position and shrink the array by 1
        uint64 last = self.heap[--self.heapSize];
        // now sift down 
        // write the smallest child value into the parent each time
        // then once we no longer have any smaller children, we write the 'last' value into place
        // requires a total of O(logN) updates
        uint256 index = 0;
        while (index < self.heapSize) {
            // get the indices of the child values
            uint256 leftChildIndex = (index * 2) + 1;
            uint256 rightChildIndex = leftChildIndex + 1;
            uint256 swapIndex = index;
            uint64 smallestValue = last;

            // identify the smallest child, first check the left
            if (leftChildIndex < self.heapSize && self.heap[leftChildIndex] < smallestValue) {
                swapIndex = leftChildIndex;
                smallestValue = self.heap[leftChildIndex];
            }
            // then check the right
            if (rightChildIndex < self.heapSize && self.heap[rightChildIndex] < smallestValue) {
                swapIndex = rightChildIndex;
            }
            // if neither child was smaller then nothing more to do
            if (swapIndex == index) {
                self.heap[index] = smallestValue;
                break;
            }
            // take the value from the smallest child and write in into our slot
            self.heap[index] = self.heap[swapIndex];
            index = swapIndex;
        }
    }

    // will remove an expiry from the min-heap
    function removeExpiryFromHeap(MinHeapData storage self, uint64 expiry) internal {
        uint256 index = 0;
        while (index < self.heapSize && self.heap[index] != expiry) {
            ++index;
        }
        if (index == self.heapSize) {
            return;
        }
        if (index != 0) {
            self.heap[index] = 0;
            siftUp(self, index);
        }
        popFromHeap(self);
    }
}