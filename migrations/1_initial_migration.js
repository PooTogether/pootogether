const POO = artifacts.require("POO");
const PooTogether = artifacts.require("PooTogether");
const Distributor = artifacts.require("Distributor");

module.exports = async function (deployer) {
	const yusdVault = "0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c"
	await deployer.deploy(POO, { gas: 1200000 });
	await deployer.deploy(Distributor, { gas: 600000 });
	await deployer.deploy(PooTogether, yusdVault, Distributor.address, { gas: 2600000 });
};
