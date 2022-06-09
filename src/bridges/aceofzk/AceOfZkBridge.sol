// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IRollupProcessor} from "../../interfaces/IRollupProcessor.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";

contract AceOfZkBridge is IDefiBridge {
    error InvalidCaller();
    error AsyncDisabled();

    address public constant ACE_OF_ZK_NFT = 0xE56B526E532804054411A470C49715c531CFd485;
    address public constant NFT_HOLDER = 0xE298a76986336686CC3566469e3520d23D1a8aaD;
    uint256 public constant NFT_ID = 16;

    address public immutable ROLLUP_PROCESSOR;

    constructor(address _rollupProcessor) {
        ROLLUP_PROCESSOR = _rollupProcessor;
    }

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
        returns (
            uint256,
            uint256,
            bool
        )
    {
        if (msg.sender != ROLLUP_PROCESSOR) {
            revert InvalidCaller();
        }

        IERC721(ACE_OF_ZK_NFT).transferFrom(NFT_HOLDER, ROLLUP_PROCESSOR, NFT_ID);

        return (0, 0, false);
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncDisabled();
    }
}
