require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

require('dotenv').config();
const env = process.env;

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4"
      },
      {
        version: "0.5.17",
        settings: { 
          optimizer: {
            enabled: true,
            runs: 200
          }
        } 
      },
      {
        version: "0.6.12",
        settings: { 
          optimizer: {
            enabled: true,
            runs: 200
          }
        } 
      }
    ]
  },
  networks: {
    bscTest: {
      url: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
      accounts: [`0x${env.PK1}`]
    },
    REI_MAIN: {
      url: `https://rpc.rei.network/`,
      accounts: [`0x${env.PK1}`]
    }
  }
};
