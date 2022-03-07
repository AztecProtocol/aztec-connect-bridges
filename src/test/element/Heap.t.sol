pragma solidity 0.8.10;

import { HeapTestContract } from './HeapTestContract.sol';
import "../../../lib/ds-test/src/test.sol";

import { console } from '../console.sol';

contract HeapTest is DSTest {
    HeapTestContract heap;

    uint64[] randomInts = [
        207, 628, 47, 920, 864, 132, 942, 684, 573, 451, 476, 594, 152, 466, 885, 300, 357, 266, 803, 320, 80, 184, 318, 949, 983, 917, 925, 808, 270,
        757, 981, 336, 458, 973, 907, 586, 869, 194, 418, 824, 847, 28, 575, 400, 249, 956, 216, 548, 699, 461, 914, 95, 482, 265, 617, 208, 954, 685,
        512, 429, 172, 292, 952, 288, 762, 362, 711, 138, 506, 443, 417, 264, 272, 108, 127, 814, 936, 158, 298, 797, 106, 175, 871, 722, 151, 26, 720,
        304, 497, 665, 245, 953, 262, 398, 743, 363, 639, 723, 935, 807
    ];

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

    function testAddAndRemoveMinMultiples() public {
        uint64[] memory values = new uint64[](randomInts.length);
        uint64[] memory sortedValues = new uint64[](randomInts.length);
        for (uint256 i = 0; i < randomInts.length; i++) {
            values[i] = randomInts[i];
            sortedValues[i] = randomInts[i];
        }
        sortArray(sortedValues);
        uint64 minimum = 10000;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, 'insert');
        }    
        assertEq(heap.size(), values.length);


        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(heap.min(), sortedValues[i], 'pop');
            assertEq(heap.size(), sortedValues.length - i);
            heap.pop();
        }
        assertEq(heap.size(), 0);
    }

    function testAddAndRemoveNonMinMultiples() public {
        uint64[] memory values = new uint64[](randomInts.length);
        uint64[] memory sortedValues = new uint64[](randomInts.length);
        for (uint256 i = 0; i < randomInts.length; i++) {
            values[i] = randomInts[i];
            sortedValues[i] = randomInts[i];
        }
        sortArray(sortedValues);
        uint64 minimum = 10000;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, 'insert');
        }    
        assertEq(heap.size(), values.length);

        for (uint256 i = 0; i < randomInts.length - 1; i++) {
            heap.remove(randomInts[randomInts.length - (i + 1)]);
            assertEq(heap.size(), randomInts.length - (i + 1));
            assertEq(heap.min(), getMinOfRandomInts(randomInts.length - (i + 1)));
        }
        assertEq(heap.size(), 1);
        assertEq(heap.min(), randomInts[0]);
    }

    function testAddAndRemoveMinViaSearch() public {
        uint64[] memory values = new uint64[](randomInts.length);
        uint64[] memory sortedValues = new uint64[](randomInts.length);
        for (uint256 i = 0; i < randomInts.length; i++) {
            values[i] = randomInts[i];
            sortedValues[i] = randomInts[i];
        }
        sortArray(sortedValues);
        uint64 minimum = 10000;
        for (uint256 i = 0; i < values.length; i++) {
            heap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(heap.min(), minimum, 'insert');
        }    
        assertEq(heap.size(), values.length);


        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(heap.min(), sortedValues[i], 'pop');
            assertEq(heap.size(), sortedValues.length - i);
            heap.remove(heap.min());
        }
        assertEq(heap.size(), 0);
    }

    function testCanBuildHeapGreaterThanInitialised() public {
        HeapTestContract newHeap = new HeapTestContract(1);
        uint64[] memory values = new uint64[](randomInts.length);
        uint64[] memory sortedValues = new uint64[](randomInts.length);
        for (uint256 i = 0; i < randomInts.length; i++) {
            values[i] = randomInts[i];
            sortedValues[i] = randomInts[i];
        }
        sortArray(sortedValues);
        uint64 minimum = 10000;
        for (uint256 i = 0; i < values.length; i++) {
            newHeap.add(values[i]);
            if (values[i] < minimum) {
                minimum = values[i];
            }
            assertEq(newHeap.min(), minimum, 'insert');
        }    
        assertEq(newHeap.size(), values.length);


        for (uint256 i = 0; i < sortedValues.length; i++) {
            assertEq(newHeap.min(), sortedValues[i], 'pop');
            assertEq(newHeap.size(), sortedValues.length - i);
            newHeap.pop();
        }
        assertEq(newHeap.size(), 0);
    }

    function getMinOfRandomInts(uint256 upperBound) internal view returns (uint64 min) {
        min = 10000;
        for (uint256 i = 0; i < upperBound; i++) {
            if (randomInts[i] < min) {
                min = randomInts[i];
            }
        }
    }

    function sortArray(uint64[] memory array) private pure {
        if (array.length == 0) {
            return;
        }
        uint256 l = array.length;
        bool swapped = false;
        for(uint i = 0; i < l - 1; i++) {
            swapped = false;
            for(uint j = 0; j < l - i - 1; j++) {
                if(array[j] > array[j + 1]) {
                    uint64 temp = array[j];
                    array[j] = array[j + 1];
                    array[j + 1] = temp;
                    swapped = true;
                }
            }
            if (!swapped) {
                break;
            }
        }
    }
}