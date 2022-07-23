// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {AceOfZkBridge} from "../../../bridges/aceofzk/AceOfZkBridge.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract AceOfZkTest is BridgeTestBase {
    IERC721 public constant ACE_OF_ZK_NFT = IERC721(0xE56B526E532804054411A470C49715c531CFd485);
    address public constant NFT_HOLDER = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    uint256 public constant NFT_ID = 16;

    AceOfZkBridge internal bridge;

    AztecTypes.AztecAsset private ethAsset;

    function setUp() public {
        bridge = new AceOfZkBridge(address(ROLLUP_PROCESSOR));

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 200000);

        vm.prank(NFT_HOLDER);
        ACE_OF_ZK_NFT.approve(address(bridge), NFT_ID);

        ethAsset = getRealAztecAsset(address(0));
    }

    function testHappyPath() public {
        // Fund rollup processor
        vm.deal(address(ROLLUP_PROCESSOR), 1);
        assertTrue(ACE_OF_ZK_NFT.ownerOf(NFT_ID) != address(ROLLUP_PROCESSOR), "The rollup processor owns the nft");

        uint256 bId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        uint256 bridgeCallData = encodeBridgeCallData(bId, ethAsset, emptyAsset, ethAsset, emptyAsset, 0);

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), 1, 0, 0, true, "");
        sendDefiRollup(bridgeCallData, 1);

        assertEq(ACE_OF_ZK_NFT.ownerOf(NFT_ID), address(ROLLUP_PROCESSOR), "The rollup processor does not own the nft");
    }

    function testWrongCaller(address _caller) public {
        vm.assume(_caller != address(ROLLUP_PROCESSOR));
        vm.prank(_caller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(ethAsset, emptyAsset, ethAsset, emptyAsset, 0, 0, 0, _caller);
    }

    function testAsyncDisabled() public {
        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(ethAsset, emptyAsset, ethAsset, emptyAsset, 0, 0);
    }
}
