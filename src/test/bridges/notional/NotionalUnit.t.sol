// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {NotionalBridgeContract} from "../../../bridges/notional/NotionalBridge.sol";
import {IWrappedfCashFactory} from "../../../bridges/notional/interfaces/notional/IWrappedfCashFactory.sol";
import {NotionalViews} from "../../../bridges/notional/interfaces/notional/INotionalViews.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

struct Info {
    uint16 currencyId;
    uint40 maturity;
    bool underlying;
    uint256 interactionNonce;
}

contract NotionalTest is BridgeTestBase {
    address public constant ETH = address(0);
    address public constant CETH = address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant CDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant CUSDC = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public constant CWBTC = address(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4);
    mapping(address => bytes32) public balanceOfSlot;
    uint16 public constant ETH_CURRENCYID = 1;
    uint16 public constant DAI_CURRENCYID = 2;
    uint16 public constant USDC_CURRENCYID = 3;
    uint16 public constant WBTC_CURRENCYID = 4;
    IWrappedfCashFactory public constant FCASH_FACTORY =
        IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    AztecTypes.AztecAsset private empty;
    NotionalBridgeContract public bridge;
    NotionalViews public notionalView = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    function setUp() public {
        balanceOfSlot[DAI] = bytes32(uint256(2));
        balanceOfSlot[CETH] = bytes32(uint256(15));
        balanceOfSlot[CDAI] = bytes32(uint256(14));
        balanceOfSlot[WETH] = bytes32(uint256(3));
        balanceOfSlot[USDC] = bytes32(uint256(9));
        balanceOfSlot[CUSDC] = bytes32(uint256(15));
        balanceOfSlot[WBTC] = bytes32(uint256(0));
        balanceOfSlot[CWBTC] = bytes32(uint256(14));

        bridge = new NotionalBridgeContract(address(ROLLUP_PROCESSOR), address(FCASH_FACTORY));
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
    }

    // test whether when we lend eth, we receive wrapper fcash token back
    function testETHLend(uint256 _x) public {
        _x = _convertInput(_x, 1e16, 1e20);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 balance = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        if (balance == 0) {
            revert("receive fcash for lending");
        }
    }

    function testETHWithdrawUnderMaturity(uint256 _x) public {
        _x = _convertInput(_x, 1e16, 1e20);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        info.interactionNonce = 1;
        _lend(_x, ETH, info);
        uint256 prevBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = true;
        info.interactionNonce = 2;
        _withdraw(withdrawAmount, ETH, CETH, info);
        uint256 redeemedBalance = address(ROLLUP_PROCESSOR).balance - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testETHLendAtAnyTimeWithdraw(uint256 _x, uint256 _time) public {
        _time = _time > 60 days ? 60 days : _time;
        vm.warp(block.timestamp + _time);
        _x = _convertInput(_x, 1e16, 1e20);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        info.interactionNonce = 1;
        _lend(_x, ETH, info);
        uint256 prevBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = true;
        info.interactionNonce = 2;
        _withdraw(withdrawAmount, ETH, CETH, info);
        uint256 redeemedBalance = address(ROLLUP_PROCESSOR).balance - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testETHLendTwiceAndWithdraw(uint256 _x) public {
        _x = _convertInput(_x, 1e16, 1e20);
        // first lend
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        uint40 firstMaturity = info.maturity;
        address firstFcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 firstLendFcashTokenAmt = ERC20(firstFcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        vm.warp(block.timestamp + 30 days);
        // second lend after a month
        info.interactionNonce = 2;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        uint40 secondMaturity = info.maturity;
        address secondFcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 balance = address(ROLLUP_PROCESSOR).balance;
        info.maturity = firstMaturity;
        info.underlying = true;
        info.interactionNonce = 3;
        _withdraw(firstLendFcashTokenAmt, ETH, CETH, info);
        uint256 secondLendFCashTokenAmt = ERC20(secondFcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 firstWithdrawETH = address(ROLLUP_PROCESSOR).balance - balance;
        info.maturity = secondMaturity;
        info.interactionNonce = 4;
        _withdraw(secondLendFCashTokenAmt, ETH, CETH, info);
        uint256 secondWithdrawETH = address(ROLLUP_PROCESSOR).balance - firstWithdrawETH - balance;
        if (firstWithdrawETH < secondWithdrawETH) {
            revert("should incur more eth interest");
        }
<<<<<<< HEAD
<<<<<<< HEAD
        if ((secondWithdrawETH * 10000) / _x < 9900) {
=======
        if(secondWithdrawETH * 10000 / _x < 9900) {
>>>>>>> 70661815 (add notional bridge)
=======
        if(secondWithdrawETH * 10000 / _x < 9900) {
>>>>>>> 6be78da2 (add notional bridge)
            revert("should take most of money back");
        }
    }

    function testETHWithdrawOverMaturity(uint256 _x) public {
        _x = _convertInput(_x, 1e16, 1e20);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 prevBalance = address(ROLLUP_PROCESSOR).balance;
        vm.warp(block.timestamp + 90 days);
        info.underlying = true;
        info.interactionNonce = 2;
        _withdraw(withdrawAmount, ETH, CETH, info);
        uint256 redeemedBalance = address(ROLLUP_PROCESSOR).balance - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testETHPartialWithdraw(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e16, 1e20);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 prevBalance = address(ROLLUP_PROCESSOR).balance;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        info.underlying = true;
        info.interactionNonce = 2;
        _withdraw(withdrawAmount / 2, ETH, CETH, info);
        uint256 redeemedBalance = address(ROLLUP_PROCESSOR).balance - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / (_x / 2) < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) < withdrawAmount / 2) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / (_x/2) < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) < withdrawAmount/2 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("should still have fcash");
        }
    }

    function testCETHLendithdrawCETH(uint256 _x) public {
        _x = _convertInput(_x, 1e8, 1e12);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, CETH, info);
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        vm.warp(block.timestamp + 90 days);
        info.underlying = false;
        info.interactionNonce = 2;
        uint256 prevBalance = ERC20(CETH).balanceOf(address(ROLLUP_PROCESSOR));
        _withdraw(withdrawAmount, ETH, CETH, info);
<<<<<<< HEAD
<<<<<<< HEAD
        uint256 redeemedBalance = ERC20(CETH).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        uint redeemedBalance = ERC20(CETH).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testCDAILend(uint256 _x) public {
        _x = _convertInput(_x, 1e9, 1e15);
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, CDAI, info);
        uint256 balance = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        if (balance == 0) {
            revert("receive fcash for lending");
        }
    }

    function testCDAILendwithdrawCDAI(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e9, 1e12);
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, CDAI, info);
        uint256 prevBalance = ERC20(CDAI).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = false;
        info.interactionNonce = 2;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        _withdraw(withdrawAmount, DAI, CDAI, info);
        uint256 redeemedBalance = ERC20(CDAI).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testDAIWithdraw(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e18, 1e21);
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, DAI, info);
        uint256 prevBalance = ERC20(DAI).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = true;
        info.interactionNonce = 2;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        _withdraw(withdrawAmount, DAI, CDAI, info);
        uint256 redeemedBalance = ERC20(DAI).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testUSDCLend(uint256 _x) public {
        _x = _convertInput(_x, 1e6, 1e10);
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, USDC, info);
        uint256 balance = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        if (balance == 0) {
            revert("receive fcash for lending");
        }
    }

    function testCUSDCLendWithdrawCUSDC(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e9, 1e12);
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, CUSDC, info);
        uint256 prevBalance = ERC20(CUSDC).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = false;
        info.interactionNonce = 2;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        _withdraw(withdrawAmount, USDC, CUSDC, info);
        uint256 redeemedBalance = ERC20(CUSDC).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testUSDCWithdraw(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e6, 1e10);
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, USDC, info);
        uint256 prevBalance = ERC20(USDC).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = true;
        info.interactionNonce = 2;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        _withdraw(withdrawAmount, USDC, CUSDC, info);
        uint256 redeemedBalance = ERC20(USDC).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function testWBTCLend(uint256 _x) public {
        _x = _convertInput(_x, 1e6, 1e9);
        Info memory info;
        info.currencyId = WBTC_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, WBTC, info);
        uint256 balance = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        if (balance == 0) {
            revert("receive fcash for lending");
        }
    }

    function testWBTCWithdraw(uint256 _x, bool _overMaturity) public {
        _x = _convertInput(_x, 1e6, 1e9);
        Info memory info;
        info.currencyId = WBTC_CURRENCYID;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, WBTC, info);
        uint256 prevBalance = ERC20(WBTC).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        info.underlying = true;
        info.interactionNonce = 2;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        _withdraw(withdrawAmount, WBTC, CWBTC, info);
        uint256 redeemedBalance = ERC20(WBTC).balanceOf(address(ROLLUP_PROCESSOR)) - prevBalance;
<<<<<<< HEAD
<<<<<<< HEAD
        if ((redeemedBalance * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0) {
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
        if(redeemedBalance * 10000 / _x < 9900) {
            revert("should take most of money back");
        }
        if(ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) != 0 ) {
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
            revert("fcash should be burned");
        }
    }

    function _lend(
        uint256 _inputAmount,
        address _lendToken,
        Info memory _info
    ) internal {
        AztecTypes.AztecAsset memory inputAsset;
        AztecTypes.AztecAsset memory outputAsset;
        bool isLendETH = _lendToken == address(0);
        if (isLendETH) {
            vm.deal(address(ROLLUP_PROCESSOR), _inputAmount + 1 ether);
        } else {
            deal(_lendToken, address(bridge), _inputAmount);
            vm.deal(address(ROLLUP_PROCESSOR), 1 ether);
        }
        uint256 balance = isLendETH ? _inputAmount : ERC20(_lendToken).balanceOf(address(bridge));
        inputAsset.assetType = isLendETH ? AztecTypes.AztecAssetType.ETH : AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = _lendToken;
        uint64 auxData = uint64(_info.maturity);
        outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        outputAsset.erc20Address = FCASH_FACTORY.computeAddress(_info.currencyId, _info.maturity);
        vm.prank(address(ROLLUP_PROCESSOR));
        uint256 fcashAmount;
        if (isLendETH) {
            (fcashAmount, , ) = bridge.convert{value: _inputAmount}(
                inputAsset,
                empty,
                outputAsset,
                empty,
                balance,
                _info.interactionNonce,
                auxData,
                address(0)
            );
        } else {
            (fcashAmount, , ) = bridge.convert(
                inputAsset,
                empty,
                outputAsset,
                empty,
                balance,
                _info.interactionNonce,
                auxData,
                address(0)
            );
        }
        vm.prank(address(ROLLUP_PROCESSOR));
        ERC20(outputAsset.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), fcashAmount);
    }

    function _withdraw(
        uint256 _withdrawAmount,
        address _underlyingAddr,
        address _ctoken,
        Info memory _info
    ) internal {
        AztecTypes.AztecAsset memory inputAsset;
        AztecTypes.AztecAsset memory outputAsset;
        address fcashToken = FCASH_FACTORY.computeAddress(_info.currencyId, _info.maturity);
        inputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        uint64 auxData = 0;
        if (_info.underlying) {
            outputAsset.erc20Address = _underlyingAddr;
            if (_underlyingAddr == address(0)) {
                outputAsset.assetType = AztecTypes.AztecAssetType.ETH;
            }
        } else {
            outputAsset.erc20Address = _ctoken;
        }
        vm.prank(address(ROLLUP_PROCESSOR));
        ERC20(fcashToken).transfer(address(bridge), _withdrawAmount);
        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputAmount, , ) = bridge.convert(
            inputAsset,
            empty,
            outputAsset,
            empty,
            _withdrawAmount,
            _info.interactionNonce,
            auxData,
            address(0)
        );
        if (outputAsset.assetType == AztecTypes.AztecAssetType.ERC20) {
            vm.prank(address(ROLLUP_PROCESSOR));
            ERC20(outputAsset.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), outputAmount);
        }
    }

    function _convertInput(
        uint256 _x,
        uint256 _lowerBound,
        uint256 _upperBound
    ) internal pure returns (uint256) {
        _x = _x > _lowerBound ? _x : _lowerBound;
        _x = _x < _upperBound ? _x : _upperBound;
        return _x;
    }
}
