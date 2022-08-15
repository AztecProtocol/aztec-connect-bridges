// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

/**
 * @title Aztec Connect Bridge for ERC4626 compatible vaults
 * @author johhonn (on github) and the Aztec team
 * @notice You can use this contract to issue or redeem shares of any ERC4626 vault
 */
contract ERC4626Bridge is BridgeBase {
    using SafeERC20 for IERC20;

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Sets the address of RollupProcessor
     * @param _rollupProcessor Address of RollupProcessor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}

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
     * @param _interactionNonce A globally unique identifier of this call
     * @param _auxData Number indicating which flow to execute (0 is deposit flow, 1 is redeem flow)
     * @return outputValueA The amount of shares (deposit) or assets (redeem) returned
     * @dev Not checking validity of input/output assets because if they were invalid, approvals could not get set
     *      in the `listVault(...)` method.
     * @dev In case input or output asset is ETH, the bridge wraps/unwraps it.
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
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
            // Issuing new shares - input can be ETH
            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                WETH.deposit{value: _totalInputValue}();
            }
            // If input asset is not the vault asset (or ETH if vault asset is WETH) the following will revert when
            // trying to pull the funds from the bridge
            outputValueA = IERC4626(_outputAssetA.erc20Address).deposit(_totalInputValue, address(this));
        } else if (_auxData == 1) {
            // Redeeming shares
            // If output asset is not the vault asset the convert call will revert when RollupProcessor tries to pull
            // the funds from the bridge
            outputValueA = IERC4626(_inputAssetA.erc20Address).redeem(_totalInputValue, address(this), address(this));

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                IWETH(WETH).withdraw(outputValueA);
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            }
        } else {
            revert ErrorLib.InvalidAuxData();
        }
    }
}
