// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";
import {AddressRegistryDeployment} from "../../deployment/registry/AddressRegistryDeployment.s.sol";
import {NftVault} from "../../bridges/nft-basic/NftVault.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {NftVaultDeployment} from "../../deployment/nft-basic/NftVaultDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

import {ERC721PresetMinterPauserAutoId} from
    "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";


interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract NftVaultGas is NftVaultDeployment, AddressRegistryDeployment {
    GasBase internal gasBase;
    NftVault internal bridge;
    ERC721PresetMinterPauserAutoId internal nftContract;
    address internal registry;
    uint256 internal registryAddressId;

    function measure() public {
        uint256 privKey1 = vm.envUint("PRIVATE_KEY");
        address addr1 = vm.addr(privKey1);

        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.startBroadcast();
        gasBase = new GasBase(defiProxy);
        nftContract = new ERC721PresetMinterPauserAutoId("test", "NFT", "");
        nftContract.mint(addr1);
        vm.stopBroadcast();

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        registry = deployAndListAddressRegistry();
        address bridge = deployAndList(registry);
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory eth =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        AztecTypes.AztecAsset memory virtualAsset =
            AztecTypes.AztecAsset({id: 100, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

        vm.startBroadcast();
        address(gasBase).call{value: 2 ether}("");

        // get registry virtual asset
        gasBase.convert(address(registry), eth, empty, virtualAsset, empty, 1, 0, 0, address(0), 400000);
        // register address
        gasBase.convert(address(registry), virtualAsset, empty, virtualAsset, empty, uint256(uint160(addr1)), 0, 0, address(0), 400000);
        nftContract.approve(address(bridge), 0);
        vm.stopBroadcast();

        // Get virtual assets
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, virtualAsset, empty, 1, 0, 0, address(0), 400000);
        }
        // deposit nft
        {
            vm.broadcast();
            NftVault(bridge).matchDeposit(virtualAsset.id, address(nftContract), 0);
        }
        // withdraw nft
        {
            vm.broadcast();
            gasBase.convert(bridge, virtualAsset, empty, eth, empty, 1, 0, 1, address(0), 400000);
        }
    }
}
