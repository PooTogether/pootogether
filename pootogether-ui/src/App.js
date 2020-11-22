import './App.css';
import { Contract, getDefaultProvider, BigNumber, providers, utils } from 'ethers'
import { useState, useEffect } from 'react'
const { formatUnits, parseUnits } = utils
const provider = getDefaultProvider('homestead')

//const POO = new Contract('0x6A54EF1680f593574522422f3700194EC91CE57d', require('./interfaces/ERC20'), provider)
const PooTogether = new Contract('0x19a62938f67F2A44C47975Cc4c1132B7B75Aab76', require('./interfaces/PooTogether'), provider)
const Vault = new Contract('0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c', require('./interfaces/Vault'), provider)

// getPricePerFullShare

// TODOs
// cleanup
// depsit/withdraw
// cards styling
// errors
// connect walet
// approvals 
// better button styling
// github pages account, deploy
// check for cname leaks
// show shitcoin list
// footer
const colors = {
	text: '#ffffff',
	gradient1: '#a6fffb',
	gradient2: '#ff8cf1',
	border: '#ffffff'
}

async function getStats() {
	const [staked, skimmableBase] = await Promise.all([
		Vault.balanceOf(PooTogether.address),
		PooTogether.skimmableBase()
	])
	return { staked, skimmableBase }
}

function App() {
	const [stats, setStats] = useState({ staked: BigNumber.from(0), skimmableBase: BigNumber.from(0) })

	// @TODO
	const onError = e => console.error(e.message || e)

	useEffect(() => {
		getStats().then(setStats).catch(onError)
		setInterval(() => getStats().then(setStats).catch(onError), 30000)
	}, [])

	return (
		 <div className="App">
			<div class="poo"/>
			<Button label="connect wallet"/>
			<div style={{ flex: 1, display: 'flex', maxWidth: 850, margin: 'auto' }}>
				<Deposit/>
				<Withdraw/>
			</div>
			<RewardStats stats={stats}/>
		 </div>
	);
}

function Deposit() {
	return InOrOut({label: 'Deposit'})
}

function Withdraw() {
	return InOrOut({label: 'Withdraw'})
}

function InOrOut({ label, maxAmount, onAction }) {
	return (<div class="card" style={{ display: 'flex' }}>
		<div style={{ flex: 1 }}>
			<input type="number" value="0"></input>
			<div>Max amount: {label=='Deposit' ? 2000 : 0} yUSD</div>
		</div>
		<Button label={label}/>
	</div>)
}

// @TODO
function Button({ label }) {
	return (<button>{label}</button>)
}

function RewardStats({ stats }) {
	return (<div class="card stats">
		<p>Total staked: {formatUnits(stats.staked, 18)} yUSD</p>
		<p>Total prize pool: {formatUnits(stats.skimmableBase, 18)} yUSD</p>
		<p>Your share (chance to win): 0%</p>
	</div>)
}

// @TODO refactor
async function getSigner() {
        if (typeof window.ethereum !== 'undefined') await window.ethereum.enable()
        if (!window.web3) throw new Error('no web3')

        const provider = new providers.Web3Provider(window.web3.currentProvider)
        const signer = provider.getSigner()
        return signer
}


export default App;
