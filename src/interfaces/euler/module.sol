pragma solidity >=0.8.4;

interface module {

    function enterMarket(uint, address) external; //address here = collateral
    function underlyingToAssetConfigUnresolved(address) external view returns (IEuler.AssetConfig memory config);
    function underlyingToEToken(address) external view returns (address);
    
    
    


}
