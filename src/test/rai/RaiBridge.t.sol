// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import {Vm} from "../Vm.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {MockRollupProcessor} from "./../../aztec/MockRollupProcessor.sol";
import {AggregatorV3Interface} from "./../../bridges/rai/interfaces/AggregatorV3Interface.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RaiBridge} from "./../../bridges/rai/RaiBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";


contract RaiBridgeTest is DSTest {

    using SafeMath for uint256;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    MockRollupProcessor rollupProcessor;

    RaiBridge raiBridge;

    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x4ad7B025127e89263242aB68F0f9c4E5C033B489);

    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant rai = IERC20(0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new MockRollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        raiBridge = new RaiBridge(
            address(rollupProcessor)
        );
    }

    event Sexxxxxxxxxxyyyyyyyyyy(uint num);
     

    function testCollateralDeposit() public {
        uint depositAmount = 10e18;
        uint rollUpRai = _addCollateral(depositAmount);

        // rai to Eth Ratio
        (, int x, , ,) = priceFeed.latestRoundData();

        uint raiToEth = uint(x);

        uint actualCollateralRatio = depositAmount.mul(1e22).div(raiToEth).div(rollUpRai);

        require(
            actualCollateralRatio == raiBridge.collateralRatio(), 
            "Collateral ratio does not equal expected"
        );
    }

    // percentageThreshold is in BPS (divide by 10000)
    function assertApprox(uint actual, uint expected, uint percentageThreshold, string memory errorMsg) internal {
        uint diff;
        if (actual > expected) {
            diff = actual - expected;
        } else {
            diff = expected - actual;
        }

        require(diff < (actual.mul(percentageThreshold).div(10000)), errorMsg);

    }


    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }


    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 3; // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }

    function _addCollateral(uint depositAmount) internal returns (uint rollUpRai){

        _setTokenBalance(address(weth), address(rollupProcessor), depositAmount);

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        require(rollUpRai == 0, "initial rollup balance not zero");

        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1, 
            erc20Address: address(weth),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1, 
            erc20Address: address(rai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            ,
            
        ) = rollupProcessor.convert(
                address(raiBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                0
        );

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        emit Sexxxxxxxxxxyyyyyyyyyy(rollUpRai);
        emit Sexxxxxxxxxxyyyyyyyyyy(outputValueA);

        require(
            outputValueA == rollUpRai,
            "Rai balance dont match"
        );
    }
}
