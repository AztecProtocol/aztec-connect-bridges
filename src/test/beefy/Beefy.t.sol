// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from '../../../lib/forge-std/src/Vm.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {DefiBridgeProxy} from './../../aztec/DefiBridgeProxy.sol';
import {RollupProcessor} from './../../aztec/RollupProcessor.sol';
import {IBeefyVault} from './../../bridges/beefy/Interfaces/IBeefyVault.sol';
import {BeefyBridge} from './../../bridges/beefy/BeefyBridge.sol';
import {AztecTypes} from './../../aztec/AztecTypes.sol';
import {console} from '../console.sol';
import '../../../lib/ds-test/src/test.sol';

contract Beefy is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    IBeefyVault vault;
    BeefyBridge beefybridge;

    IERC20 constant dai = IERC20(0x2cF7252e74036d1Da831d11089D326296e64a728);
    //https://polygonscan.com/address/0xE695fCeD8fD93eeE54204a7fC33323a60d41865A#readContract
    IBeefyVault constant beefy = IBeefyVault(0x4462817b53E76b722c2D174D0148ddb81452f1dE);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        beefybridge = new BeefyBridge(address(rollupProcessor));
        //beefybridge.validateVault(address(beefy));
        rollupProcessor.setBridgeGasLimit(address(beefybridge), 1000000);
    }

    function testBeefyBridge() public {
        uint256 depositAmount = 5000;

        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(beefy),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(beefybridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        uint256 rollupBeefy = beefy.balanceOf(address(rollupProcessor));
        console.log(rollupBeefy, 'ouput amount');
        //assertEq(depositAmount, rollupBeefy, 'Balances must match');
    }

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log('Error: a != b not satisfied [address]');
            emit log_named_address('  Expected', b);
            emit log_named_address('    Actual', a);
            fail();
        }
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 1; // May vary depending on token

        vm.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));
        console.log('setting up token balance things');
        assertEq(IERC20(token).balanceOf(user), balance, 'wrong balance');
    }
}
