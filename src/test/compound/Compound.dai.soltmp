// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.6 <0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Compound-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CompoundBridgeContract} from "./../../bridges/compound/CompoundBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";


import "../../../lib/ds-test/src/test.sol";


contract CompoundTest is DSTest {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    CompoundBridgeContract compoundBridge;

    // List of relevant cToken contracts
    // Could be pulled from Comptroller's getAllMarkets if needed
    IERC20 constant cAAVE  = IERC20(0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c);
    IERC20 constant cBAT   = IERC20(0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E);
    IERC20 constant cCOMP  = IERC20(0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4);
    IERC20 constant cDAI   = IERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    IERC20 constant cETH   = IERC20(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    IERC20 constant cLINK  = IERC20(0xFAce851a4921ce59e912d19329929CE6da6EB0c7);
    IERC20 constant cMKR   = IERC20(0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b);
    IERC20 constant cSUSHI = IERC20(0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7);
    IERC20 constant cTUSD  = IERC20(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);
    IERC20 constant cUNI   = IERC20(0x35A18000230DA775CAc24873d00Ff85BccdeD550);
    IERC20 constant cUSDC  = IERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    IERC20 constant cUSDP  = IERC20(0x041171993284df560249B57358F931D9eB7b925D);
    IERC20 constant cUSDT  = IERC20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);
    IERC20 constant cWBTC2 = IERC20(0xccF4429DB6322D5C611ee964527D42E5d685DD6a);
    IERC20 constant cYFI   = IERC20(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946);
    IERC20 constant cZRX   = IERC20(0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407);

    // List of all relevant underlying token addresses;
    // Could be pulled from cToken's underlying function (except cETH)
    address AAVEaddress   = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address BATaddress    = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address COMPaddress   = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address DAIaddress    = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address LINKaddress   = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address MKRaddress    = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address SUSHIaddress  = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address TUSDaddress   = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address UNIaddress    = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDCaddress   = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address USDPaddress   = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address USDTaddress   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address WBTCaddress   = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address YFIaddress    = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address ZRXaddress    = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address cAAVEaddress  = 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c;
    address cBATaddress   = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
    address cCOMPaddress  = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
    address cDAIaddress   = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address cETHaddress   = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address cLINKaddress  = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
    address cMKRaddress   = 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b;
    address cSUSHIaddress = 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7;
    address cTUSDaddress  = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86;
    address cUNIaddress   = 0x35A18000230DA775CAc24873d00Ff85BccdeD550;
    address cUSDCaddress  = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address cUSDPaddress  = 0x041171993284df560249B57358F931D9eB7b925D;
    address cUSDTaddress  = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address cWBTC2address = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
    address cYFIaddress   = 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946;
    address cZRXaddress   = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407;

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        compoundBridge = new CompoundBridgeContract(
            address(rollupProcessor),
            //address(cETHaddress)
            address(cDAIaddress)
        );

        _setTokenBalance(DAIaddress, address(0xdead), 42069);
    }


    function testCompoundBridge() public {
        uint256 depositAmount = 150000000000000;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(DAIaddress, address(rollupProcessor), depositAmount);


        //AztecTypes.AztecAsset memory empty;
        //AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
        //    id: 1,
        //    erc20Address: address(0x0000000000000000000000000000000000000000),
        //    assetType: AztecTypes.AztecAssetType.ETH
        //});
        //AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
        //    id: 2,
        //    erc20Address: cETHaddress,
        //    assetType: AztecTypes.AztecAssetType.ERC20
        //});

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: DAIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cDAIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(compoundBridge),
                inputAsset,
                empty,
                outputAsset,
                empty,
                depositAmount,
                1,
                0
            );

        uint256 rollupcDai = cDAI.balanceOf(address(rollupProcessor));
        //uint256 rollupcEth = cETH.balanceOf(address(rollupProcessor));

        assertLt(
            rollupcDai,
            depositAmount,
            "cDai received exceeds DAI deposited"
        );
        assertGt(
            rollupcDai,
            0,
            "cDAI received is zero"
        );

        //assertLt(
        //    rollupcEth,
        //    depositAmount,
        //    "cEth received exceeds ETH deposited"
        //);
        //assertGt(
        //    rollupcEth,
        //    0,
        //    "cETH received is zero"
        //);
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
        uint256 slot = 2; // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }



}
