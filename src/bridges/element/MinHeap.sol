pragma solidity 0.8.10;

/**
 * @title Min Heap
 * @dev Library for managing an array of uint64 values as a minimum heap
 */
library MinHeap {
    using MinHeap for MinHeapData;

    error HEAP_EMPTY();

    // maximum value of uint64. used as initial value in pre-allocated array 
    uint64 internal constant MAX_INT = type(uint64).max;

    /**
     * @dev Encapsulates the underlyding data structure used to manage the heap
     *
     * @param heap the array of values contained within the heap
     * @param heapSize the current size of the heap, usually different to the size of underlying array so tracked seperately
     */
    struct MinHeapData {
        uint64[] heap;
        uint32 heapSize;
    }

    /**
     * @dev used to pre-allocate the underlying array with dummy values
     * Useful for gas optimisation later when tru value start to be added
     * @param self reference to the underlying data structure of the heap
     * @param initialSize the amount of slots to pre-allocate
     */
    function initialise(MinHeapData storage self, uint32 initialSize) internal {
        for (uint32 i = 0; i < initialSize; i++) {
            self.heap.push(MAX_INT);
        }
        self.heapSize = 0;
    }

    /**
     * @dev used to add a new value to the heap
     * @param self reference to the underlying data structure of the heap
     * @param value the value to add
     */
    function add(MinHeapData storage self, uint64 value) internal {
        addToHeap(self, value);
    }

    /**
     * @dev retrieve the current minimum value in the heap
     * @param self reference to the underlying data structure of the heap
     * @return minimum the heap's current minimum value
     */
    function min(MinHeapData storage self) internal view returns (uint64 minimum) {
        if (size(self) == 0) {
            revert HEAP_EMPTY();
        }
        minimum = self.heap[0];
    }

    /**
     * @dev used to remove a value from the heap
     * will remove the first found occurence of the value from the heap, optimised for removal of the minimum value
     * @param self reference to the underlying data structure of the heap
     * @param value the value to be removed
     */
    function remove(MinHeapData storage self, uint64 value) internal {
        removeExpiryFromHeap(self, value);
    }

    /**
     * @dev used to remove the minimum value from the heap
     * @param self reference to the underlying data structure of the heap
     */
    function pop(MinHeapData storage self) internal {
        popFromHeap(self);
    }

    /**
     * @dev retrieve the current size of the heap
     * @param self reference to the underlying data structure of the heap
     * @return currentSize the heap's current size
     */
    function size(MinHeapData storage self) internal view returns (uint256 currentSize) {
        currentSize = self.heapSize;
    }

    /**
     * @dev move the value at the given index up to the correct position in the heap
     * @param self reference to the underlying data structure of the heap
     * @param index the index of the element that is to be correctly positioned
     */
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

    /**
     * @dev private implementation of adding to the heap
     * @param self reference to the underlying data structure of the heap
     * @param value the value to add
     */
    function addToHeap(MinHeapData storage self, uint64 value) private {
        // standard min-heap insertion
        // push to the end of the heap and sift up.
        // there is a high probability that the expiry being added will remain where it is
        // so this operation will end up being O(1)
        if (self.heapSize == self.heap.length) {
            self.heap.push(value);       
        } else {
            self.heap[self.heapSize] = value;
        }
        uint256 index = self.heapSize++;
        siftUp(self, index);
    }

    /**
     * @dev private implementation to remove the minimum value from the heap
     * @param self reference to the underlying data structure of the heap
     */
    function popFromHeap(MinHeapData storage self) private {
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

    /**
     * @dev private implementation used to remove a value from the heap
     * will remove the first found occurence of the value from the heap, optimised for removal of the minimum value
     * @param self reference to the underlying data structure of the heap
     * @param value the value to be removed
     */
    function removeExpiryFromHeap(MinHeapData storage self, uint64 value) private {
        uint256 index = 0;
        while (index < self.heapSize && self.heap[index] != value) {
            ++index;
        }
        if (index == self.heapSize) {
            return;
        }
        if (index != 0) {
            // the value was found but it is not the minimum value
            // to remove this we set it's value to 0 and sift it up to it's new position
            self.heap[index] = 0;
            siftUp(self, index);
        }
        // now we just need to pop the minimum value
        popFromHeap(self);
    }
}