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

	uint totalBase;
	mapping (address => uint) perUserBase;
	yVaultInterface vault;
	DistribInterface distributor;

	using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
	SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

	constructor (yVaultInterface _vault, DistribInterface _distrib) public {
		vault = _vault;
		distributor = _distrib;
	}

	// @TODO you'd have to support depositing yUSD too

	function deposit(uint amountBase) external {
		require(IERC20(vault.token()).transferFrom(msg.sender, address(this), amountBase));
		vault.deposit(amountBase);
		setUserBase(msg.sender, perUserBase[msg.sender].add(amountBase));
		totalBase = totalBase.add(amountBase);
		// @TODO emit
	}

	function depositShares(uint amountShares) external {
		require(vault.transferFrom(msg.sender, address(this), amountShares));
		uint amountBase = toBase(amountShares);
		setUserBase(msg.sender, perUserBase[msg.sender].add(amountBase));
		totalBase = totalBase.add(amountBase);
	}

	// @TODO explain why we have two deposits and two withdrawals
	function withdraw(uint amountBase) external {
		require(perUserBase[msg.sender] > amountBase, 'insufficient funds');
		// XXX: if there is a rounding error here and we don't receive amountBase?
		vault.withdraw(toShares(amountBase));
		require(IERC20(vault.token()).transfer(msg.sender, amountBase));
		setUserBase(msg.sender, perUserBase[msg.sender].sub(amountBase));
		totalBase = totalBase.sub(amountBase);
	}

	function withdrawShares(uint amountShares) external {
		uint amountBase = toBase(amountShares);
		require(perUserBase[msg.sender] > amountBase, 'insufficient funds');
		require(vault.transfer(msg.sender, amountShares));
		setUserBase(msg.sender, perUserBase[msg.sender].sub(amountBase));
		totalBase = totalBase.sub(amountBase);
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

	function draw() onlyOwner external {
		//require(/* no recent draw */)
		uint skimmableShares = toShares(this.skimmableBase());

		// XXX if the distributor wants to receive the base then we withdraw the shares and transfer skimmable
		require(vault.transfer(address(distributor), skimmableShares));

		uint rand = entropy();
		address winner = winner(rand);
		distributor.distribute(rand, winner);
		
		// @TODO 
		//poo.mint(winner, pooPerDraw)
	}

	function winner(uint entropy) public view returns (address) {
		return address(uint256(sortitionSumTrees.draw(TREE_KEY, entropy)));
	}

	function entropy() internal view returns (uint256) {
		return uint256(blockhash(block.number - 1)/* ^ secret*/);
	}


	// the share value is vault.getPricePerFullShare() / 1e18
	// multiplying it is .mul(vault.getPricePerFullShare()).div(1e18)
	// and the opposite is .mul(1e18).div(vault.getPricePerFullShare())

	// @TODO check if all base -> shares is dividing by shares and vice versa
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
