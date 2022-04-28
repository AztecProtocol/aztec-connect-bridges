import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IBeefyVault is IERC20 {
    function name() external view returns (string memory);

    function deposit(uint256) external;

    function depositAll() external;

    function withdraw(uint256) external;

    function withdrawAll() external;

    function getPricePerFullShare() external view returns (uint256);

    function upgradeStrat() external;

    function balance() external view returns (uint256);

    function want() external view returns (IERC20);

    function strategy() external view returns (IBeefyStrategy);
}

interface IBeefyStrategy {
    function vault() external view returns (address);

    function want() external view returns (IERC20);

    function beforeDeposit() external;

    function deposit() external;

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function harvest(address callFeeRecipient) external;

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function unirouter() external view returns (address);

    function lpToken0() external view returns (address);

    function lpToken1() external view returns (address);

    function lastHarvest() external view returns (uint256);

    function callReward() external view returns (uint256);

    function harvestWithCallFeeRecipient(address callFeeRecipient) external; // back compat call
}
