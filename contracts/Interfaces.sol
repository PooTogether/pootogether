
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Interfaces
interface yVaultInterface is IERC20 {
    function token() external view returns (address);
    function balance() external view returns (uint);
    function deposit(uint _amount) external;
    function withdraw(uint _shares) external;
    function getPricePerFullShare() external view returns (uint);
}


