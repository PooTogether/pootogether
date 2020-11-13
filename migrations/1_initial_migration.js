const PooTogether = artifacts.require("PooTogether");
const Distributor = artifacts.require("Distributor");

module.exports = async function (deployer) {
	await deployer.deploy(Distributor);
	await deployer.deploy(PooTogether, "0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c", Distributor.address);
	console.log(PooTogether.address, Distributor.address)
};
