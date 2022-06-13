import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IERC4626 is IERC20 {
    //Mints   shares of Vault to receiver by depositing exact amount of underlying tokens.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    //Mints exact shares of Vault  to receiver by depositing variable amount of underlying tokens.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    //Burns shares from owner and sends exact assets of underlying tokens to receiver.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    //Burns exact shares from owner and sends assets of underlying tokens to receiver.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function asset() external view returns (IERC20);
}
