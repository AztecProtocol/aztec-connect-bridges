// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../../../lib/forge-std/src/Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MStableBridge} from "./../../bridges/mStable/MStableBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";

import "../../../lib/forge-std/src/stdlib.sol";
import "../../../lib/ds-test/src/test.sol";


contract MStableTest is DSTest {

    using stdStorage for StdStorage;

    StdStorage stdStore;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    MStableBridge mStableBridge;

    mapping (string => IERC20) tokens;



    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        mStableBridge = new MStableBridge(
            address(rollupProcessor)
        );

       
        tokens["DAI"] = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        tokens["imUSD"] = IERC20(0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19);
    

        rollupProcessor.setBridgeGasLimit(address(mStableBridge), 900000);

    }


    function testMStableIMUSDToDai() public {
       uint256 depositAmount = 1 * 10 ** 21;
        _setTokenBalance("DAI", address(rollupProcessor), depositAmount);
        
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(tokens["imUSD"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(mStableBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                100
            );

        uint256 newRollupimUSD = tokens["imUSD"].balanceOf(address(rollupProcessor));
		uint256 newRollupDai = tokens["DAI"].balanceOf(address(rollupProcessor));

        
        assertEq(
            outputValueA,
            newRollupimUSD,
            "Balances must match"
        );

	    assertEq(
            outputValueB,
            0,
            "Should have no output value b"
        );
        
        assertEq(
            newRollupDai,
            0,
            "All Dai should be spent"
        );

        assertTrue(
             !isAsync,
             "Should be sync"
        );
    }

	function testMStableDaiToImusd() public {
	
        uint256 daiDepositAmount = 1000 * 10 ** 18;
            
        _setTokenBalance("DAI", address(rollupProcessor), daiDepositAmount);
			
			AztecTypes.AztecAsset memory empty;

			AztecTypes.AztecAsset memory imUSD = AztecTypes.AztecAsset({
					id: 2,
					erc20Address: address(tokens["imUSD"]),
					assetType: AztecTypes.AztecAssetType.ERC20
			});
			AztecTypes.AztecAsset memory dai = AztecTypes.AztecAsset({
					id: 1,
					erc20Address: address(tokens["DAI"]),
					assetType: AztecTypes.AztecAssetType.ERC20
			});

             (uint256 imUSDAmount, ,) = rollupProcessor.convert(
                address(mStableBridge),
                dai,
                empty,
                imUSD,
                empty,
                daiDepositAmount,
                1,
                100
            );

			(
					uint256 outputValueA,
					uint256 outputValueB,
					bool isAsync
			) = rollupProcessor.convert(
							address(mStableBridge),
							imUSD,
							empty,
							dai,
							empty,
							imUSDAmount,
							2,
							100
					);

			uint256 newRollupimUSD = tokens["imUSD"].balanceOf(address(rollupProcessor));
			uint256 newRollupDai = tokens["DAI"].balanceOf(address(rollupProcessor));

			
			assertEq(
					outputValueA,
					newRollupDai,
					"Balances must match"
			);

			assertEq(
					outputValueB,
					0,
					"Should have no output value b"
			);
			
			assertEq(
					newRollupimUSD,
					0,
					"All Dai should be spent"
			);

			assertTrue(
						!isAsync,
						"Should be sync"
			);
    }

     function _setTokenBalance(
        string memory asset,
        address account,
        uint256 balance
    ) internal {
        bytes32 slot = _findTokenBalanceSlot(asset, account);
        address tokenAddress = address(tokens[asset]);

        vm.store(
            tokenAddress,
            slot,
            bytes32(uint256(balance))
        );

        assertEq(tokens[asset].balanceOf(account), balance, "wrong balance");
    }

    function compareStrings(string memory a, string memory b) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function _findTokenBalanceSlot(string memory asset, address account) internal returns (bytes32 slot) {
        string memory usdc = "USDC";
        if (!compareStrings(asset, usdc)) {
            bytes4 selector = bytes4(keccak256(abi.encodePacked("balanceOf(address)")));
            uint256 foundSlot = stdStore.target(address(tokens[asset])).sig(selector).with_key(account).find();        
            slot = bytes32(foundSlot);
		} else {
            slot = keccak256(abi.encode(account, uint256(9)));
        }
    }
}