pragma solidity >=0.8.4;
import {ISetToken} from './ISetToken.sol';

interface IAaveLeverageModule{
    function sync(ISetToken) external;

}
