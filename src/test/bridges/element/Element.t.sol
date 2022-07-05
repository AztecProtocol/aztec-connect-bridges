// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {stdStorage} from "forge-std/Test.sol";
import {StdStorage} from "forge-std/Test.sol";

<<<<<<< HEAD:src/test/bridges/element/Element.t.sol
import {DefiBridgeProxy} from "./aztecmocks/DefiBridgeProxy.sol";
import {RollupProcessor} from "./aztecmocks/RollupProcessor.sol";
=======
import {DefiBridgeProxy} from "../../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "../../../aztec/RollupProcessor.sol";
>>>>>>> de3f647e... pull master from upstream and merge:src/test/element/Element.t.sol

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ElementBridge} from "../../../bridges/element/ElementBridge.sol";
import {ITranche} from "../../../interfaces/element/ITranche.sol";
import {IPool} from "../../../interfaces/element/IPool.sol";
import {IWrappedPosition} from "../../../interfaces/element/IWrappedPosition.sol";
import {MockDeploymentValidator} from "./MockDeploymentValidator.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// @dev Note: these tests are deprecated and will be replaced once Element v2 is released
contract ElementTest is Test {
    using stdStorage for StdStorage;

    struct TrancheConfig {
        string asset;
        address trancheAddress;
        address poolAddress;
        uint64 expiry;
    }

    struct Interaction {
        TrancheConfig tranche;
        uint256 depositAmount;
        uint256 nonce;
        uint256 outputValue;
    }

    struct Balances {
        uint256 startingAsset;
        uint256 bridgeTranche;
        uint256 balancerAsset;
        uint256 balancerTranche;
    }

    address private constant BALANCER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 private constant BYTE_CODE_HASH = 0xf481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d;
    address private constant TRANCHE_FACTORY_ADDRESS = 0x62F161BF3692E4015BefB05A03a94A40f520d1c0;

    int64 private constant DAI_CONVERT_GAS = 237914;
    int64 private constant USDC_FINALISE_GAS = 224810;

    uint256[] private timestamps = [
        1640995200, //Jan 01 2022
        1643673600, //Feb 01 2022
        1644601070,
        1646092800, //Mar 01 2022
        1648771200, //Apr 01 2022
        1651275535, // max expiry
        1651363200 //May 01 2022
    ];

    uint256[] private expiries = [
        1643382446,
        1643382460,
        1643382476,
        1643382514,
        1644601070,
        //1644604852, commented out becuase these tranches are not used
        1650025565,
        1651240496,
        1651247155,
        //1651264326,
        1651265241,
        1651267340,
        1651275535
    ];

    StdStorage private stdStore;

    mapping(string => TrancheConfig[]) private trancheConfigs;
    mapping(string => IERC20) private tokens;
    mapping(string => address) private wrappedPositions;
    mapping(string => uint256) private quantities;

    mapping(address => uint256) private totalReceiptByTranche;
    mapping(address => uint256) private bridgeBalanceByTranche;

    string[] private assets;

    AztecTypes.AztecAsset private emptyAsset;
    uint256 private numTranches = 0;

    // solhint-disable-next-line
    RollupProcessor private rollupProcessor;
    MockDeploymentValidator private elementDeploymentValidator;

    ElementBridge private elementBridge;

    event LogConvert(uint256 indexed nonce, uint256 totalInputValue, int64 gasUsed);

    event LogFinalise(uint256 indexed nonce, bool success, string message, int64 gasUsed);

    event LogPoolAdded(address poolAddress, address wrappedPositionAddress, uint64 expiry);

    function setUp() public {
        rollupProcessor = new RollupProcessor(address(new DefiBridgeProxy()));
        elementDeploymentValidator = new MockDeploymentValidator();

        tokens["USDC"] = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        tokens["WETH"] = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        tokens["DAI"] = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        tokens["LUSD3CRV-F"] = IERC20(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
        tokens["CRVTRICRYPTO"] = IERC20(0xcA3d75aC011BF5aD07a98d02f18225F9bD9A6BDF);
        tokens["STECRV"] = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
        tokens["CRV3CRYPTO"] = IERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
        tokens["WBTC"] = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        tokens["ALUSD3CRV-F"] = IERC20(0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c);
        tokens["MIM-3LP3CRV-F"] = IERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B);
        tokens["EURSCRV"] = IERC20(0x194eBd173F6cDacE046C53eACcE9B953F28411d1);

        wrappedPositions["USDC"] = 0xdEa04Ffc66ECD7bf35782C70255852B34102C3b0;
        wrappedPositions["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        wrappedPositions["DAI"] = 0x21BbC083362022aB8D7e42C18c47D484cc95C193;
        wrappedPositions["LUSD3CRV-F"] = 0x53b1aEAa018da00b4F458Cc13d40eB3e8d1B85d6;
        wrappedPositions["CRVTRICRYPTO"] = 0x97278Ce17D4860f8f49afC6E4c1C5AcBf2584cE5;
        wrappedPositions["STECRV"] = 0xB3295e739380BD68de96802F7c4Dba4e54477206;
        wrappedPositions["CRV3CRYPTO"] = 0x4F424B26c7c659F198797Bd87282BF602F543521;
        wrappedPositions["WBTC"] = 0x8D9487b81e0fEdcd2D8Cab91885756742375CDC5;
        wrappedPositions["ALUSD3CRV-F"] = 0x3b5Dbd685C7ad66f8D3A82E2134320eD74DA4Af2;
        wrappedPositions["MIM-3LP3CRV-F"] = 0x270f63b67FF1Ca770D60684366B009A566170AdD;
        wrappedPositions["EURSCRV"] = 0xb601610553071209443Fbae6E71b8dE4Ba78643b;

        quantities["USDC"] = 1e6;
        quantities["WETH"] = 1e15;
        quantities["DAI"] = 1e15;
        quantities["LUSD3CRV-F"] = 1e3;
        quantities["CRVTRICRYPTO"] = 1e15;
        quantities["STECRV"] = 1e6;
        quantities["CRV3CRYPTO"] = 1e15;
        quantities["WBTC"] = 1e5;
        quantities["ALUSD3CRV-F"] = 1e15;
        quantities["MIM-3LP3CRV-F"] = 1e15;
        quantities["EURSCRV"] = 1e15;

        _addTrancheConfig(
            "USDC",
            0x8a2228705ec979961F0e16df311dEbcf097A2766,
            0x10a2F8bd81Ee2898D7eD18fb8f114034a549FA59,
            1643382476
        );

        _addTrancheConfig(
            "DAI",
            0x449D7C2e096E9f867339078535b15440d42F78E8,
            0xA47D1251CF21AD42685Cc6B8B3a186a73Dbd06cf,
            1643382446
        );
        _addTrancheConfig(
            "DAI",
            0x2c72692E94E757679289aC85d3556b2c0f717E0E,
            0xEdf085f65b4F6c155e13155502Ef925c9a756003,
            1651275535
        );

        _addTrancheConfig(
            "STECRV",
            0x720465A4AE6547348056885060EEB51F9CAdb571,
            0x544c823194218f0640daE8291c1f59752d25faE3,
            1643382514
        );
        _addTrancheConfig(
            "STECRV",
            0x2361102893CCabFb543bc55AC4cC8d6d0824A67E,
            0xb03C6B351A283bc1Cd26b9cf6d7B0c4556013bDb,
            1650025565
        );

        _addTrancheConfig(
            "WBTC",
            0x49e9e169f0B661Ea0A883f490564F4CC275123Ed,
            0x4bd6D86dEBdB9F5413e631Ad386c4427DC9D01B2,
            1651265241
        );

        _addTrancheConfig(
            "ALUSD3CRV-F",
            0xEaa1cBA8CC3CF01a92E9E853E90277B5B8A23e07,
            0x63E9B50DD3eB63BfBF93B26F57b9EFB574e59576,
            1651267340
        );
        _addTrancheConfig(
            "ALUSD3CRV-F",
            0x55096A35Bf827919B3Bb0A5e6b5E2af8095F3D4d,
            0xC9AD279994980F8DF348b526901006972509677F,
            1643382460
        );

        //addTrancheConfig('EURSCRV', 0x2A8f5649DE50462fF9699Ccc75A2Fb0b53447503, 0x6AC02eCD0c2A23B11f9AFb3b3Aaf237169475cac, 1644604852);
        //addTrancheConfig('LUSD3CRV-F', 0x0740A6CfB9468B8b53070C0B327099293DCCB82d, 0x56F30398d13F111401d6e7ffE758254a0946687d, 1651264326);
        _addTrancheConfig(
            "CRV3CRYPTO",
            0x285328906D0D33cb757c1E471F5e2176683247c2,
            0x6Dd0F7c8F4793ed2531c0df4fEA8633a21fDcFf4,
            1651240496
        );

        _addTrancheConfig(
            "MIM-3LP3CRV-F",
            0x418De6227499181B045CAdf554030722E460881a,
            0x09b1b33BaD0e87454ff05696b1151BFbD208a43F,
            1644601070
        );
        _addTrancheConfig(
            "MIM-3LP3CRV-F",
            0xC63958D9D01eFA6B8266b1df3862c6323CbDb52B,
            0x14792d3F6FcF2661795d1E08ef818bf612708BbF,
            1651247155
        );

        elementBridge = new ElementBridge(
            address(rollupProcessor),
            TRANCHE_FACTORY_ADDRESS,
            BYTE_CODE_HASH,
            BALANCER,
            address(elementDeploymentValidator)
        );

        rollupProcessor.setBridgeGasLimit(address(elementBridge), 700000);

        vm.warp(timestamps[0]);
    }

    function testCanConfigurePool() public {
        TrancheConfig storage config = trancheConfigs["USDC"][0];

        elementDeploymentValidator.validateWPAddress(wrappedPositions["USDC"]);
        elementDeploymentValidator.validatePoolAddress(config.poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPositions["USDC"], config.poolAddress);

        vm.expectEmit(false, false, false, true);
        emit LogPoolAdded(config.poolAddress, wrappedPositions["USDC"], config.expiry);

        elementBridge.registerConvergentPoolAddress(config.poolAddress, wrappedPositions["USDC"], config.expiry);
    }

    function testCanConfigureSamePoolMultipleTimes() public {
        TrancheConfig storage config = trancheConfigs["USDC"][0];

        elementDeploymentValidator.validateWPAddress(wrappedPositions["USDC"]);
        elementDeploymentValidator.validatePoolAddress(config.poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPositions["USDC"], config.poolAddress);

        vm.expectEmit(false, false, false, true);
        emit LogPoolAdded(config.poolAddress, wrappedPositions["USDC"], config.expiry);

        elementBridge.registerConvergentPoolAddress(config.poolAddress, wrappedPositions["USDC"], config.expiry);

        elementBridge.registerConvergentPoolAddress(config.poolAddress, wrappedPositions["USDC"], config.expiry);

        elementBridge.registerConvergentPoolAddress(config.poolAddress, wrappedPositions["USDC"], config.expiry);
    }

    function testCanConfigureMultiplePools() public {
        elementDeploymentValidator.validateWPAddress(wrappedPositions["USDC"]);
        elementDeploymentValidator.validateWPAddress(wrappedPositions["DAI"]);
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["USDC"][0].poolAddress);
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][0].poolAddress);
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][1].poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPositions["USDC"], trancheConfigs["USDC"][0].poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPositions["DAI"], trancheConfigs["DAI"][0].poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPositions["DAI"], trancheConfigs["DAI"][1].poolAddress);

        vm.expectEmit(false, false, false, true);
        emit LogPoolAdded(
            trancheConfigs["USDC"][0].poolAddress,
            wrappedPositions["USDC"],
            trancheConfigs["USDC"][0].expiry
        );

        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["USDC"][0].poolAddress,
            wrappedPositions["USDC"],
            trancheConfigs["USDC"][0].expiry
        );

        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );

        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][1].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][1].expiry
        );
    }

    function testRejectsWrongExpiryForPool() public {
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.POOL_EXPIRY_MISMATCH.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][1].expiry // expiry is for a different pool to
        );
    }

    function testRejectsIncorrectWrappedPositionForPool() public {
        vm.expectRevert(bytes(""));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["USDC"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsInvalidWrappedPosition() public {
        vm.expectRevert(bytes(""));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            _randomAddress(),
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsInvalidPoolAddress() public {
        vm.expectRevert(bytes(""));
        elementBridge.registerConvergentPoolAddress(
            _randomAddress(),
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPoolAddress() public {
        // register position but not pool
        elementDeploymentValidator.validateWPAddress(wrappedPositions["DAI"]);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_POOL.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPositionAddress() public {
        // register pool but not position
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][0].poolAddress);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_POSITION.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPositionAndPoolAddresses() public {
        // register neither address, pool is validated first
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_POOL.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPairAddresses() public {
        // register both the pool and position but not as a pair
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][0].poolAddress);
        elementDeploymentValidator.validateWPAddress(wrappedPositions["DAI"]);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_PAIR.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPairAddresses2() public {
        // register DAI position
        elementDeploymentValidator.validateWPAddress(wrappedPositions["DAI"]);
        // register both DAI pools
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][0].poolAddress);
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][1].poolAddress);

        // register second DAI pair
        elementDeploymentValidator.validateAddresses(wrappedPositions["DAI"], trancheConfigs["DAI"][1].poolAddress);

        // the first DAI pair isn't registered and should revert
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_PAIR.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][0].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][0].expiry
        );
    }

    function testRejectsUnregisteredPairAddresses3() public {
        // register DAI position
        elementDeploymentValidator.validateWPAddress(wrappedPositions["DAI"]);
        // register both DAI pools
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][0].poolAddress);
        elementDeploymentValidator.validatePoolAddress(trancheConfigs["DAI"][1].poolAddress);

        // register first DAI pair
        elementDeploymentValidator.validateAddresses(wrappedPositions["DAI"], trancheConfigs["DAI"][0].poolAddress);

        // the second DAI pair isn't registered and should revert
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.UNREGISTERED_PAIR.selector));
        elementBridge.registerConvergentPoolAddress(
            trancheConfigs["DAI"][1].poolAddress,
            wrappedPositions["DAI"],
            trancheConfigs["DAI"][1].expiry
        );
    }

    function testShouldRejectVirtualAsset() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.ASSET_NOT_ERC20.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectInputAssetBNotUnused() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.INPUT_ASSETB_NOT_UNUSED.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            inputAssetB,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectOutputAssetBNotUnused() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.OUTPUT_ASSETB_NOT_UNUSED.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            outputAssetB,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectEthAsset() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.ASSET_NOT_ERC20.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectAlreadyExpired() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.warp(trancheConfigs["DAI"][0].expiry);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.TRANCHE_ALREADY_EXPIRED.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectUnusedAsset() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.ASSET_NOT_ERC20.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectInconsistentAssetIds() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.ASSET_IDS_NOT_EQUAL.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectNonRollupCaller() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ErrorLib.InvalidCaller.selector));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][0].expiry,
            address(0)
        );
    }

    function testShouldRejectInconsistentPool() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.POOL_NOT_FOUND.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["USDC"][0].expiry, // USDC expiry will not work with DAI asset
            address(0)
        );
    }

    function testShouldRejectInconsistentPool2() public {
        _setupConvergentPool(trancheConfigs["DAI"][0]);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;
        _setTokenBalance("DAI", address(elementBridge), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ElementBridge.POOL_NOT_FOUND.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            trancheConfigs["DAI"][1].expiry, // The second DAI expiry hasn't been registered
            address(0)
        );
    }

    function testCanConvert() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]);
        Interaction memory interactionConfig = Interaction(config, 15000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        uint256 balancerBefore = tokens["DAI"].balanceOf(address(BALANCER));
        vm.expectEmit(false, false, false, true);
        emit LogConvert(interactionConfig.nonce, interactionConfig.depositAmount, DAI_CONVERT_GAS);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        uint256 balancerAfter = tokens["DAI"].balanceOf(address(BALANCER));
        assertEq(balancerBefore + interactionConfig.depositAmount, balancerAfter, "Balances must match");
        _assertZeroBalance(address(elementBridge), address(tokens["DAI"]));
        _assertNonZeroBalance(address(elementBridge), interactionConfig.tranche.trancheAddress);
    }

    function testCanRetrieveTrancheDeploymentBlockNumber() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]);
        Interaction memory interactionConfig = Interaction(config, 15000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        tokens["DAI"].balanceOf(BALANCER);
        vm.expectEmit(false, false, false, true);
        emit LogConvert(interactionConfig.nonce, interactionConfig.depositAmount, DAI_CONVERT_GAS);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);

        // now retrieve the tranche's deployment block number based on the interaction nonce
        uint256 blockNumber = elementBridge.getTrancheDeploymentBlockNumber(interactionConfig.nonce);
        assertEq(blockNumber, block.number); // block.number = convergentPoolBlockNumber
    }

    function testRetrieveTrancheDeploymentBlockNumberFailsForInvalidNonce() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        _setupConvergentPool(config);

        // unknown nonce should revert
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.InvalidNonce.selector));
        elementBridge.getTrancheDeploymentBlockNumber(12345);
    }

    function testRejectConvertDuplicateNonce() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]);
        Interaction memory interactionConfig = Interaction(config, 15000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount * 2);
        tokens["DAI"].balanceOf(address(BALANCER));
        vm.expectEmit(false, false, false, true);
        emit LogConvert(interactionConfig.nonce, interactionConfig.depositAmount, DAI_CONVERT_GAS);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.INTERACTION_ALREADY_EXISTS.selector));
        _callElementConvert("DAI", interactionConfig);
    }

    function testRejectFinaliseInvalidCaller() public {
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.InvalidCaller.selector));
        elementBridge.finalise(asset, emptyAsset, asset, emptyAsset, 1, trancheConfigs["DAI"][0].expiry);
    }

    function testRejectFinaliseInvalidNonce() public {
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.InvalidNonce.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(asset, emptyAsset, asset, emptyAsset, 6, trancheConfigs["DAI"][0].expiry);
    }

    function testCanRegisterAllPools() public {
        _setupAllPools();
    }

    function testRejectFinaliseNotReady() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]);
        Interaction memory interactionConfig = Interaction(config, 15000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.BRIDGE_NOT_READY.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(asset, emptyAsset, asset, emptyAsset, 6, config.expiry);
    }

    function testCanFinaliseDaiJan22() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]); // Jan 01 2022
        Interaction memory interactionConfig = Interaction(config, 15000000000000000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        // warp to just after the tranche expiry
        vm.warp(interactionConfig.tranche.expiry + 1);
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(
            asset,
            emptyAsset,
            asset,
            emptyAsset,
            interactionConfig.nonce,
            interactionConfig.tranche.expiry
        );
        _assertZeroBalance(address(elementBridge), interactionConfig.tranche.trancheAddress);
        _assertBalanceGt(address(elementBridge), address(tokens["DAI"]), interactionConfig.depositAmount);
    }

    function testCanFinaliseDaiApr22() public {
        TrancheConfig storage config = trancheConfigs["DAI"][1];
        vm.warp(timestamps[0]); // Jan 01 2022
        Interaction memory interactionConfig = Interaction(config, 15000000000000000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        // warp to just after the tranche expiry
        vm.warp(interactionConfig.tranche.expiry + 1);
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(
            asset,
            emptyAsset,
            asset,
            emptyAsset,
            interactionConfig.nonce,
            interactionConfig.tranche.expiry
        );
        _assertZeroBalance(address(elementBridge), interactionConfig.tranche.trancheAddress);
        _assertBalanceGt(address(elementBridge), address(tokens["DAI"]), interactionConfig.depositAmount);
    }

    function testRejectAlreadyFinalised() public {
        TrancheConfig storage config = trancheConfigs["DAI"][0];
        vm.warp(timestamps[0]); // Jan 01 2022
        Interaction memory interactionConfig = Interaction(config, 15000000000000000, 6, 0);
        _setupConvergentPool(config);
        _setTokenBalance("DAI", address(elementBridge), interactionConfig.depositAmount);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert("DAI", interactionConfig);
        assertEq(isAsync, true);
        assertEq(outputValueA, 0);
        assertEq(outputValueB, 0);
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        // warp to just after the tranche expiry
        vm.warp(interactionConfig.tranche.expiry + 1);
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(asset, emptyAsset, asset, emptyAsset, interactionConfig.nonce, config.expiry);
        _assertZeroBalance(address(elementBridge), interactionConfig.tranche.trancheAddress);
        _assertBalanceGt(address(elementBridge), address(tokens["DAI"]), interactionConfig.depositAmount);
        vm.expectRevert(abi.encodeWithSelector(ElementBridge.ALREADY_FINALISED.selector));
        vm.prank(address(rollupProcessor));
        elementBridge.finalise(asset, emptyAsset, asset, emptyAsset, interactionConfig.nonce, config.expiry);
    }

    function testCanProcessAllExpiries() public {
        _setupAllPools();
        uint256 numInteractionsPerExpiry = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        Interaction[] memory interactions = new Interaction[](numTranches * numInteractionsPerExpiry);
        uint256 nonce = 1;
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            _increaseTokenBalance(asset, address(elementBridge), depositAmount * configs.length * 15);
            for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
                for (uint256 interactionCount = 0; interactionCount < numInteractionsPerExpiry; interactionCount++) {
                    TrancheConfig storage config = configs[configIndex];
                    Interaction memory interaction = Interaction(
                        config,
                        depositAmount * depositMultipliers[interactionCount],
                        nonce,
                        0
                    );
                    interactions[nonce - 1] = interaction;
                    Balances memory balancesBefore = _getBalances(interaction, address(elementBridge));
                    (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert(
                        asset,
                        interaction
                    );
                    assertEq(isAsync, true);
                    assertEq(outputValueA, 0);
                    assertEq(outputValueB, 0);
                    Balances memory balancesAfter = _getBalances(interaction, address(elementBridge));
                    assertEq(
                        balancesBefore.startingAsset - balancesAfter.startingAsset,
                        balancesAfter.balancerAsset - balancesBefore.balancerAsset,
                        "asset balance"
                    );
                    assertEq(
                        balancesBefore.balancerTranche - balancesAfter.balancerTranche,
                        balancesAfter.bridgeTranche - balancesBefore.bridgeTranche,
                        "tranche balance"
                    );
                    nonce++;
                }
            }
        }
        vm.warp(expiries[expiries.length - 1] + 1);

        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            Balances memory balancesBefore = _getBalances(interaction, address(elementBridge));
            (uint256 outputValueA, uint256 outputValueB, bool interactionCompleted) = _callElementFinalise(interaction);
            assertEq(interactionCompleted, true);
            assertEq(outputValueB, 0);
            assertGt(outputValueA, interaction.depositAmount);
            Balances memory balancesAfter = _getBalances(interaction, address(elementBridge));
            if (bridgeBalanceByTranche[interaction.tranche.trancheAddress] == 0) {
                uint256 balanceMovedToBridge = balancesAfter.startingAsset - balancesBefore.startingAsset;
                uint256 totalDeposit = 15 * quantities[interaction.tranche.asset];
                assertGt(balanceMovedToBridge, totalDeposit);
                bridgeBalanceByTranche[interaction.tranche.trancheAddress] = balanceMovedToBridge;
            }
            // accumulate the amount received by asset
            totalReceiptByTranche[interaction.tranche.trancheAddress] += outputValueA;
            interaction.outputValue = outputValueA;
        }

        // now verify that each interaction received the same proportion of the output as it gave in deposit
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            uint256 percentOfDeposit = (interaction.depositAmount * 100) / (15 * quantities[interaction.tranche.asset]);
            uint256 totalReceipt = totalReceiptByTranche[interaction.tranche.trancheAddress];
            uint256 percentOfReceipt = (interaction.outputValue * 100) / totalReceipt;
            int256 diff = int256(percentOfDeposit) - int256(percentOfReceipt);
            uint256 absDiff = diff >= 0 ? uint256(diff) : uint256(-diff);
            assertLt(absDiff, 2);
        }

        // verify rollup and bridge contract token quantities
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            uint256 totalDeposited = depositAmount * configs.length;
            uint256 assetInBridge = tokens[asset].balanceOf(address(elementBridge));
            assertGt(assetInBridge, totalDeposited);
        }
    }

    function testCanFinaliseInteractionsOutOfOrder() public {
        _setupAllPools();
        uint256 numInteractionsPerExpiry = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        // deposit 5 interactions against every expiry
        Interaction[] memory interactions = new Interaction[](numTranches * numInteractionsPerExpiry);
        uint256 nonce = 1;
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            _increaseTokenBalance(asset, address(elementBridge), depositAmount * configs.length * 15);
            for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
                for (uint256 interactionCount = 0; interactionCount < numInteractionsPerExpiry; interactionCount++) {
                    TrancheConfig storage config = configs[configIndex];
                    Interaction memory interaction = Interaction(
                        config,
                        depositAmount * depositMultipliers[interactionCount],
                        nonce,
                        0
                    );
                    interactions[nonce - 1] = interaction;
                    Balances memory balancesBefore = _getBalances(interaction, address(elementBridge));
                    (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callElementConvert(
                        asset,
                        interaction
                    );
                    assertEq(isAsync, true);
                    assertEq(outputValueA, 0);
                    assertEq(outputValueB, 0);
                    Balances memory balancesAfter = _getBalances(interaction, address(elementBridge));
                    assertEq(
                        balancesBefore.startingAsset - balancesAfter.startingAsset,
                        balancesAfter.balancerAsset - balancesBefore.balancerAsset,
                        "asset balance"
                    );
                    assertEq(
                        balancesBefore.balancerTranche - balancesAfter.balancerTranche,
                        balancesAfter.bridgeTranche - balancesBefore.bridgeTranche,
                        "tranche balance"
                    );
                    nonce++;
                }
            }
        }
        vm.warp(expiries[expiries.length - 1] + 1);

        // we are now going to call finalise on every interaction
        // but we are going to do it out of order
        // we will find the middle expiry value
        // then get the interactions for that expiry and finalise them one at a time using the middle interaction of the set
        // keep doing this until all interactions are finalised
        uint256[] memory expiriesCopy = new uint256[](expiries.length);
        for (uint256 i = 0; i < expiries.length; i++) {
            expiriesCopy[i] = expiries[i];
        }

        uint256 numExpiries = expiriesCopy.length;
        while (numExpiries != 0) {
            // us the middle expiry and shuffle the rest down
            uint256 midExpiry = numExpiries / 2;
            uint64 currentExpiry = uint64(expiriesCopy[midExpiry]);
            for (uint256 i = midExpiry + 1; i < numExpiries; i++) {
                expiriesCopy[i - 1] = expiriesCopy[i];
            }
            numExpiries--;
            // we now have the expiry we wish to work with
            // get the set of interactions for this expiry
            Interaction[] memory interactionsForThisExpiry = new Interaction[](numInteractionsPerExpiry);
            uint256 nextInteractionIndex = 0;
            for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
                Interaction memory interaction = interactions[interactionIndex];
                if (interaction.tranche.expiry == currentExpiry) {
                    interactionsForThisExpiry[nextInteractionIndex] = interaction;
                    nextInteractionIndex++;
                }
            }
            if (nextInteractionIndex == 0) {
                continue;
            }
            // we now have the set of interactions we would like to finalise
            uint256 numInteractions = interactionsForThisExpiry.length;
            while (numInteractions != 0) {
                // use the middle interaction and shuffle the rest down
                uint256 midInteraction = numInteractions / 2;
                Interaction memory currentInteraction = interactionsForThisExpiry[midInteraction];
                for (uint256 i = midInteraction + 1; i < numInteractions; i++) {
                    interactionsForThisExpiry[i - 1] = interactionsForThisExpiry[i];
                }
                numInteractions--;
                // now finalise this interaction
                Balances memory balancesBefore = _getBalances(currentInteraction, address(elementBridge));
                (uint256 outputValueA, uint256 outputValueB, bool interactionCompleted) = _callElementFinalise(
                    currentInteraction
                );
                assertEq(interactionCompleted, true);
                assertEq(outputValueB, 0);
                assertGt(outputValueA, currentInteraction.depositAmount);
                Balances memory balancesAfter = _getBalances(currentInteraction, address(elementBridge));
                if (bridgeBalanceByTranche[currentInteraction.tranche.trancheAddress] == 0) {
                    uint256 balanceMovedToBridge = balancesAfter.startingAsset - balancesBefore.startingAsset;
                    uint256 totalDeposit = 15 * quantities[currentInteraction.tranche.asset];
                    assertGt(balanceMovedToBridge, totalDeposit);
                    bridgeBalanceByTranche[currentInteraction.tranche.trancheAddress] = balanceMovedToBridge;
                }
                // accumulate the amount received by asset
                totalReceiptByTranche[currentInteraction.tranche.trancheAddress] += outputValueA;
                currentInteraction.outputValue = outputValueA;
            }
        }

        // now verify that each interaction received the same proportion of the output as it gave in deposit
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            uint256 percentOfDeposit = (interaction.depositAmount * 100) / (15 * quantities[interaction.tranche.asset]);
            uint256 totalReceipt = totalReceiptByTranche[interaction.tranche.trancheAddress];
            uint256 percentOfReceipt = (interaction.outputValue * 100) / totalReceipt;
            int256 diff = int256(percentOfDeposit) - int256(percentOfReceipt);
            uint256 absDiff = diff >= 0 ? uint256(diff) : uint256(-diff);
            assertLt(absDiff, 2);
        }

        // verify rollup and bridge contract token quantities
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            uint256 totalDeposited = depositAmount * configs.length;
            uint256 assetInBridge = tokens[asset].balanceOf(address(elementBridge));
            assertGt(assetInBridge, totalDeposited);
            for (uint256 trancheIndex = 0; trancheIndex < configs.length; trancheIndex++) {
                _assertZeroBalance(address(elementBridge), configs[trancheIndex].trancheAddress);
            }
        }
    }

    function testMultipleInteractionsAreFinalisedOnConvert() public {
        // need to increase the gaslimit for the bridge to finalise
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 960000);
        _setupAssetPools("DAI");
        _setupAssetPools("USDC");
        string memory asset = "USDC";
        uint256 usdcDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numUsdcInteractions = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numUsdcInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), usdcDepositAmount * 15);
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            Interaction memory interaction = Interaction(config, usdcDepositAmount * depositMultipliers[i], nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // we expect 5 Finalise events to be emitted but we can't test the data values
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            vm.expectEmit(false, false, false, false);
            emit LogFinalise(1 + i, true, "", 0);
        }
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for USDC
        Balances memory balancesRollupAfter = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory balancesBridgeAfter = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should now be 0
        assertEq(balancesRollupAfter.bridgeTranche, 0);
        // the bridge's balance of USDC should be 0
        assertEq(balancesBridgeAfter.startingAsset, 0);
        // the rollup contract's balance of USDC should now be greater than the original amount deposited
        assertGt(balancesRollupAfter.startingAsset, usdcDepositAmount * numUsdcInteractions);

        // now verify that each interaction received the same proportion of the output as it gave in deposit
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            uint256 percentOfDeposit = (interaction.depositAmount * 100) / (15 * quantities[interaction.tranche.asset]);
            uint256 totalReceipt = balancesRollupAfter.startingAsset;
            (bool finalised, uint256 interactionOutputValue) = rollupProcessor.getDefiResult(interaction.nonce);
            _assertWithinOnePercentagePoint(interactionOutputValue, totalReceipt, percentOfDeposit);
            assertEq(finalised, true);
        }
    }

    function testMultipleInteractionsFailToFinaliseIfInsufficientBalance() public {
        _addTrancheConfig(
            "EURSCRV",
            0x2A8f5649DE50462fF9699Ccc75A2Fb0b53447503,
            0x6AC02eCD0c2A23B11f9AFb3b3Aaf237169475cac,
            1644604852
        );
        _setupAssetPools("DAI");
        _setupAssetPools("EURSCRV");
        string memory asset = "EURSCRV";
        uint256 eurDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numEurInteractions = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numEurInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), eurDepositAmount * 15);
        for (uint256 i = 0; i < numEurInteractions; i++) {
            Interaction memory interaction = Interaction(config, eurDepositAmount * depositMultipliers[i], nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }
        Balances memory balancesBridgeAfterConvert = _getBalances(interactions[0], address(elementBridge));

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // the next call wo convert will attempt to finalise the EUR tranche above. But they will fail as there is insufficient balance in the yearn vault
        // we expect 5 Finalise events to be emitted but we can't test the data values
        for (uint256 i = 0; i < numEurInteractions; i++) {
            vm.expectEmit(false, false, false, false);
            emit LogFinalise(1 + i, true, "", 0);
        }
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for EUR
        Balances memory balancesBridgeAfterFinalise = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should now be the same as after the initial calls to convert
        assertEq(balancesBridgeAfterFinalise.bridgeTranche, balancesBridgeAfterConvert.bridgeTranche);
        // the bridge's balance of EUR should be 0
        assertEq(balancesBridgeAfterFinalise.startingAsset, 0);

        // having previously failed, interactions can be finalised directly
        uint256 totalReceived = 0;
        for (uint256 i = 0; i < numEurInteractions; i++) {
            Interaction memory interaction = interactions[i];
            Balances memory balancesRollupBeforeManualFinalise = _getBalances(
                interactions[i],
                address(rollupProcessor)
            );
            Balances memory balancesBridgeBeforeManualFinalise = _getBalances(interactions[i], address(elementBridge));
            bool interactionCompleted = rollupProcessor.processAsyncDefiInteraction(interaction.nonce);
            assertEq(interactionCompleted, true);
            Balances memory balancesRollupAfterManualFinalise = _getBalances(interactions[i], address(rollupProcessor));
            Balances memory balancesBridgeAfterManualFinalise = _getBalances(interactions[i], address(elementBridge));
            uint256 outputValue = balancesRollupAfterManualFinalise.startingAsset -
                balancesRollupBeforeManualFinalise.startingAsset;
            totalReceived += outputValue;
            assertGt(outputValue, 0);
            assertEq(balancesBridgeAfterManualFinalise.bridgeTranche, 0);
            assertEq(
                balancesBridgeBeforeManualFinalise.bridgeTranche,
                i == 0 ? balancesBridgeAfterConvert.bridgeTranche : 0
            );
        }
        assertGt(totalReceived, eurDepositAmount * 15);
        Balances memory rollupBalancesEnd = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory bridgeBalancesEnd = _getBalances(interactions[0], address(elementBridge));
        assertEq(rollupBalancesEnd.startingAsset, totalReceived);
        assertEq(bridgeBalancesEnd.bridgeTranche, 0);
        assertEq(bridgeBalancesEnd.startingAsset, 0);
    }

    function testCanFinaliseAllInteractionsOnConvert() public {
        // set the gas limit high as we want all of our interactions to finalise
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 900000);
        _setupAllPools();
        uint256 numInteractionsPerTranche = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        Interaction[] memory interactions = new Interaction[]((numTranches - 1) * numInteractionsPerTranche);
        uint256 nonce = 1;
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            _increaseTokenBalance(asset, address(rollupProcessor), depositAmount * configs.length * 15);
            for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
                TrancheConfig storage config = configs[configIndex];
                if (config.expiry >= expiries[expiries.length - 1]) {
                    continue;
                }
                for (uint256 interactionCount = 0; interactionCount < numInteractionsPerTranche; interactionCount++) {
                    Interaction memory interaction = Interaction(
                        config,
                        depositAmount * depositMultipliers[interactionCount],
                        nonce,
                        0
                    );
                    interactions[nonce - 1] = interaction;
                    Balances memory balancesBefore = _getBalances(interaction, address(rollupProcessor));
                    (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                    assertEq(isAsync, true);
                    assertEq(outputValueA, 0);
                    assertEq(outputValueB, 0);
                    Balances memory balancesAfter = _getBalances(interaction, address(rollupProcessor));
                    assertEq(
                        balancesBefore.startingAsset - balancesAfter.startingAsset,
                        balancesAfter.balancerAsset - balancesBefore.balancerAsset
                    );
                    assertEq(
                        balancesBefore.balancerTranche - balancesAfter.balancerTranche,
                        balancesAfter.bridgeTranche - balancesBefore.bridgeTranche
                    );
                    // accumulate the tranche tokens collected by the bridge contract
                    bridgeBalanceByTranche[config.trancheAddress] +=
                        balancesAfter.bridgeTranche -
                        balancesBefore.bridgeTranche;
                    nonce++;
                }
            }
        }
        vm.warp(expiries[expiries.length - 2] + 1);
        for (uint256 trancheCount = 0; trancheCount < numTranches; trancheCount++) {
            string memory asset = "DAI";
            uint256 daiDepositAmount = quantities[asset];
            TrancheConfig storage config = trancheConfigs[asset][1];
            Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
            _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
            nonce++;
        }

        // verify rollup and bridge contract token quantities
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            uint256 totalDeposited = depositAmount * (configs.length * 15);
            uint256 rollupBalance = tokens[asset].balanceOf(address(rollupProcessor));
            assertGt(rollupBalance, totalDeposited);
            _assertZeroBalance(address(elementBridge), address(tokens[asset]));
            for (uint256 trancheIndex = 0; trancheIndex < configs.length; trancheIndex++) {
                // the second dai tranche hasn't been finalised so don't test this
                if (trancheIndex == 1 && keccak256(bytes(asset)) == keccak256(bytes("DAI"))) {
                    continue;
                }
                _assertZeroBalance(address(elementBridge), configs[trancheIndex].trancheAddress);
            }
        }

        // now verify that each interaction received the same proportion of the output as it gave in deposit
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            uint256 percentOfDeposit = (interaction.depositAmount * 100) / (15 * quantities[interaction.tranche.asset]);
            // this is the amount of tranche tokens collected by the bridge contract. These should have been withdrawn pretty much one for one into the end asset
            uint256 totalReceipt = bridgeBalanceByTranche[interaction.tranche.trancheAddress];
            (bool finalised, uint256 interactionOutputValue) = rollupProcessor.getDefiResult(interaction.nonce);
            _assertWithinOnePercentagePoint(interactionOutputValue, totalReceipt, percentOfDeposit);
            assertEq(finalised, true);
        }
    }

    function testCanFinaliseInteractionsAsTimeProgresses() public {
        // set the gas limit high as we want all of our interactions to finalise
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 2000000);
        _setupAllPools();
        uint256 numInteractionsPerTranche = 5;
        uint256 numTranchesPerBatch = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        Interaction[] memory interactions = new Interaction[]((numTranches - 1) * numInteractionsPerTranche);
        uint256 nonce = 1;
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            _increaseTokenBalance(asset, address(rollupProcessor), depositAmount * configs.length * 15);
        }

        // deposit into the the first batch of expiries
        // we do this by looping over everything but only selecting the tranches that have their expiry in the correct range
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
                TrancheConfig storage config = configs[configIndex];
                if (config.expiry > expiries[numTranchesPerBatch - 1]) {
                    continue;
                }
                for (uint256 interactionCount = 0; interactionCount < numInteractionsPerTranche; interactionCount++) {
                    Interaction memory interaction = Interaction(
                        config,
                        depositAmount * depositMultipliers[interactionCount],
                        nonce,
                        0
                    );
                    interactions[nonce - 1] = interaction;
                    Balances memory balancesBefore = _getBalances(interaction, address(rollupProcessor));
                    (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                    assertEq(isAsync, true);
                    assertEq(outputValueA, 0);
                    assertEq(outputValueB, 0);
                    Balances memory balancesAfter = _getBalances(interaction, address(rollupProcessor));
                    assertEq(
                        balancesBefore.startingAsset - balancesAfter.startingAsset,
                        balancesAfter.balancerAsset - balancesBefore.balancerAsset
                    );
                    assertEq(
                        balancesBefore.balancerTranche - balancesAfter.balancerTranche,
                        balancesAfter.bridgeTranche - balancesBefore.bridgeTranche
                    );
                    // accumulate the tranche tokens collected by the bridge contract
                    bridgeBalanceByTranche[config.trancheAddress] +=
                        balancesAfter.bridgeTranche -
                        balancesBefore.bridgeTranche;
                    nonce++;
                }
            }
        }
        // now fast forward time to just after the end of the first batch
        vm.warp(expiries[numTranchesPerBatch - 1] + 1);

        // deposit into the the second batch of expiries
        // we do this by looping over everything but only selecting the tranches that have their expiry in the correct range
        // this should finalise the first batch of deposits which we can then test afterwards
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
                TrancheConfig storage config = configs[configIndex];
                if (
                    config.expiry < expiries[numTranchesPerBatch] ||
                    config.expiry > expiries[numTranchesPerBatch * 2 - 1]
                ) {
                    continue;
                }
                for (uint256 interactionCount = 0; interactionCount < numInteractionsPerTranche; interactionCount++) {
                    Interaction memory interaction = Interaction(
                        config,
                        depositAmount * depositMultipliers[interactionCount],
                        nonce,
                        0
                    );
                    interactions[nonce - 1] = interaction;
                    Balances memory balancesBefore = _getBalances(interaction, address(rollupProcessor));
                    (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                    assertEq(isAsync, true);
                    assertEq(outputValueA, 0);
                    assertEq(outputValueB, 0);
                    Balances memory balancesAfter = _getBalances(interaction, address(rollupProcessor));
                    assertEq(
                        balancesBefore.balancerTranche - balancesAfter.balancerTranche,
                        balancesAfter.bridgeTranche - balancesBefore.bridgeTranche
                    );
                    // accumulate the tranche tokens collected by the bridge contract
                    bridgeBalanceByTranche[config.trancheAddress] +=
                        balancesAfter.bridgeTranche -
                        balancesBefore.bridgeTranche;
                    nonce++;
                }
            }
        }

        // now verify that the first batch of deposits have been finalised and they produced the correct output
        // the second batch should not be finalised and their output should be 0
        uint256 numInteractionsInFirstBatch = numTranchesPerBatch * numInteractionsPerTranche;
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            (bool finalised, uint256 interactionOutputValue) = rollupProcessor.getDefiResult(interaction.nonce);
            if (interactionIndex < numInteractionsInFirstBatch) {
                uint256 percentOfDeposit = (interaction.depositAmount * 100) /
                    (15 * quantities[interaction.tranche.asset]);
                // this is the amount of tranche tokens collected by the bridge contract. These should have been withdrawn pretty much one for one into the end asset
                uint256 totalReceipt = bridgeBalanceByTranche[interaction.tranche.trancheAddress];
                _assertWithinOnePercentagePoint(interactionOutputValue, totalReceipt, percentOfDeposit);
                assertEq(finalised, true);
            } else {
                assertEq(finalised, false);
                assertEq(interactionOutputValue, 0);
            }
        }

        // fast forward to the final tranche
        vm.warp(expiries[numTranchesPerBatch * 2 - 1] + 1);

        // make some deposits into the final tranche
        // this should finalise the second batch of deposits
        for (uint256 trancheCount = 0; trancheCount < numTranches; trancheCount++) {
            string memory asset = "DAI";
            uint256 daiDepositAmount = quantities[asset];
            TrancheConfig storage config = trancheConfigs[asset][1];
            Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
            _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
            nonce++;
        }

        //verify rollup and bridge contract token quantities
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            string storage asset = assets[assetIndex];
            uint256 depositAmount = quantities[asset];
            TrancheConfig[] storage configs = trancheConfigs[asset];
            uint256 totalDeposited = depositAmount * configs.length * 15;
            uint256 rollupBalance = tokens[asset].balanceOf(address(rollupProcessor));
            assertGt(rollupBalance, totalDeposited);
            _assertZeroBalance(address(elementBridge), address(tokens[asset]));
            for (uint256 trancheIndex = 0; trancheIndex < configs.length; trancheIndex++) {
                // the second dai tranche hasn't been finalised so don't test this
                if (trancheIndex == 1 && keccak256(bytes(asset)) == keccak256(bytes("DAI"))) {
                    continue;
                }
                _assertZeroBalance(address(elementBridge), configs[trancheIndex].trancheAddress);
            }
        }

        // now verify that each interaction received the same proportion of the output as it gave in deposit
        // for the first batch, this is a repeat of the check we did earlier but that's ok
        for (uint256 interactionIndex = 0; interactionIndex < interactions.length; interactionIndex++) {
            Interaction memory interaction = interactions[interactionIndex];
            uint256 percentOfDeposit = (interaction.depositAmount * 100) / (15 * quantities[interaction.tranche.asset]);
            // this is the amount of tranche tokens collected by the bridge contract. These should have been withdrawn pretty much one for one into the end asset
            uint256 totalReceipt = bridgeBalanceByTranche[interaction.tranche.trancheAddress];
            (bool finalised, uint256 interactionOutputValue) = rollupProcessor.getDefiResult(interaction.nonce);
            _assertWithinOnePercentagePoint(interactionOutputValue, totalReceipt, percentOfDeposit);
            assertEq(finalised, true);
        }
    }

    function testInteractionsFailOnSpeedbump() public {
        _addTrancheConfig(
            "EURSCRV",
            0x2A8f5649DE50462fF9699Ccc75A2Fb0b53447503,
            0x6AC02eCD0c2A23B11f9AFb3b3Aaf237169475cac,
            1644604852
        );
        _setupAssetPools("DAI");
        _setupAssetPools("EURSCRV");
        string memory asset = "EURSCRV";
        uint256 eurDepositAmount = 1;
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numEurInteractions = 5;
        uint8[5] memory depositMultipliers = [1, 2, 3, 4, 5];
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numEurInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), eurDepositAmount * 15);
        for (uint256 i = 0; i < numEurInteractions; i++) {
            Interaction memory interaction = Interaction(config, eurDepositAmount * depositMultipliers[i], nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }
        Balances memory balancesBridgeAfterConvert = _getBalances(interactions[0], address(elementBridge));

        vm.warp(config.expiry + 1);

        // now set the speedbump
        _setSpeedbumpSlot(asset, config.expiry, config.expiry + 1);

        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // the next call to convert will attempt to finalise the EUR tranche above. But they will fail as the tranche has the speedbump set
        // we expect 5 Finalise events to be emitted but we can't test the data values
        for (uint256 i = 0; i < numEurInteractions; i++) {
            vm.expectEmit(false, false, false, false);
            emit LogFinalise(1 + i, true, "", 0);
        }
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for EUR
        Balances memory balancesBridgeAfterFinalise = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should now be the same as after the initial calls to convert
        assertEq(balancesBridgeAfterFinalise.bridgeTranche, balancesBridgeAfterConvert.bridgeTranche);
        // the bridge's balance of EUR should be 0
        assertEq(balancesBridgeAfterFinalise.startingAsset, 0);

        // having previously failed, interactions can be finalised directly
        uint256 totalReceived = 0;
        for (uint256 i = 0; i < numEurInteractions; i++) {
            Interaction memory interaction = interactions[i];
            Balances memory balancesRollupBeforeManualFinalise = _getBalances(
                interactions[i],
                address(rollupProcessor)
            );
            Balances memory balancesBridgeBeforeManualFinalise = _getBalances(interactions[i], address(elementBridge));
            bool interactionCompleted = rollupProcessor.processAsyncDefiInteraction(interaction.nonce);
            assertEq(interactionCompleted, true);
            Balances memory balancesRollupAfterManualFinalise = _getBalances(interactions[i], address(rollupProcessor));
            Balances memory balancesBridgeAfterManualFinalise = _getBalances(interactions[i], address(elementBridge));
            uint256 outputValue = balancesRollupAfterManualFinalise.startingAsset -
                balancesRollupBeforeManualFinalise.startingAsset;
            totalReceived += outputValue;
            assertGt(outputValue, 0);
            assertEq(balancesBridgeAfterManualFinalise.bridgeTranche, 0);
            assertEq(
                balancesBridgeBeforeManualFinalise.bridgeTranche,
                i == 0 ? balancesBridgeAfterConvert.bridgeTranche : 0
            );
        }
        assertGt(totalReceived, eurDepositAmount * 15);
        Balances memory rollupBalancesEnd = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory bridgeBalancesEnd = _getBalances(interactions[0], address(elementBridge));
        assertEq(rollupBalancesEnd.startingAsset, totalReceived);
        assertEq(bridgeBalancesEnd.bridgeTranche, 0);
        assertEq(bridgeBalancesEnd.startingAsset, 0);
    }

    function testOnlyFinalisesUpToGasLimit1() public {
        // set the gas limit so that only the first interaction finalises
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 600000);
        _setupAssetPools("DAI");
        _setupAssetPools("USDC");
        string memory asset = "USDC";
        uint256 usdcDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numUsdcInteractions = 5;
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numUsdcInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), usdcDepositAmount * 5);
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            Interaction memory interaction = Interaction(config, usdcDepositAmount, nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // we expect 1 Finalise events to be emitted but we can't test the data values
        vm.expectEmit(false, false, false, true);
        emit LogFinalise(5, true, "", USDC_FINALISE_GAS);
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for USDC
        Balances memory balancesRollupAfter = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory balancesBridgeAfter = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should be 0
        assertEq(balancesRollupAfter.bridgeTranche, 0);
        // the bridge's balance of USDC should be greater than zero
        assertGt(balancesBridgeAfter.startingAsset, 0);
        // the rollup contract's balance of USDC should now be greater than the amount of 1 deposit but less than the amount of 2
        assertGt(balancesRollupAfter.startingAsset, usdcDepositAmount);
        assertLt(balancesRollupAfter.startingAsset, usdcDepositAmount * 2);
        // rollup balance of asset should be 20%
        _assertWithinOnePercentagePoint(
            balancesRollupAfter.startingAsset,
            balancesRollupAfter.startingAsset + balancesBridgeAfter.startingAsset,
            20
        );

        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            (bool finalised, uint256 outputValueA) = rollupProcessor.getDefiResult(numUsdcInteractions - i);
            assertEq(finalised, i == 0);
            assertEq(outputValueA, i == 0 ? balancesRollupAfter.startingAsset : 0);
        }
    }

    function testOnlyFinalisesUpToGasLimit2() public {
        // set the gas limit so that only the first 2 interactions finalise
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 670000);
        _setupAssetPools("DAI");
        _setupAssetPools("USDC");
        string memory asset = "USDC";
        uint256 usdcDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numUsdcInteractions = 5;
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numUsdcInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), usdcDepositAmount * 5);
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            Interaction memory interaction = Interaction(config, usdcDepositAmount, nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // we expect 2 Finalise events to be emitted but we can't test the data values
        uint256 numExpectedFinalisedInteractions = 2;
        vm.expectEmit(false, false, false, false);
        emit LogFinalise(5, true, "", 0);
        emit LogFinalise(4, true, "", 0);
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for USDC
        Balances memory balancesRollupAfter = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory balancesBridgeAfter = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should be 0
        assertEq(balancesRollupAfter.bridgeTranche, 0);
        // the bridge's balance of USDC should be greater than zero
        assertGt(balancesBridgeAfter.startingAsset, 0);
        // the rollup contract's balance of USDC should now be greater than the amount of 2 deposit but less than the amount of 3
        assertGt(balancesRollupAfter.startingAsset, usdcDepositAmount * numExpectedFinalisedInteractions);
        assertLt(balancesRollupAfter.startingAsset, usdcDepositAmount * (numExpectedFinalisedInteractions + 1));
        // rollup balance of asset should be 20% for each finalised interaction
        _assertWithinOnePercentagePoint(
            balancesRollupAfter.startingAsset,
            balancesRollupAfter.startingAsset + balancesBridgeAfter.startingAsset,
            numExpectedFinalisedInteractions * 20
        );

        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            (bool finalised, uint256 outputValueA) = rollupProcessor.getDefiResult(numUsdcInteractions - i);
            assertEq(finalised, i < numExpectedFinalisedInteractions);
            if (i < numExpectedFinalisedInteractions) {
                _assertWithinOnePercentagePoint(
                    outputValueA,
                    balancesRollupAfter.startingAsset + balancesBridgeAfter.startingAsset,
                    20
                );
            } else {
                assertEq(outputValueA, 0);
            }
        }
    }

    function testOnlyFinalisesUpToGasLimit3() public {
        // set the gas limit so that only the first 3 interactions finalise
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 800000);
        _setupAssetPools("DAI");
        _setupAssetPools("USDC");
        string memory asset = "USDC";
        uint256 usdcDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numUsdcInteractions = 5;
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numUsdcInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), usdcDepositAmount * 5);
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            Interaction memory interaction = Interaction(config, usdcDepositAmount, nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        // we expect 3 Finalise events to be emitted but we can't test the data values
        uint256 numExpectedFinalisedInteractions = 3;
        vm.expectEmit(false, false, false, false);
        emit LogFinalise(5, true, "", 0);
        emit LogFinalise(4, true, "", 0);
        emit LogFinalise(3, true, "", 0);
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for USDC
        Balances memory balancesRollupAfter = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory balancesBridgeAfter = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should be 0
        assertEq(balancesRollupAfter.bridgeTranche, 0);
        // the bridge's balance of USDC should be greater than zero
        assertGt(balancesBridgeAfter.startingAsset, 0);
        // the rollup contract's balance of USDC should now be greater than the amount of 3 deposit but less than the amount of 4
        assertGt(balancesRollupAfter.startingAsset, usdcDepositAmount * numExpectedFinalisedInteractions);
        assertLt(balancesRollupAfter.startingAsset, usdcDepositAmount * (numExpectedFinalisedInteractions + 1));
        // rollup balance of asset should be 20% for each finalised interaction
        _assertWithinOnePercentagePoint(
            balancesRollupAfter.startingAsset,
            balancesRollupAfter.startingAsset + balancesBridgeAfter.startingAsset,
            numExpectedFinalisedInteractions * 20
        );

        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            (bool finalised, uint256 outputValueA) = rollupProcessor.getDefiResult(numUsdcInteractions - i);
            assertEq(finalised, i < numExpectedFinalisedInteractions);
            if (i < numExpectedFinalisedInteractions) {
                _assertWithinOnePercentagePoint(
                    outputValueA,
                    balancesRollupAfter.startingAsset + balancesBridgeAfter.startingAsset,
                    20
                );
            } else {
                assertEq(outputValueA, 0);
            }
        }
    }

    function testRedemptionFailsIfNotEnoughGas() public {
        // set the gas limit so that the redemption is attempted but fails
        rollupProcessor.setBridgeGasLimit(address(elementBridge), 350000);
        _setupAssetPools("DAI");
        _setupAssetPools("USDC");
        string memory asset = "USDC";
        uint256 usdcDepositAmount = quantities[asset];
        TrancheConfig storage config = trancheConfigs[asset][0];
        uint256 numUsdcInteractions = 5;
        uint8[5] memory depositMultipliers = [1, 1, 1, 1, 1];
        uint256 nonce = 1;
        Interaction[] memory interactions = new Interaction[](numUsdcInteractions);
        _increaseTokenBalance(asset, address(rollupProcessor), usdcDepositAmount * 5);
        for (uint256 i = 0; i < numUsdcInteractions; i++) {
            Interaction memory interaction = Interaction(config, usdcDepositAmount * depositMultipliers[i], nonce, 0);
            interactions[nonce - 1] = interaction;
            {
                (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, interaction);
                assertEq(isAsync, true);
                assertEq(outputValueA, 0);
                assertEq(outputValueB, 0);
            }
            nonce++;
        }

        vm.warp(config.expiry + 1);
        asset = "DAI";
        uint256 daiDepositAmount = quantities[asset];
        config = trancheConfigs[asset][1];
        Interaction memory daiInteraction = Interaction(config, daiDepositAmount, nonce, 0);
        _increaseTokenBalance(asset, address(rollupProcessor), daiDepositAmount);
        {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _callRollupConvert(asset, daiInteraction);
            assertEq(isAsync, true);
            assertEq(outputValueA, 0);
            assertEq(outputValueB, 0);
        }
        // this will get the balances for USDC
        Balances memory balancesRollupAfter = _getBalances(interactions[0], address(rollupProcessor));
        Balances memory balancesBridgeAfter = _getBalances(interactions[0], address(elementBridge));
        // the bridge's balance of the tranche token should be greater than 0
        assertGt(balancesRollupAfter.bridgeTranche, 0);
        // the bridge's balance of USDC should be 0
        assertEq(balancesBridgeAfter.startingAsset, 0);
        // the rollup contract's balance of USDC should be 0
        assertEq(balancesRollupAfter.startingAsset, 0);
    }

    function _callElementConvert(string memory _asset, Interaction memory _interaction)
        private
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        AztecTypes.AztecAsset memory assetData = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens[_asset]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.prank(address(rollupProcessor));
        (uint256 outputValueALocal, uint256 outputValueBLocal, bool isAsyncLocal) = elementBridge.convert(
            assetData,
            emptyAsset,
            assetData,
            emptyAsset,
            _interaction.depositAmount,
            _interaction.nonce,
            _interaction.tranche.expiry,
            address(0)
        );
        outputValueA = outputValueALocal;
        outputValueB = outputValueBLocal;
        isAsync = isAsyncLocal;
    }

    function _callElementFinalise(Interaction memory _interaction)
        private
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionCompleted
        )
    {
        AztecTypes.AztecAsset memory asset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens[_interaction.tranche.asset]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.prank(address(rollupProcessor));
        (uint256 outputValueALocal, uint256 outputValueBLocal, bool interactionCompletedLocal) = elementBridge.finalise(
            asset,
            emptyAsset,
            asset,
            emptyAsset,
            _interaction.nonce,
            _interaction.tranche.expiry
        );
        outputValueA = outputValueALocal;
        outputValueB = outputValueBLocal;
        interactionCompleted = interactionCompletedLocal;
    }

    function _callRollupConvert(string memory _asset, Interaction memory _interaction)
        private
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        AztecTypes.AztecAsset memory assetData = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens[_asset]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint64 expiry = _interaction.tranche.expiry;
        uint256 nonce = _interaction.nonce;
        uint256 deposit = _interaction.depositAmount;
        vm.prank(address(rollupProcessor));
        (uint256 outputValueALocal, uint256 outputValueBLocal, bool isAsyncLocal) = rollupProcessor.convert(
            address(elementBridge),
            assetData,
            emptyAsset,
            assetData,
            emptyAsset,
            deposit,
            nonce,
            expiry
        );
        outputValueA = outputValueALocal;
        outputValueB = outputValueBLocal;
        isAsync = isAsyncLocal;
    }

    function _assertZeroBalance(address _owner, address _erc20) private {
        assertEq(IERC20(_erc20).balanceOf(_owner), 0);
    }

    function _assertNonZeroBalance(address _owner, address _erc20) private {
        _assertBalanceGt(_owner, _erc20, 0);
    }

    function _assertBalanceGt(
        address _owner,
        address _erc20,
        uint256 _value
    ) private {
        assertGt(IERC20(_erc20).balanceOf(_owner), _value);
    }

    function _assertWithinOnePercentagePoint(
        uint256 _quantity,
        uint256 _total,
        uint256 _targetPercent
    ) private {
        uint256 percent = (_quantity * 100) / _total;
        int256 diff = int256(percent) - int256(_targetPercent);
        uint256 absDiff = diff >= 0 ? uint256(diff) : uint256(-diff);
        assertLt(absDiff, 2);
    }

    function _setTokenBalance(
        string memory _asset,
        address _account,
        uint256 _balance
    ) private {
        address tokenAddress = address(tokens[_asset]);
        deal(tokenAddress, _account, _balance);

        assertEq(tokens[_asset].balanceOf(_account), _balance, "wrong balance");
    }

    function _increaseTokenBalance(
        string memory _asset,
        address _account,
        uint256 _additionalBalance
    ) private {
        address tokenAddress = address(tokens[_asset]);
        uint256 currentBalance = tokens[_asset].balanceOf(_account);
        uint256 newBalance = currentBalance + _additionalBalance;

        deal(tokenAddress, _account, newBalance);

        assertEq(tokens[_asset].balanceOf(_account), newBalance, "wrong balance");
    }

    function _findSpeedbumpSlot(string memory _asset, uint256 _expiry) private returns (bytes32 slot) {
        address trancheAddress = _deriveTranche(_asset, _expiry);
        uint256 foundSlot = stdStore.target(trancheAddress).sig("speedbump()").find();
        slot = bytes32(foundSlot);
    }

    function _setSpeedbumpSlot(
        string memory _asset,
        uint256 _expiry,
        uint256 _speedbump
    ) private returns (uint256 newSpeedbump) {
        address trancheAddress = _deriveTranche(_asset, _expiry);
        bytes32 slot = _findSpeedbumpSlot(_asset, _expiry);
        vm.store(trancheAddress, slot, bytes32(_speedbump));
        return ITranche(trancheAddress).speedbump();
    }

    function _getBalances(Interaction memory _interaction, address _startingContract)
        private
        returns (Balances memory balances)
    {
        balances.startingAsset = IERC20(tokens[_interaction.tranche.asset]).balanceOf(_startingContract);
        balances.bridgeTranche = IERC20(_interaction.tranche.trancheAddress).balanceOf(address(elementBridge));
        balances.balancerAsset = IERC20(tokens[_interaction.tranche.asset]).balanceOf(BALANCER);
        balances.balancerTranche = IERC20(_interaction.tranche.trancheAddress).balanceOf(BALANCER);
        return balances;
    }

    function _setupConvergentPool(TrancheConfig storage _config) private {
        address wrappedPosition = wrappedPositions[_config.asset];
        elementDeploymentValidator.validateWPAddress(wrappedPosition);
        elementDeploymentValidator.validatePoolAddress(_config.poolAddress);
        elementDeploymentValidator.validateAddresses(wrappedPosition, _config.poolAddress);
        elementBridge.registerConvergentPoolAddress(_config.poolAddress, wrappedPosition, _config.expiry);
    }

    function _setupAssetPools(string memory _asset) private {
        TrancheConfig[] storage configs = trancheConfigs[_asset];
        for (uint256 configIndex = 0; configIndex < configs.length; configIndex++) {
            TrancheConfig storage config = configs[configIndex];
            _setupConvergentPool(config);
        }
    }

    function _setupAllPools() private {
        for (uint256 assetIndex = 0; assetIndex < assets.length; assetIndex++) {
            _setupAssetPools(assets[assetIndex]);
        }
    }

    function _addTrancheConfig(
        string memory _asset,
        address _trancheAddress,
        address _poolAddress,
        uint64 _expiry
    ) private {
        TrancheConfig[] storage configs = trancheConfigs[_asset];
        configs.push(TrancheConfig(_asset, _trancheAddress, _poolAddress, _expiry));
        if (configs.length == 1) {
            assets.push(_asset);
        }
        numTranches++;
        bridgeBalanceByTranche[_trancheAddress] = 0;
        totalReceiptByTranche[_trancheAddress] = 0;
    }

    function _deriveTranche(string memory _asset, uint256 _expiry) private view returns (address trancheContract) {
        address position = wrappedPositions[_asset];
        bytes32 salt = keccak256(abi.encodePacked(position, _expiry));
        bytes32 addressBytes = keccak256(abi.encodePacked(bytes1(0xff), TRANCHE_FACTORY_ADDRESS, salt, BYTE_CODE_HASH));
        trancheContract = address(uint160(uint256(addressBytes)));
    }

    function _randomAddress() private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
    }
}
