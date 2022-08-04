// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IStableMaster} from "../../interfaces/angle/IStableMaster.sol";

/**
 * @title Angle Protocol bridge contract.
 * @author Angle Protocol Team
 * @notice Allows a user to deposit/withdraw his tokens to/from Angle Protocol
 * @dev Enter Angle Protocol as an SLP by depositing authorized tokens
 */
contract AngleBridge is BridgeBase {
    using SafeERC20 for IERC20;

    IStableMaster public constant STABLE_MASTER = IStableMaster(0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87);

    // collateralAddress => poolManagerAddress
    mapping(address => address) internal poolManagers;

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        poolManagers[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0xc9daabC677F3d1301006e723bD21C60be57a5915;
        poolManagers[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD;
        poolManagers[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2;
        poolManagers[0x853d955aCEf822Db058eb8505911ED77F175b99e] = 0x6b4eE7352406707003bC6f6b96595FD35925af48;

        // _preApprove(0xc9daabC677F3d1301006e723bD21C60be57a5915);
        // _preApprove(0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD);
        // _preApprove(0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2);
        // _preApprove(0x6b4eE7352406707003bC6f6b96595FD35925af48);
    }

    /**
     * @notice A function which returns an _totalInputValue amount of _inputAssetA
     * @param _inputAssetA - ERC20/ETH (deposit), or sanToken (withdraw)
     * @param _outputAssetA - sanToken (deposit), or ERC20/ETH (withdraw)
     * @param _totalInputValue - amount of ERC20/ETH to deposit, or the amount of sanToken to withdraw
     * @param _auxData - 0 (deposit), 1 (withdraw)
     * @return outputValueA - the amount of output asset to return
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

        uint256 outputAssetBalanceBefore = IERC20(_outputAssetA.erc20Address).balanceOf(address(this));

        IERC20(_inputAssetA.erc20Address).approve(address(STABLE_MASTER), _totalInputValue);

        if (_auxData == 0) {
            address poolManager = poolManagers[_inputAssetA.erc20Address];
            if (poolManager == address(0)) revert ErrorLib.InvalidInputA();

            (, address sanToken, , , , , , , ) = STABLE_MASTER.collateralMap(poolManager);
            if (sanToken != _outputAssetA.erc20Address) revert ErrorLib.InvalidOutputA();

            STABLE_MASTER.deposit(_totalInputValue, address(this), poolManager);
        } else if (_auxData == 1) {
            address poolManager = poolManagers[_outputAssetA.erc20Address];
            if (poolManager == address(0)) revert ErrorLib.InvalidOutputA();

            (, address sanToken, , , , , , , ) = STABLE_MASTER.collateralMap(poolManager);
            if (sanToken != _inputAssetA.erc20Address) revert ErrorLib.InvalidInputA();

            STABLE_MASTER.withdraw(_totalInputValue, address(this), address(this), poolManager);
        }

        outputValueA = IERC20(_outputAssetA.erc20Address).balanceOf(address(this)) - outputAssetBalanceBefore;

        // Approve rollup processor to take input value of input asset
        IERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, outputValueA);
    }

    // (not used for now)
    // Pre-approval of all tokens, should be done in the constructor
    function _preApprove(address _poolManager) private {
        (IERC20 token, address sanToken, , , , , , , ) = STABLE_MASTER.collateralMap(_poolManager);

        uint256 allowance = token.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            token.safeApprove(ROLLUP_PROCESSOR, 0);
            token.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }
        allowance = token.allowance(address(this), address(STABLE_MASTER));
        if (allowance != type(uint256).max) {
            token.safeApprove(address(STABLE_MASTER), 0);
            token.safeApprove(address(STABLE_MASTER), type(uint256).max);
        }

        allowance = IERC20(sanToken).allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance != type(uint256).max) {
            IERC20(sanToken).safeApprove(ROLLUP_PROCESSOR, 0);
            IERC20(sanToken).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        }
        allowance = IERC20(sanToken).allowance(address(this), address(STABLE_MASTER));
        if (allowance != type(uint256).max) {
            IERC20(sanToken).safeApprove(address(STABLE_MASTER), 0);
            IERC20(sanToken).safeApprove(address(STABLE_MASTER), type(uint256).max);
        }
    }
}
