import "./App.css";
import { Contract, getDefaultProvider, BigNumber, providers, utils } from "ethers"
import { useState, useEffect } from "react"
const { formatUnits, parseUnits } = utils
const provider = getDefaultProvider("homestead")

//const POO = new Contract("0x6A54EF1680f593574522422f3700194EC91CE57d", require("./interfaces/ERC20"), provider)
const PooTogether = new Contract("0x19a62938f67F2A44C47975Cc4c1132B7B75Aab76", require("./interfaces/PooTogether"), provider)
const Vault = new Contract("0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c", require("./interfaces/Vault"), provider)

// getPricePerFullShare

// TODOs
// github pages account, deploy
// check for cname leaks
// show shitcoin list?
// footer

async function getStats() {
	const [staked, totalBase, skimmableBase] = await Promise.all([
		Vault.balanceOf(PooTogether.address),
		PooTogether.totalBase(),
		PooTogether.skimmableBase()
	])
	return { staked, totalBase, skimmableBase, loading: false }
}

function App() {
	const [stats, setStats] = useState(null)

	const [errMsg, setErrMsg] = useState(null)
	const onError = e => {
		console.error(e)
		if (e && e.message.startsWith("failed to meet quorum")) return
		setErrMsg((e && e.message) ? e.message : "unknown error occured")
	}
	const errWrapper = func => (...arg) => {
		setErrMsg(null)
		func.apply(null, arg).catch(onError)
	}

	const [wallet, setWallet] = useState(null)
	const getWalletInfo = async signer => {
		const address = await signer.getAddress()
		const [userBase, maxWithdraw, maxDeposit] = await Promise.all([
			PooTogether.perUserBase(address),
			PooTogether.withdrawableShares(address),
			Vault.balanceOf(address)
		])
		return { signer, address, userBase, maxWithdraw, maxDeposit }
	}
	const connectWallet = () => getSigner()
		.then(getWalletInfo)
		.then(setWallet)
		.catch(onError)
	useEffect(() => {
		getStats().then(setStats).catch(onError)

		const updateWalletIfAny = wallet
			? () => getWalletInfo(wallet.signer).then(setWallet)
			: () => null
		const interval = setInterval(() => getStats().then(setStats).then(updateWalletIfAny).catch(onError), 20000)
		return () => clearInterval(interval)
	}, [wallet])

	return (
		 <div className="App">
			<a href="https://medium" target="_blank" rel="noreferrer noopener"><div className="poo"/></a>
			{ wallet ?
				(<h2>Connected wallet: {wallet.address}</h2>) :
				(<Button label="connect wallet" onClick={connectWallet}/>)
			}
			{ errMsg ? (<h2 className="error">Error: {errMsg}</h2>) : null }
			<div style={{ flex: 1, display: "flex", maxWidth: 900, margin: "auto" }}>
				<Deposit wallet={wallet} errWrapper={errWrapper}/>
				<Withdraw wallet={wallet} errWrapper={errWrapper}/>
			</div>
			<RewardStats stats={stats} wallet={wallet}/>
		 </div>
	);
}

function Deposit({ wallet, errWrapper }) {
	const onAction = errWrapper(async toDeposit => {
		if (!wallet) throw new Error("no wallet connected")
		const TogetherWithSigner = new Contract(PooTogether.address, PooTogether.interface, wallet.signer)
		const depositAmount = parseUnits(toDeposit, 18)
		const allowance = await Vault.allowance(wallet.address, PooTogether.address)
		if (allowance.lt(depositAmount)) {
			const VaultWithSigner = new Contract(Vault.address, Vault.interface, wallet.signer)
			// same value that iearnfinance is using
			await VaultWithSigner.approve(PooTogether.address, parseUnits("999999999999", 18))
			await TogetherWithSigner.deposit(depositAmount, { gasLimit: 350000 })
		} else {
			await TogetherWithSigner.deposit(depositAmount)
		}
	})
	return InOrOut({ label: "Deposit", maxAmount: wallet ? wallet.maxDeposit : BigNumber.from(0), onAction })
}

function Withdraw({ wallet, errWrapper }) {
	const onAction = errWrapper(async toWithdraw => {
		if (!wallet) throw new Error("no wallet connected")
		const TogetherWithSigner = new Contract(PooTogether.address, PooTogether.interface, wallet.signer)
		await TogetherWithSigner.withdraw(parseUnits(toWithdraw, 18))
	})
	return InOrOut({ label: "Withdraw", maxAmount: wallet ? wallet.maxWithdraw : BigNumber.from(0), onAction })
}

function InOrOut({ label, maxAmount, onAction }) {
	const [val, setVal] = useState("0")
	const onChange = event => {
		try { parseUnits(event.target.value, 18) } catch { return }
		const val = event.target.value
		setVal(val < 0 ? -val : val)
	}
	const setToMax = () => setVal(formatUnits(maxAmount, 18))
	return (<div className="card" style={{ display: "flex" }}>
		<div style={{ flex: 1 }}>
			<input type="number" value={val} onChange={onChange}></input>
			<div className="clickable" onClick={setToMax}>Max amount: {formatyUSD(maxAmount)} yUSD</div>
		</div>
		<Button label={label} onClick={() => onAction(val)}/>
	</div>)
}

function Button({ label, onClick }) {
	return (<button onClick={onClick}>{label}</button>)
}

function RewardStats({ stats, wallet }) {
	if (!stats) return (<div className="card stats"><h2>Loading...</h2></div>)
	const chanceToWin = wallet
		? wallet.userBase.mul(10000).div(stats.totalBase).toNumber()/100
		: 0
	return (<div className="card stats">
		<p>Total staked: {formatyUSD(stats.staked)} yUSD</p>
		<p>Total prize pool: {formatyUSD(stats.skimmableBase)} yCRV</p>
		<p>Your share (chance to win): {chanceToWin.toFixed(2)}%</p>
	</div>)
}

function formatyUSD(x) {
	const den = BigNumber.from(1e14)
	return formatUnits(x.div(den), 4)
}

// @TODO refactor
async function getSigner() {
        if (typeof window.ethereum !== "undefined") await window.ethereum.enable()
        if (!window.web3) throw new Error("no web3")

        const provider = new providers.Web3Provider(window.web3.currentProvider)
        const signer = provider.getSigner()
        return signer
}


export default App;
