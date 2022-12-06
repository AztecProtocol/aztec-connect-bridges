pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {BridgeBase} from "../bridges/base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../aztec/interfaces/ISubsidy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract SubsidyFunding is Test {
    ISubsidy public constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);

    address[] private shareAddresses = [
        0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0, // ERC4626-Wrapped Euler WETH (weWETH)
        0x4169Df1B7820702f566cc10938DA51F6F597d264, //  ERC4626-Wrapped Euler DAI (weDAI)
        0x60897720AA966452e8706e74296B018990aEc527, //  ERC4626-Wrapped Euler wstETH (wewstETH)
        0xbcb91e0B4Ad56b0d41e0C168E3090361c0039abC, //  ERC4626-Wrapped AAVE V2 DAI (wa2DAI)
        0xc21F107933612eCF5677894d45fc060767479A9b //  ERC4626-Wrapped AAVE V2 WETH (wa2WETH)
    ];

    AztecTypes.AztecAsset internal emptyAsset;

    function listSubsidies() public {
        // bridge address asset combination gas usage subsidy
        BridgeBase erc4626Bridge = BridgeBase(0x3578D6D5e1B4F07A48bb1c958CBfEc135bef7d98);
        for (uint256 i = 0; i < shareAddresses.length; i++) {
            address share = shareAddresses[i];
            address asset = IERC4626(share).asset();

            AztecTypes.AztecAsset memory shareAsset = AztecTypes.AztecAsset({
                id: 0, // ID is not used when computing criteria and for this reason can be incorrect
                erc20Address: share,
                assetType: AztecTypes.AztecAssetType.ERC20
            });
            AztecTypes.AztecAsset memory assetAsset = AztecTypes.AztecAsset({
                id: 0, // ID is not used when computing criteria and for this reason can be incorrect
                erc20Address: asset,
                assetType: AztecTypes.AztecAssetType.ERC20
            });

            uint256 enterCriteria = erc4626Bridge.computeCriteria(assetAsset, emptyAsset, shareAsset, emptyAsset, 0);
            uint256 exitCriteria = erc4626Bridge.computeCriteria(shareAsset, emptyAsset, assetAsset, emptyAsset, 0);

            ISubsidy.Subsidy memory enterSubsidy = SUBSIDY.getSubsidy(address(erc4626Bridge), enterCriteria);
            ISubsidy.Subsidy memory exitSubsidy = SUBSIDY.getSubsidy(address(erc4626Bridge), exitCriteria);

            emit log_string("========================");
            emit log_named_address("share", share);
            emit log_named_uint("enterCriteria", enterCriteria);
            emit log_named_uint("enterCriteria available aubsidy", enterSubsidy.available);
            emit log_named_uint("exitCriteria", exitCriteria);
            emit log_named_uint("exitCriteria available aubsidy", exitSubsidy.available);
        }
    }
}
