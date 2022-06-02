// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from '../../../lib/forge-std/src/Vm.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {DefiBridgeProxy} from './../../aztec/DefiBridgeProxy.sol';
import {RollupProcessor} from './../../aztec/RollupProcessor.sol';
import {IERC4626} from './../../bridges/erc4626/Interfaces/IERC4626.sol';
import {VaultBridge} from './../../bridges/erc4626/VaultBridge.sol';
import {AztecTypes} from './../../aztec/AztecTypes.sol';
import {console} from '../console.sol';
import '../../../lib/ds-test/src/test.sol';

//Tested at block 14886873 may not work at other blocks
contract ERC4626 is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    VaultBridge vaultbridge;

    IERC20 constant maple = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);

    IERC4626 constant vault = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        vaultbridge = new VaultBridge(address(rollupProcessor));
        //vaultbridge.validateVault(address(vault));
        rollupProcessor.setBridgeGasLimit(address(vaultbridge), 1000000);
    }

    function testVaultBridge() public {
        uint256 depositAmount = 5000;

        _setTokenBalance(address(maple), address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(maple),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(vault),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(vaultbridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        uint256 rollupMapleShares = vault.balanceOf(address(rollupProcessor));
        console.log(rollupMapleShares, 'ouput amount');
        assertEq(rollupMapleShares, 4996);
        rollupProcessor.convert(address(vaultbridge), outputAsset, empty, inputAsset, empty, rollupMapleShares, 1, 0);
        uint256 rollupMapleToken = maple.balanceOf(address(rollupProcessor));
        console.log(rollupMapleToken, 'withdraw amount');
        assertEq(rollupMapleToken, 4999);
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
        uint256 slot = 0; // May vary depending on token

        vm.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));
        console.log('setting up token balance things');
        assertEq(IERC20(token).balanceOf(user), balance, 'wrong balance');
    }
}
