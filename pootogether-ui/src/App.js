import './App.css';
import { Contract, getDefaultProvider, BigNumber, utils } from 'ethers'
import { useState, useEffect } from 'react'
const { formatUnits, parseUnits } = utils
const provider = getDefaultProvider('homestead')

//const POO = new Contract('0x6A54EF1680f593574522422f3700194EC91CE57d', require('./interfaces/ERC20'), provider)
const PooTogether = new Contract('0x19a62938f67F2A44C47975Cc4c1132B7B75Aab76', require('./interfaces/PooTogether'), provider)
const Vault = new Contract('0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c', require('./interfaces/Vault'), provider)

// getPricePerFullShare

function App() {
	const [stats, setStats] = useState({ staked: BigNumber.from(0) })

	useEffect(() => {
		(async () => {
			setStats({ staked: await Vault.balanceOf(PooTogether.address) })
		})()
	}, [])

	return (
		 <div className="App">
			<header className="App-header">
			  <p>{formatUnits(stats.staked, 18)}</p>
			  <a
				 className="App-link"
				 href="https://reactjs.org"
				 target="_blank"
				 rel="noopener noreferrer"
			  >
				 Learn React
			  </a>
			</header>
		 </div>
	);
}

export default App;
