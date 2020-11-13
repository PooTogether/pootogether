import "./SortitionSumTreeFactory.sol";
import "./UniformRandomNumber.sol";
import "./SafeMath.sol";
import "./Interfaces.sol";
import "./Ownable.sol";

interface DistribInterface {
	function distribute(uint entropy, address winner) external;
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

	// NOTE: we can only access the hash for the last 256 blocks (~ 55 minutes assuming 13.04s block times); we take the 40th to last block (~8 mins)
	// we will lock for around 10 mins
	// Note: must be at least 40 for security properties to hold! We use `blockhash(block.number - 40)` for entropy to mitigate reorgs to manipulate the winner,
	// but if the block taken is before the lock (LOCK_FOR_BLOCKS < 40), then the operator can manipulate the secret bsaed on the known block hash!
	uint public constant LOCK_FOR_BLOCKS = 46;

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
		return toShares(perUserBase[msg.sender]);
	}

	function setUserBase(address user, uint base) internal {
		perUserBase[user] = base;
		sortitionSumTrees.set(TREE_KEY, base, bytes32(uint(user)));
	}

	// Drawing system
	function skimmableBase() public view returns (uint) {
		uint ourWorthInBase = toBase(vault.balanceOf(address(this)));
		uint skimmable = ourWorthInBase.sub(totalBase);
		return skimmable;
	}

	function lock(bytes32 _secretHash) onlyOwner external {
		lockedUntilBlock = block.number + lockedUntilBlock;
		secretHash = _secretHash;
	}

	function draw(bytes32 secret) onlyOwner external {
		require(lockedUntilBlock > 0, "pool is not locked");
		require(block.number >= lockedUntilBlock, "pool is not unlockable yet");
		require(keccak256(abi.encodePacked(secret)) == secretHash, "secret does not match");

		// unlock pool
		lockedUntilBlock = 0;
		secretHash = bytes32(0);

		// skim the revenue and distribute it
		uint skimmableShares = toShares(this.skimmableBase());

		// XXX if the distributor wants to receive the base then we withdraw the shares and transfer skimmable
		require(vault.transfer(address(distributor), skimmableShares));

		uint rand = entropy(secret);
		address winner = winner(rand);
		distributor.distribute(rand, winner);

		// @TODO 
		//poo.mint(winner, pooPerDraw)
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
