#!/usr/bin/node

const ethers = require('ethers')
const fs = require('fs')
const mnemonic = fs.readFileSync('.secret').toString().trim()

const { randomBytes, parseUnits, formatUnits, hexlify, keccak256 } = ethers.utils

const PooTogether = require('../build/contracts/PooTogether')

const DRAW_THRESHOLD = parseUnits('0.15', 18)

async function main() {
	const provider = ethers.providers.getDefaultProvider('homestead')
	// hack cause wallet.provider = does not work
	const walletTemp = new ethers.Wallet.fromMnemonic(mnemonic)
	const wallet = new ethers.Wallet(walletTemp.privateKey, provider)
	const Poo = new ethers.Contract(PooTogether.networks['1'].address, PooTogether.abi, wallet)
	// @TODO check if there's enough drwa
	const skimmable = await Poo.skimmableBase()
	console.log(`Total prize: ${formatUnits(skimmable, 18)} yCrv`)
	if (skimmable.lt(DRAW_THRESHOLD)) {
		console.log(`Prize under threshold, nothing to do!`)
		return
	}
	const lockedUntilBlock = await Poo.lockedUntilBlock()
	if (lockedUntilBlock.gt(0)) {
		console.log(`Pool already locked`)
		return
	}
	const secret = randomBytes(32)
	const secretHash = keccak256(secret)
	console.log(`secret: ${hexlify(secret)}`)
	console.log(`secret hash: ${hexlify(secretHash)}`)
	const tx = await Poo.lock(secretHash)
	console.log(await tx.wait())
	await new Promise(r => setTimeout(r, 720000)) // 12 mins
	const txDraw = await Poo.draw(secret)
	console.log(await tx.wait())
}


main()
	.catch(e => {
		console.error(e)
		process.exit(1)
	})
