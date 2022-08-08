// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";

/**
 * @title Aztec Connect Bridge for ERC4626 compatible vaults
 * @author johhonn (on github) and the Aztec team
 * @notice You can use this contract to issue or redeem shares of any ERC4626 vault
 */
contract ERC4626Bridge is BridgeBase {
    using SafeERC20 for IERC20;

    // TODO: EIP-1087 based optimization

    /**
     * @notice Sets the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice Sets all the approvals necessary for issuance and redemption of `_vault` shares
     * @param _vault An address of erc4626 vault
     */
    function listVault(address _vault) external {
        IERC20 asset = IERC20(IERC4626(_vault).asset());

        // Resetting allowance to 0 for USDT compatibility
        asset.safeApprove(address(_vault), 0);
        asset.safeApprove(address(_vault), type(uint256).max);
        asset.safeApprove(address(ROLLUP_PROCESSOR), 0);
        asset.safeApprove(address(ROLLUP_PROCESSOR), type(uint256).max);

        IERC20(_vault).approve(ROLLUP_PROCESSOR, type(uint256).max);
    }

    /**
     * @notice Issues or redeems shares of any ERC4626 vault
     * @param _inputAssetA Vault asset (deposit) or vault shares (redeem)
     * @param _outputAssetA Vault shares (deposit) or vault asset (redeem)
     * @param _totalInputValue The amount of assets to deposit or shares to redeem
     * @param _auxData Number indicating which flow to execute (0 is deposit flow, 1 is redeem flow)
     * @return outputValueA The amount of shares (deposit) or assets (redeem) returned
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
        if (_auxData == 0) {
            outputValueA = IERC4626(_outputAssetA.erc20Address).deposit(_totalInputValue, address(this));
        } else if (_auxData == 1) {
            outputValueA = IERC4626(_inputAssetA.erc20Address).redeem(_totalInputValue, address(this), address(this));
        } else {
            revert ErrorLib.InvalidInput();
        }
    }
}
