pragma solidity 0.8.10;

/**
 * @title Min Heap
 * @dev Library for managing an array of uint64 values as a minimum heap
 */
library MinHeap {
    using MinHeap for MinHeapData;

    error HEAP_EMPTY();

    /**
     * @dev Encapsulates the underlying data structure used to manage the heap
     *
     * @param heap the array of values contained within the heap
     * @param heapSize the current size of the heap, usually different to the size of underlying array so tracked seperately
     */
    struct MinHeapData {
        uint32 heapSize;
        uint64[] heap;
    }

    /**
     * @dev used to pre-allocate the underlying array with dummy values
     * Useful for gas optimisation later when tru value start to be added
     * @param self reference to the underlying data structure of the heap
     * @param initialSize the amount of slots to pre-allocate
     */
    function initialise(MinHeapData storage self, uint32 initialSize) internal {
        uint256 i = 0;
        unchecked {
            while (i < initialSize) {
                self.heap.push(type(uint64).max);
                i++;
            }
            self.heapSize = 0;
        }
    }

    /**
     * @dev used to add a new value to the heap
     * @param self reference to the underlying data structure of the heap
     * @param value the value to add
     */
    function add(MinHeapData storage self, uint64 value) internal {
        uint32 hSize = self.heapSize;
        if (hSize == self.heap.length) {
            self.heap.push(value);
        } else {
            self.heap[hSize] = value;
        }
        unchecked {
            self.heapSize = hSize + 1;
        }
        siftUp(self, hSize);
    }

    /**
     * @dev retrieve the current minimum value in the heap
     * @param self reference to the underlying data structure of the heap
     * @return minimum the heap's current minimum value
     */
    function min(MinHeapData storage self) internal view returns (uint64 minimum) {
        if (self.heapSize == 0) {
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
        uint256 index = 0;
        uint32 hSize = self.heapSize;
        while (index < hSize && self.heap[index] != value) {
            unchecked {
                ++index;
            }
        }
        if (index == hSize) {
            return;
        }
        if (index != 0) {
            // the value was found but it is not the minimum value
            // to remove this we set it's value to 0 and sift it up to it's new position
            self.heap[index] = 0;
            siftUp(self, index);
        }
        // now we just need to pop the minimum value
        pop(self);
    }

    /**
     * @dev used to remove the minimum value from the heap
     * @param self reference to the underlying data structure of the heap
     */
    function pop(MinHeapData storage self) internal {
        // if the heap is empty then nothing to do
        uint32 hSize = self.heapSize;
        if (hSize == 0) {
            return;
        }
        // read the value in the last position and shrink the array by 1
        uint64 last = self.heap[--hSize];
        // now sift down
        // write the smallest child value into the parent each time
        // then once we no longer have any smaller children, we write the 'last' value into place
        // requires a total of O(logN) updates
        uint256 index = 0;
        uint256 leftChildIndex;
        uint256 rightChildIndex;
        while (index < hSize) {
            // get the indices of the child values
            unchecked {
                leftChildIndex = (index << 1) + 1; // as long as hSize is not gigantic, we are fine.
                rightChildIndex = leftChildIndex + 1;
            }
            uint256 swapIndex = index;
            uint64 smallestValue = last;
            uint64 leftChild; // Used only for cache

            // identify the smallest child, first check the left
            if (leftChildIndex < hSize && (leftChild = self.heap[leftChildIndex]) < smallestValue) {
                swapIndex = leftChildIndex;
                smallestValue = leftChild;
            }
            // then check the right
            if (rightChildIndex < hSize && self.heap[rightChildIndex] < smallestValue) {
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
        self.heapSize = hSize;
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
    function siftUp(MinHeapData storage self, uint256 index) private {
        uint64 value = self.heap[index];
        uint256 parentIndex;
        while (index > 0) {
            uint64 parent;
            unchecked {
                parentIndex = (index - 1) >> 1;
            }
            if ((parent = self.heap[parentIndex]) <= value) {
                break;
            }
            self.heap[index] = parent; // update
            index = parentIndex;
        }
        self.heap[index] = value;
    }
}
