import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract vaultMock is ERC20 {
    address public erc20;

    constructor(
        address _erc20,
        string memory n,
        string memory sym
    ) public ERC20(n, sym) {
        erc20 = _erc20;
    }

    function want() public view returns (IERC20) {
        return IERC20(erc20);
    }

    function deposit(uint256 amount) external {
        IERC20(erc20).transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        IERC20(erc20).transferFrom(address(this), msg.sender, amount);
        _burn(msg.sender, amount);
    }
}
