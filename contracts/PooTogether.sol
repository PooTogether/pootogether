// SPDX-License-Identifier: UNLICENSED
// Copyright 2020 PooDaddy
// PooTogether: the best no-loss shitcoin lottery
// https://www.pootogether.com
// https://twitter.com/pootogether
pragma solidity ^0.6.12;
import "./SortitionSumTreeFactory.sol";
import "./UniformRandomNumber.sol";
import "./SafeMath.sol";
import "./Interfaces.sol";
import "./Ownable.sol";

interface DistribInterface {
	function distribute(address inputToken, uint entropy, address winner) external;
}

contract PooTogether is Ownable {
	using SafeMath for uint;

	// Terminology
	// base = the base token of the vault (vault.token)
	// share = the share tokeni, i.e. the vault token itself
	// example: base is yCrv, share is yUSD
	uint public totalBase;
	mapping (address => uint) public perUserBase;
	yVaultInterface public immutable vault;
	DistribInterface public distributor;
	uint public unlocksAtBlock;
	bytes32 public secretHash;

	// events
	event Deposit(address indexed user, uint amountBase, uint amountShares, uint time);
	event Withdraw(address indexed user, uint amountBase, uint amountShares, uint time);
	event Locked(uint unlocksAtBlock, uint time);
	event Draw(address winner, uint amountShares, uint time);

	// We use `blockhash(unlocksAtBlock - (BLOCKS_WAIT_TO_DRAW + BLOCKS_DRAW_WINDOW))` for additional entropy for two reasons
	// 1) to mitigate reorgs to manipulate the winner - we will have at least BLOCKS_WAIT_TO_DRAW passed before draw opens
	// 2) once the operator commits to a secret, unlocksAtBlock gets set so this block number is fixed, so the operator cannot manipulate that

	// After we lock, the 10th block is the one we use for randomness
	// The total draw window is 46 blocks - that's around 10 minutes
	uint public constant BLOCK_FOR_RANDOMNESS = 10;
	uint public constant BLOCKS_WAIT_TO_DRAW = 36;
	// The pool unlocks automatically w/o a draw if the draw hasn't happened in a certain amount of time, ensuring users can withdraw their funds
	uint public constant BLOCKS_DRAW_WINDOW = 200;
	uint public constant LOCK_FOR_BLOCKS = BLOCK_FOR_RANDOMNESS + BLOCKS_WAIT_TO_DRAW + BLOCKS_DRAW_WINDOW;
	// NOTE: we can only access the hash for the last 256 blocks (~ 55 minutes assuming 13.04s block times)
	// This must be true: LOCKS_FOR_BLOCKS < 256, to ensure the operator cannot draw when blockhash() returns zero
	// Finally, we have the number of blocks that need to pass from the unlock point to a new lock being possible
	uint public constant BLOCKS_BETWEEN_LOCKS = 1000;


	bytes32 public constant TREE_KEY = "PooPoo";

	using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
	SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

	constructor (yVaultInterface _vault, DistribInterface _distrib) public {
		vault = _vault;
		distributor = _distrib;
		sortitionSumTrees.createTree(TREE_KEY, 4);
	}

	// Why we have locks:
	// Outcome (winner) is affected by three factors: the secret (which uses commit-reveal),
	// ...the entropy block (mined after the commit but before the reveal) and the overall sortition tree state (deposits)
	// Deposits/withdrawals get locked once the secret is committed, so that the operator can't manipulate results using their inside knowledge
	// of the secret, after the entropy block has been mined
	// Miners can't manipulate cause they don't know the secret
	function deposit(uint amountShares) external {
		require(block.number >= unlocksAtBlock, "pool is locked");
		uint amountBase = toBase(amountShares);

		setUserBase(msg.sender, perUserBase[msg.sender].add(amountBase));
		totalBase = totalBase.add(amountBase);

		require(vault.transferFrom(msg.sender, address(this), amountShares));

		emit Deposit(msg.sender, amountBase, amountShares, now);
	}

	function withdraw(uint amountShares) external {
		require(block.number >= unlocksAtBlock, "pool is locked");
		uint amountBase = toBase(amountShares);
		require(perUserBase[msg.sender] >= amountBase, "insufficient funds");

		setUserBase(msg.sender, perUserBase[msg.sender].sub(amountBase));
		totalBase = totalBase.sub(amountBase);

		require(vault.transfer(msg.sender, amountShares));

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
		// This will fail if somehow ourWorthInBase < totalBase - this shouldn't happen, unless something goes wrong with yearn
		// if this DOES happen, draws won't be possible but withdrawing your funds will be
		uint skimmable = ourWorthInBase.sub(totalBase);
		return skimmable;
	}

	function lock(bytes32 _secretHash) onlyOwner external {
		require(block.number > (unlocksAtBlock + BLOCKS_BETWEEN_LOCKS), "pool has been recently locked");
		unlocksAtBlock = block.number + LOCK_FOR_BLOCKS;
		secretHash = _secretHash;
		emit Locked(unlocksAtBlock, now);
	}

	function draw(bytes32 secret) onlyOwner external {
		require(block.number < unlocksAtBlock, "pool is not locked");
		require(block.number >= unlocksAtBlock.sub(BLOCKS_DRAW_WINDOW), "pool is not in draw window yet");
		require(keccak256(abi.encodePacked(secret)) == secretHash, "secret does not match");

		// Needs to be called before setting unlocksAtBlock 
		bytes32 hash = blockhash(unlocksAtBlock.sub(BLOCKS_WAIT_TO_DRAW + BLOCKS_DRAW_WINDOW));
		require(hash != 0, "blockhash returned 0"); // should never happen if all constants are correct (see above)
		uint rand = entropy(hash, secret);

		unlocksAtBlock = block.number;
		secretHash = bytes32(0);

		// skim the revenue and distribute it
		// Note: if there are no participants, this would always be 0
		uint skimmableShares = toShares(this.skimmableBase());
		require(skimmableShares > 0, "no skimmable rewards");

		// Send the tokens to the distributor directly, and it will spend them on .distribute() - cheaper than approve, transferFrom
		require(vault.transfer(address(distributor), skimmableShares));

		address winner = winner(rand);
		distributor.distribute(address(vault), rand, winner);

		emit Draw(winner, skimmableShares, now);
	}

	function winner(uint entropy) public view returns (address) {
		uint randomToken = UniformRandomNumber.uniform(entropy, totalBase);
		return address(uint256(sortitionSumTrees.draw(TREE_KEY, randomToken)));
	}

	function entropy(bytes32 sourceA, bytes32 sourceB) internal pure returns (uint256) {
		return uint256(keccak256(abi.encodePacked(sourceA, sourceB)));
	}

	function toShares(uint256 tokens) internal view returns (uint256) {
		return vault.totalSupply().mul(tokens).div(vault.balance());
	}

	function toBase(uint256 shares) internal view returns (uint256) {
		uint256 supply = vault.totalSupply();
		if (supply == 0 || shares == 0) return 0;
		return (vault.balance().mul(shares)).div(supply);
	}

	// admin only (besides lock/draw)
	function changeDistributor(DistribInterface _dist) onlyOwner external {
		distributor = _dist;
	}
	// recover any erroneously sent tokens
	function recoverTokens(IERC20 token, uint amount) onlyOwner external {
		require(address(token) != address(vault), "cannot withdraw vault tokens");
		// no need to require() this - we don't care whether it was successful or not
		token.transfer(msg.sender, amount);
	}
}
