// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);


  const investorAddr = "0x5e78aC44ac59a8E001ba7A3D5Eb078c532Cf2759";
  const requiredSignatories = ["0x06677520c1449D9977E7A245f0797A65e7efF219","0x4974946794E3752EBf1Bede6de25F0997A611BA8","0x9B09921538091680E6f29d2347bcdece01FC5501"];
  const beneficiary = "0x3cDbB3BC15A031A1A3637F7c06563a7E6b2ac7D4";
  const periodInSeconds = 31536000;
  const oortPerBlock =  21875000000000000000;
  const startBlock = 1906755;
  const weth = "0x726A343864Ddf968631b8E034742D7a7A5053B76";
  const rei_addr = "0x2Afc53F7582e4Bfd55425A0Eca120F44C202582F";

  // const MultiSigPeriodicTimeLock = await hre.ethers.getContractFactory("MultiSigPeriodicTimeLock");
  // const multiSigPeriodicTimeLock = await MultiSigPeriodicTimeLock.deploy(beneficiary,periodInSeconds,requiredSignatories);
  // console.log('multiSigPeriodicTimeLock address:',multiSigPeriodicTimeLock.address);

  // const OortToken = await hre.ethers.getContractFactory("OortToken");
  // const oortToken = await OortToken.deploy(multiSigPeriodicTimeLock.address,investorAddr,requiredSignatories);
  // console.log('oortToken address:',oortToken.address);

  // const MasterChef = await hre.ethers.getContractFactory("MasterChef");
  // const masterChef = await MasterChef.deploy(oortToken.addres,oortPerBlock,startBlock);
  // console.log('masterChef address:',masterChef.address);

  // const MasterChef = await hre.ethers.getContractFactory("MasterChef");
  // const oortToken = await MasterChef.deploy(oortToken.addres,oortPerBlock,startBlock);
  // console.log('oortToken address:',oortToken.address);

  // const OortswapFactory = await hre.ethers.getContractFactory("OortswapFactory");
  // const oortswapFactory = await OortswapFactory.deploy(deployer.address);
  // console.log('oortswapFactory address:',oortswapFactory.address);

  // const OortRouter = await hre.ethers.getContractFactory("OortRouter");
  // const oortRouter = await OortRouter.deploy(deployer.address);
  // console.log('oortRouter address:',oortRouter.address,weth);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
