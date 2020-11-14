#!/usr/bin/node

const ethers = require('ethers')
const fs = require('fs')
const mnemonic = fs.readFileSync('.secret').toString().trim()

const { randomBytes } = ethers.utils

const PooTogether = require('../build/contracts/PooTogether')

async function main() {
	const provider = ethers.providers.getDefaultProvider('homestead')
	// hack cause wallet.provider = does not work
	const walletTemp = new ethers.Wallet.fromMnemonic(mnemonic)
	const wallet = new ethers.Wallet(walletTemp.privateKey, provider)
	const Poo = new ethers.Contract(PooTogether.networks['1'].address, PooTogether.abi, wallet)
	// @TODO check if there's enough drwa
	const skimmable = await Poo.skimmableBase()
	console.log(skimmable)
	//const tx = await Poo.lock()
	//const tx = 
	// @TODO provider
	// @TODO derivation
}


main()
	.then(() => console.log(`Draw done!`))
	.catch(e => {
		console.error(e)
		process.exit(1)
	})
