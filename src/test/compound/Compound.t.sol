// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.6 <0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Compound-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CompoundBridgeContract} from "./../../bridges/compound/CompoundBridge.sol";

interface ICERC20 {
  function accrueInterest() external;
  function approve(address, uint) external returns (uint);
  function balanceOf(address) external view returns (uint256);
  function balanceOfUnderlying(address) external view returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function transfer(address,uint) external returns (uint);
  function mint(uint256) external returns (uint256);
  function redeem(uint) external returns (uint);
  function redeemUnderlying(uint) external returns (uint);
  function underlying() external returns (address);
}

import {AztecTypes} from "./../../aztec/AztecTypes.sol";

interface IComptroller {
  function getAllMarkets() external view returns (ICERC20[] memory);
}

import "../../../lib/ds-test/src/test.sol";


contract CompoundTest is DSTest {
    using SafeMath for uint256;
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    CompoundBridgeContract compoundBridge;

    // Get a list of active cToken contracts and underlying tokens
    IComptroller comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    ICERC20 constant cAAVE  = ICERC20(0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c);
    ICERC20 constant cBAT   = ICERC20(0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E);
    ICERC20 constant cCOMP  = ICERC20(0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4);
    ICERC20 constant cDAI   = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    ICERC20 constant cETH   = ICERC20(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    ICERC20 constant cLINK  = ICERC20(0xFAce851a4921ce59e912d19329929CE6da6EB0c7);
    ICERC20 constant cMKR   = ICERC20(0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b);
    ICERC20 constant cSUSHI = ICERC20(0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7);
    ICERC20 constant cTUSD  = ICERC20(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);
    ICERC20 constant cUNI   = ICERC20(0x35A18000230DA775CAc24873d00Ff85BccdeD550);
    ICERC20 constant cUSDC  = ICERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    ICERC20 constant cUSDP  = ICERC20(0x041171993284df560249B57358F931D9eB7b925D);
    ICERC20 constant cUSDT  = ICERC20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);
    ICERC20 constant cWBTC2 = ICERC20(0xccF4429DB6322D5C611ee964527D42E5d685DD6a);
    ICERC20 constant cYFI   = ICERC20(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946);
    ICERC20 constant cZRX   = ICERC20(0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407);

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
            address(rollupProcessor)
        );
    }

    /* TEST DEPOSIT OF ETH */
    function testCompoundBridgeETH(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0x0000000000000000000000000000000000000000),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cETHaddress,
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

        uint256 rollupcEth = cETH.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcEth,
            0,
            "cETH received is zero"
        );
    }

    /* TEST ALL STABLECOIN DEPOSITS */
    function testCompoundBridgeDAI(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(DAIaddress, address(rollupProcessor), depositAmount);

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

        assertGt(
            rollupcDai,
            0,
            "cDAI received is zero"
        );
    }

    function testCompoundBridgeTUSD(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(TUSDaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: TUSDaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cTUSDaddress,
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

        uint256 rollupcTUSD = cTUSD.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcTUSD,
            0,
            "cTUSD received is zero"
        );
    }
    function testCompoundBridgeUSDC(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(USDCaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: USDCaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cUSDCaddress,
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

        uint256 rollupcUSDC = cUSDC.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcUSDC,
            0,
            "cUSDC received is zero"
        );
    }

    function testCompoundBridgeUSDP(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(USDPaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: USDPaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cUSDPaddress,
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

        uint256 rollupcUSDP = cUSDP.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcUSDP,
            0,
            "cUSDP received is zero"
        );
    }


    function testCompoundBridgeUSDT(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(USDTaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: USDTaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cUSDTaddress,
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

        uint256 rollupcUSDT = cUSDT.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcUSDT,
            0,
            "cUSDT received is zero"
        );
    }

    /* TEST DEPOSIT OF ALL NON-STABLECOIN ASSETS */
    function testCompoundBridgeAAVE(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(AAVEaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: AAVEaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cAAVEaddress,
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

        uint256 rollupcAAVE = cAAVE.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcAAVE,
            0,
            "cAAVE received is zero"
        );
    }

    function testCompoundBridgeBAT(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(BATaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: BATaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cBATaddress,
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

        uint256 rollupcBAT = cBAT.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcBAT,
            0,
            "cBAT received is zero"
        );
    }

    function testCompoundBridgeCOMP(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(COMPaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: COMPaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cCOMPaddress,
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

        uint256 rollupcCOMP = cCOMP.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcCOMP,
            0,
            "cCOMP received is zero"
        );
    }

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    function testCompoundBridgeLINK(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(LINKaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: LINKaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cLINKaddress,
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

        uint256 rollupcLINK = cLINK.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcLINK,
            0,
            "cLINK received is zero"
        );
    }

    function testCompoundBridgeMKR(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(MKRaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: MKRaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cMKRaddress,
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

        uint256 rollupcMKR = cMKR.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcMKR,
            0,
            "cMKR received is zero"
        );
    }

    function testCompoundBridgeSUSHI(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(SUSHIaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: SUSHIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cSUSHIaddress,
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

        uint256 rollupcSUSHI = cSUSHI.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcSUSHI,
            0,
            "cSUSHI received is zero"
        );
    }

    // UNI test contains check that received value matches expected based on exch rate
    function testCompoundBridgeUNI(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(UNIaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: UNIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cUNIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 cUNIrate = cUNI.exchangeRateStored().div(1e18);
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

        uint256 rollupcUNI = cUNI.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcUNI,
            0,
            "cUNI received is zero"
        );
        assertEq(
            rollupcUNI,
            depositAmount.mul(cUNIrate),
            "cUNI received does not match underlying*exchangeRate"
        );
    }

    function testCompoundBridgeWBTC2(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(WBTCaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: WBTCaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cWBTC2address,
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

        uint256 rollupcWBTC2 = cWBTC2.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcWBTC2,
            0,
            "cWBTC2 received is zero"
        );
    }

    function testCompoundBridgeYFI(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(YFIaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: YFIaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cYFIaddress,
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

        uint256 rollupcYFI = cYFI.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcYFI,
            0,
            "cYFI received is zero"
        );
    }

    function testCompoundBridgeZRX(uint256 depositAmount) public {
        if (depositAmount == 0 || depositAmount >= 2**96)
          return;
        vm.deal(address(rollupProcessor), depositAmount);
        _setTokenBalance(ZRXaddress, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: ZRXaddress,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cZRXaddress,
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

        uint256 rollupcZRX = cZRX.balanceOf(address(rollupProcessor));

        assertGt(
            rollupcZRX,
            0,
            "cZRX received is zero"
        );
    }


    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot;
        if (token == USDCaddress)
          slot = 9; // Source: https://blog.coinbase.com/usdc-v2-upgrading-a-multi-billion-dollar-erc-20-token-b57cd9437096
        else if (token == BATaddress)
          slot = 1;
        else if (token == UNIaddress)
          slot = 4;
        else
          slot = 2; // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }



}
