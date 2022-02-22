// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';
import {IJBDirectory} from './interfaces/IJBDirectory.sol';
import {IJBTerminal} from './interfaces/IJBTerminal.sol';
import {IJBTokenStore} from './interfaces/IJBTokenStore.sol';

import {AztecTypes} from '../../aztec/AztecTypes.sol';

contract JuiceboxBridge is IDefiBridge {
    //*********************************************************************//
    // -------------------- public stored properties --------------------- //
    //*********************************************************************//
    address public constant JB_ETH = address(0xeeee);

    IJBDirectory public immutable jbDirectory;
    IJBTokenStore public immutable jbTokenStore;
    address public immutable rollupProcessor;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(
        address _rollupProcessor,
        IJBDirectory _jbDirectory,
        IJBTokenStore _jbTokenStore
    ) public {
        rollupProcessor = _rollupProcessor;
        jbDirectory = _jbDirectory;
        jbTokenStore = _jbTokenStore;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData // Let this represent the Juicebox projectId
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        require(msg.sender == rollupProcessor, 'JuiceboxBridge: INVALID_CALLER');
        require(inputAssetA.assetType == AztecTypes.AztecAssetType.ETH, 'JuiceboxBridge: INPUT_ASSET_NOT_ETH');
        require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, 'JuiceboxBridge: OUTPUT_ASSET_NOT_ERC20');
        require(
            inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED,
            'JuiceboxBridge: EXPECTED_SECOND_INPUT_ASSET_NOT_USED'
        );
        require(
            outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED,
            'JuiceboxBridge: EXPECTED_SECOND_OUTPUT_ASSET_NOT_USED'
        );
        // Lookup JBToken by projectId and verify equality to outputAssetA
        require(
            address(jbTokenStore.tokenOf(auxData)) == outputAssetA.erc20Address,
            'JuiceboxBridge: OUTPUT_ASSET_MISMATCH'
        );

        // Pay using appropriate JBTerminal
        IJBTerminal _terminal = jbDirectory.primaryTerminalOf(auxData, JB_ETH);
        require(_terminal != IJBTerminal(address(0)), 'JuiceboxBridge: TERMINAL_NOT_FOUND');
        _terminal.pay{value: inputValue}(
            /* _projectId */
            auxData,
            /* _beneficiary */
            address(this),
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            true,
            /* _memo */
            'Batched payments from Aztec L2. Privacy preserved!',
            /* _delegateMetadata */
            new bytes(0)
        );

        // TODO: best way to get or predict outputValueA aka "number of resulting JBTokens from pay"?
        outputValueA = 0;

        // Approve rollupProcessor to transfer output JBToken
        require(
            IERC20(outputAssetA.erc20Address).approve(address(rollupProcessor), outputValueA),
            'JuiceboxBridge: APPROVE_FAILED'
        );

        outputValueB = 0;
        isAsync = false;
    }

    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false);
    }
}
