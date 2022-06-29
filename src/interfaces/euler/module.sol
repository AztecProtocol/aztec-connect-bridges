pragma solidity >=0.8.4;

interface module {

    function enterMarket(uint, address) external; //address here = collateral
    function underlyingToAssetConfig(address) external view returns (IEuler.AssetConfig memory);
    function underlyingToEToken(address) external view returns (address);
    
    
    


}
