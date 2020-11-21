import logo from './logo.svg';
import './App.css';
import ethers from 'ethers';
import { Contract, getDefaultProvider } from 'ethers';

const provider = getDefaultProvider('homestead')

//const POO = new Contract('0x6A54EF1680f593574522422f3700194EC91CE57d', require('./interfaces/ERC20').abi, provider)
const PooTogether = new Contract('0x19a62938f67F2A44C47975Cc4c1132B7B75Aab76', require('./interfaces/PooTogether').abi, provider)

// const Vault

function App() {
  return (
    <div className="App">
      <header className="App-header">
        <img src={logo} className="App-logo" alt="logo" />
        <p>
          Edit <code>src/App.js</code> and save to reload.
        </p>
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
