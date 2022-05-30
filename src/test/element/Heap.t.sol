pragma solidity 0.8.10;

import {HeapTestContract} from "./HeapTestContract.sol";
import "../../../lib/ds-test/src/test.sol";

import {console} from "forge-std/console.sol";

contract HeapTest is DSTest {
    HeapTestContract heap;

    function setUp() public {
        heap = new HeapTestContract(100);
    }

    function testCanAddToHeap() public {
        uint64 newValue = 87;
        heap.add(newValue);
        assertEq(heap.min(), newValue);
    }

    function testReturnsMinimum() public {
        heap.add(87);
        assertEq(heap.min(), 87);
        heap.add(56);
        assertEq(heap.min(), 56);
    }

    function testReportsSize() public {
        heap.add(87);
        assertEq(heap.size(), 1);
        heap.add(56);
        assertEq(heap.size(), 2);
    }

    function testRemovesValue() public {
        heap.add(87);
        assertEq(heap.min(), 87);
        heap.add(56);
        assertEq(heap.min(), 56);
        heap.remove(87);
        assertEq(heap.size(), 1);
        assertEq(heap.min(), 56);
        heap.remove(56);
        assertEq(heap.size(), 0);
    }

    function testRemovesMinumum() public {
        heap.add(87);
        assertEq(heap.min(), 87);
        heap.add(56);
        assertEq(heap.min(), 56);
        heap.pop();
        assertEq(heap.size(), 1);
        assertEq(heap.min(), 87);
        // can remove 56 again, won't make any difference
        heap.remove(56);
        assertEq(heap.size(), 1);
        assertEq(heap.min(), 87);
        heap.pop();
        assertEq(heap.size(), 0);
    }

    function testPopDown1() public {
        uint8[10] memory values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
        }
        // heap will look exactly the same as the array of values above
        // now when we pop it, 10 will be moved to index zero and get sifted back down
        // swapping with each left child i.e. 2, 4, 8
        // continue for all values, some swaps will be right child and some will be left
        for (uint256 min = 2; min < 11; min++) {
            heap.pop();
            assertEq(heap.min(), min);
        }
    }

    function testPopDown2() public {
        uint8[10] memory values = [1, 3, 2, 5, 4, 7, 6, 9, 8, 10];
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
        }
        // heap will look exactly the same as the array of values above
        // now when we pop it, 10 will be moved to index zero and get sifted back down
        // swapping with each left child i.e. 2, 4, 8
        // continue for all values, some swaps will be right child and some will be left
        for (uint256 min = 2; min < 11; min++) {
            heap.pop();
            assertEq(heap.min(), min);
        }
    }

    function testWorksWithDuplicateValues() public {
        uint8[30] memory values = [
            1,
            1,
            1,
            2,
            2,
            2,
            3,
            3,
            3,
            4,
            4,
            4,
            5,
            5,
            5,
            6,
            6,
            6,
            7,
            7,
            7,
            8,
            8,
            8,
            9,
            9,
            9,
            10,
            10,
            10
        ];
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
        }
        for (uint256 i = 1; i < values.length; i++) {
            heap.pop();
            assertEq(heap.min(), values[i]);
        }
    }

    function testAddAndRemoveMinMultiples(uint64[100] memory values) public {
        uint64[] memory sortedValues = sortArray(values);
        uint64 minimum = type(uint64).max;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, "insert");
        }
        assertEq(heap.size(), values.length);

        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(heap.min(), sortedValues[i], "pop");
            assertEq(heap.size(), sortedValues.length - i);
            heap.pop();
        }
        assertEq(heap.size(), 0);
    }

    function testAddAndRemoveNonMinMultiples(uint64[100] memory values) public {
        uint64 minimum = type(uint64).max;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, "insert");
        }
        assertEq(heap.size(), values.length);

        for (uint256 i = 0; i < values.length - 1; i++) {
            heap.remove(values[values.length - (i + 1)]);
            assertEq(heap.size(), values.length - (i + 1));
            assertEq(heap.min(), getMin(values, values.length - (i + 1)));
        }
        assertEq(heap.size(), 1);
        assertEq(heap.min(), values[0]);
    }

    function testAddAndRemoveMinViaSearch(uint64[100] memory values) public {
        uint64[] memory sortedValues = sortArray(values);
        uint64 minimum = type(uint64).max;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, "insert");
        }
        assertEq(heap.size(), values.length);

        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(heap.min(), sortedValues[i], "pop");
            assertEq(heap.size(), sortedValues.length - i);
            uint64 min = heap.min();
            heap.remove(min);
        }
        assertEq(heap.size(), 0);
    }

    function testCanBuildHeapGreaterThanInitialised(uint64[100] memory values) public {
        uint64[] memory sortedValues = sortArray(values);

        HeapTestContract newHeap = new HeapTestContract(1);
        uint64 minimum = type(uint64).max;
        for (uint256 i = 0; i < values.length; i++) {
            newHeap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(newHeap.min(), minimum, "insert");
        }
        assertEq(newHeap.size(), values.length);

        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(newHeap.min(), sortedValues[i], "pop");
            assertEq(newHeap.size(), sortedValues.length - i);
            newHeap.pop();
        }
        assertEq(newHeap.size(), 0);
    }

    function getMin(uint64[100] memory array, uint256 upperBound) internal pure returns (uint64 min) {
        min = type(uint64).max;
        for (uint256 i = 0; i < upperBound; i++) {
            if (array[i] < min) {
                min = array[i];
            }
        }
    }

    function sortArray(uint64[100] memory array) private pure returns (uint64[] memory outputArray) {
        if (array.length == 0) {
            return new uint64[](0);
        }
        uint256 l = array.length;
        outputArray = new uint64[](l);
        for (uint256 i = 0; i < l; i++) {
            outputArray[i] = array[i];
        }

        bool swapped = false;
        for (uint256 i = 0; i < l - 1; i++) {
            swapped = false;
            for (uint256 j = 0; j < l - i - 1; j++) {
                if (outputArray[j] > outputArray[j + 1]) {
                    uint64 temp = outputArray[j];
                    outputArray[j] = outputArray[j + 1];
                    outputArray[j + 1] = temp;
                    swapped = true;
                }
            }
            if (!swapped) {
                break;
            }
        }

        return outputArray;
    }
}
