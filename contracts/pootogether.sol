pooltogether


// Terminology
// base = the base token of the vault (vault.token)
// share = the share tokeni, i.e. the vault token itself
// example: base is yCrv, share is yUSD

uint totalBase
mapping (address => uint) perUserBase

// @TODO you'd have to support depositing yUSD too

function deposit(uint amountBase) {
	vault.token.transferFrom(msg.sender, address(this), amountBase)
	vault.deposit(amountBase)
	perUserBase[msg.sender] = perUserBase[msg.sender].add(amountBase)
	totalBase = totalBase.add(amountBase)
}


function depositShares(uint amountShares) {
	vault.transferFrom(msg.sender, address(this), amountShares)
	uint amountBase = amountShares.mul(vault.getPricePerFullShare()).div(1e18)
	perUserBase[msg.sender] = perUserBase[msg.sender].add(amountBase)
	totalBase = totalBase.add(amountBase)
}

// the share value is vault.getPricePerFullShare() / 1e18
// multiplying it is .mul(vault.getPricePerFullShare()).div(1e18)
// and the opposite is .mul(1e18).div(vault.getPricePerFullShare())

// @TODO check if all base -> shares is dividing by shares and vice versa

// @TODO explain why we have two deposits and two withdrawals
function withdraw(uint amountBase) {
	require(perUserBase[msg.sender] > amountBase, 'insufficient funds')
	// XXX: if there is a rounding error here and we don't receive amountBase?
	vault.withdraw(amountBase.mul(1e18).div(vault.getPricePerFullShare()))
	vault.token.transfer(amountBase, msg.sender)
	perUserBase[msg.sender] = perUserBase[msg.sender].sub(amountBase)
	totalBase = totalBase.sub(amountBase)
}

function withdrawShares(uint amountShares) {
	uint amountBase = amountShares.mul(vault.getPricePerFullShare()).div(1e18)
	require(perUserBase[msg.sender] > amountBase, 'insufficient funds')
	vault.transfer(amountShares, msg.sender)
	perUserBase[msg.sender] = perUserBase[msg.sender].sub(amountBase)
	totalBase = totalBase.sub(amountBase)
}

draw()
	require(/* no recent draw */)

	uint pricePerFullShare = vault.getPricePerFullShare()
	uint ourWorthInBase = vault.balanceOf(address(this)).mul(pricePerFullShare).div(1e18)
	uint skimmable = ourWorthInBase.sub(totalBase)
	uint skimmableShares = skimmable.mul(1e18).div(pricePerFullShare)

	// XXX if the distributor wants to receive the base then we withdraw the shares and transfer skimmable
	vault.tranfer(skimmableShares, distributor)


	address winner = chooseWinner(chainlink.rand(), msg.signature)
	distributor.distribute(chainlink.rand(), winner)
	poo.mint(winner, pooPerDraw)

	/// XXX alternatively, leave it at distributor.distribute()


// admin only

// yvaultinterface https://github.com/pooltogether/pooltogether-pool-contracts/blob/master/contracts/prize-pool/yearn/yVaultPrizePool.sol

  function toShares(uint256 tokens) internal view returns (uint256) {
    /**
      ex. rate = tokens / shares
      => shares = shares_total * (tokens / tokens total)
     */
    return vault.totalSupply().mul(tokens).div(vault.balance());
  }

  function toBase(uint256 shares) internal view returns (uint256) {
    uint256 ts = vault.totalSupply();
    if (ts == 0 || shares == 0) {
      return 0;
    }
    return (vault.balance().mul(shares)).div(ts);
  }