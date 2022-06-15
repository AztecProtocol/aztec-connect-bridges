// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

contract AceOfZkBridge is BridgeBase {
    address public constant ACE_OF_ZK_NFT = 0xE56B526E532804054411A470C49715c531CFd485;
    address public constant NFT_HOLDER = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    uint256 public constant NFT_ID = 16;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function convert(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint256,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256,
            uint256,
            bool
        )
    {
        IERC721(ACE_OF_ZK_NFT).transferFrom(NFT_HOLDER, ROLLUP_PROCESSOR, NFT_ID);
        return (0, 0, false);
    }
}
