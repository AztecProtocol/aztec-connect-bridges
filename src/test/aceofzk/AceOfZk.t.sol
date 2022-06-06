// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";

import {AceOfZkBridge} from "./../../bridges/aceofzk/AceOfZkBridge.sol";

contract AceOfZkTest is Test {
    error InvalidCaller();
    error AsyncDisabled();

    IERC721 public constant ACE_OF_ZK_NFT = IERC721(0xE56B526E532804054411A470C49715c531CFd485);
    address public constant NFT_HOLDER = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    uint256 public constant NFT_ID = 16;

    AceOfZkBridge internal bridge;
    DefiBridgeProxy internal defiBridgeProxy;
    RollupProcessor internal rollupProcessor;

    AztecTypes.AztecAsset private empty;
    AztecTypes.AztecAsset private ethAsset =
        AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});

    function setUp() public {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));

        bridge = new AceOfZkBridge(address(rollupProcessor));

        vm.prank(NFT_HOLDER);
        ACE_OF_ZK_NFT.approve(address(bridge), NFT_ID);
    }

    function testHappyPath() public {
        // Fund rollup processor
        vm.deal(address(rollupProcessor), 1);

        assertTrue(ACE_OF_ZK_NFT.ownerOf(NFT_ID) != address(rollupProcessor), "The rollup processor owns the nft");

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(bridge),
            ethAsset,
            empty,
            ethAsset,
            empty,
            1,
            0,
            0
        );

        assertEq(outputValueA, 0, "Non zero return a");
        assertEq(outputValueB, 0, "Non zero return b");
        assertFalse(isAsync, "The convert was async");
        assertEq(ACE_OF_ZK_NFT.ownerOf(NFT_ID), address(rollupProcessor), "The rollup processor don't own the nft");
    }

    function testWrongCaller(address _caller) public {
        vm.assume(_caller != address(rollupProcessor));

        vm.prank(_caller);

        vm.expectRevert(InvalidCaller.selector);
        bridge.convert(ethAsset, empty, ethAsset, empty, 0, 0, 0, _caller);
    }

    function testAsyncDisabled() public {
        vm.expectRevert(AsyncDisabled.selector);
        bridge.finalise(ethAsset, empty, ethAsset, empty, 0, 0);
    }
}
