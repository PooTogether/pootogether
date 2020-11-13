import "./SortitionSumTreeFactory.sol";
import "./UniformRandomNumber.sol";
import "./SafeMath.sol";
import "./Interfaces.sol";
import "./Ownable.sol";

interface DistribInterface {
	function distribute(uint entropy, address winner) external;
}

contract Distributor {
	Uni public constant uniswap = Uni(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
	yVaultInterface public constant vault = yVaultInterface(0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c);
	address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	
	function shitcoinMenu(uint entropy) public pure returns (address) { 
		uint idx = UniformRandomNumber.uniform(entropy, 5);
		if (idx == 0) return address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984); // UNI 
		if (idx == 1) return address(0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7); // CORE
		if (idx == 2) return address(0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b); // DPI
		if (idx == 3) return address(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5); // PICKLE
		if (idx == 4) return address(0xa0246c9032bC3A600820415aE600c6388619A14D); // FARM
		return address(0);
	}
	
	function distribute(uint entropy, address winner) external {
		address[] memory path = new address[](3);
		path[0] = address(vault);
		path[1] = WETH;
		path[2] = shitcoinMenu(entropy);
		uniswap.swapExactTokensForTokens(vault.balanceOf(address(this)), uint(0), path, winner, block.timestamp);
	}
}

contract PooTogether is Ownable {
	using SafeMath for uint;

	// Terminology
	// base = the base token of the vault (vault.token)
	// share = the share tokeni, i.e. the vault token itself
	// example: base is yCrv, share is yUSD

	bytes32 public constant TREE_KEY = "PooPoo";

	uint public totalBase;
	mapping (address => uint) public perUserBase;
	yVaultInterface public vault;
	DistribInterface public distributor;
	uint public lockedUntilBlock;
	bytes32 public secretHash;

	// events
	event Deposit(address indexed user, uint amountBase, uint amountShares, uint time);
	event Withdraw(address indexed user, uint amountBase, uint amountShares, uint time);
	event Locked(uint untilBlock, uint time);
	event Unlocked(uint time);

	// NOTE: we can only access the hash for the last 256 blocks (~ 55 minutes assuming 13.04s block times); we take the 40th to last block (~8 mins)
	// Note: must be at least 40 for security properties to hold! We use `blockhash(block.number - 40)` for entropy to mitigate reorgs to manipulate the winner,
	// but if the block taken is before the lock (LOCK_FOR_BLOCKS < 40), then the operator can manipulate the secret bsaed on the known block hash!
	// 46 blocks is around 10 minutes
	uint public constant LOCK_FOR_BLOCKS = 46;
	// The unlock safety is the amount of blocks we wait after lockedUntilBlock before *anyone* (not only the operator) can unlock
	uint public constant UNLOCK_SAFETY_BLOCKS = 200;

	using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
	SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

	constructor (yVaultInterface _vault, DistribInterface _distrib) public {
		vault = _vault;
		distributor = _distrib;
	}

	// Why we have locks:
	// Outcome (winner) is affected by three factors: the secret (which uses commit-reveal),
	// ...the entropy block (mined after the commit but before the reveal) and the overall sortition tree state (deposits)
	// Deposits/withdrawals get locked once the secret is committed, so that the operator can't manipulate results using their inside knowledge
	// of the secret, after the entropy block has been mined
	// Miners can't manipulate cause they don't know the secret

	// Why we can deposit/withdraw both base and shares
	// cause with different vaults different things make sense - eg with yUSD most people would be holding yUSD
	// while with USDT, most people might be holding USDT rather than the vault share token (yUSDT)
	function deposit(uint amountBase) external {
		require(lockedUntilBlock == 0, "pool is locked");
		require(IERC20(vault.token()).transferFrom(msg.sender, address(this), amountBase));
		vault.deposit(amountBase);

		setUserBase(msg.sender, perUserBase[msg.sender].add(amountBase));
		totalBase = totalBase.add(amountBase);

		emit Deposit(msg.sender, amountBase, toShares(amountBase), now);
	}

	function depositShares(uint amountShares) external {
		require(lockedUntilBlock == 0, "pool is locked");
		require(vault.transferFrom(msg.sender, address(this), amountShares));
		uint amountBase = toBase(amountShares);

		setUserBase(msg.sender, perUserBase[msg.sender].add(amountBase));
		totalBase = totalBase.add(amountBase);

		emit Deposit(msg.sender, amountBase, amountShares, now);
	}

	function withdraw(uint amountBase) external {
		require(lockedUntilBlock == 0, "pool is locked");
		require(perUserBase[msg.sender] > amountBase, "insufficient funds");
		uint amountShares = toShares(amountBase);
		vault.withdraw(amountShares);
		require(IERC20(vault.token()).transfer(msg.sender, amountBase));

		setUserBase(msg.sender, perUserBase[msg.sender].sub(amountBase));
		totalBase = totalBase.sub(amountBase);

		emit Withdraw(msg.sender, amountBase, amountShares, now);
	}

	function withdrawShares(uint amountShares) external {
		require(lockedUntilBlock == 0, "pool is locked");
		uint amountBase = toBase(amountShares);
		require(perUserBase[msg.sender] > amountBase, "insufficient funds");
		require(vault.transfer(msg.sender, amountShares));

		setUserBase(msg.sender, perUserBase[msg.sender].sub(amountBase));
		totalBase = totalBase.sub(amountBase);

		emit Withdraw(msg.sender, amountBase, amountShares, now);
	}

	function withdrawableShares(address user) external view returns (uint) {
		return toShares(perUserBase[user]);
	}

	function setUserBase(address user, uint base) internal {
		perUserBase[user] = base;
		sortitionSumTrees.set(TREE_KEY, base, bytes32(uint(user)));
	}

	//
	// Drawing system
	//
	function skimmableBase() public view returns (uint) {
		uint ourWorthInBase = toBase(vault.balanceOf(address(this)));
		// XXX what happens if somehow ourWorthInBase < totalBase - this shouldn't happen
		uint skimmable = ourWorthInBase.sub(totalBase);
		return skimmable;
	}

	function lock(bytes32 _secretHash) onlyOwner external {
		lockedUntilBlock = block.number + LOCK_FOR_BLOCKS;
		secretHash = _secretHash;
		emit Locked(lockedUntilBlock, now);
	}

	function draw(bytes32 secret) onlyOwner external {
		require(lockedUntilBlock > 0, "pool is not locked");
		require(block.number >= lockedUntilBlock, "pool is not unlockable yet");
		require(keccak256(abi.encodePacked(secret)) == secretHash, "secret does not match");

		unlockInternal();

		// skim the revenue and distribute it
		uint skimmableShares = toShares(this.skimmableBase());
		require(skimmableShares > 0, "no skimmable rewards");

		// XXX if the distributor wants to receive the base then we withdraw the shares and transfer skimmable
		require(vault.transfer(address(distributor), skimmableShares));

		uint rand = entropy(secret);
		address winner = winner(rand);
		distributor.distribute(rand, winner);

		// @TODO - or just use the distributor to mint, but that needs to be done safely (msg.sender == )
		//poo.mint(winner, pooPerDraw)
	}

	function unlock() external {
		require(lockedUntilBlock > 0, "pool is not locked");
		require(block.number >= (lockedUntilBlock + UNLOCK_SAFETY_BLOCKS), "pool is not publicly unlockable yet");
		unlockInternal();
	}

	function unlockInternal() internal {
		// unlock pool
		lockedUntilBlock = 0;
		secretHash = bytes32(0);
		emit Unlocked(now);
	}

	function winner(uint entropy) public view returns (address) {
		uint randomToken = UniformRandomNumber.uniform(entropy, totalBase);
		return address(uint256(sortitionSumTrees.draw(TREE_KEY, randomToken)));
	}

	function entropy(bytes32 secret) internal view returns (uint256) {
		return uint256(keccak256(abi.encodePacked(blockhash(block.number - 40), secret)));
	}

	function toShares(uint256 tokens) internal view returns (uint256) {
		return vault.totalSupply().mul(tokens).div(vault.balance());
	}

	function toBase(uint256 shares) internal view returns (uint256) {
		uint256 supply = vault.totalSupply();
		if (supply == 0 || shares == 0) {
			return 0;
		}
		return (vault.balance().mul(shares)).div(supply);
	}

	// admin only
	function changeDistributor(DistribInterface _dist) onlyOwner external {
		distributor = _dist;
	}
}
