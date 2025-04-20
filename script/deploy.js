// script/deploy.js
const hre = require("hardhat");

async function main() {
  console.log("Deploying contracts to", network.name, "...");

  // Get the ethers object and signer
  const { ethers } = hre;
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying with account:", await deployer.getAddress());
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");

  // Deploy TokenFactory
  console.log("Deploying TokenFactory...");
  const TokenFactory = await ethers.getContractFactory("TokenFactory");
  const tokenFactory = await TokenFactory.deploy();
  await tokenFactory.waitForDeployment();
  const tokenFactoryAddress = await tokenFactory.getAddress();
  console.log("TokenFactory deployed to:", tokenFactoryAddress);

  // Deploy a sample token if enough ETH
  if (balance > ethers.parseEther("1.0")) {
    console.log("Creating a sample token with 1 ETH...");
    try {
      const tx = await tokenFactory.createToken(
        "TugZone Demo Token",
        "TUG",
        "https://tugzone.io/metadata",
        { value: ethers.parseEther("1.0") }
      );
      console.log("Transaction hash:", tx.hash);
      
      const receipt = await tx.wait();
      console.log("Token creation confirmed in block", receipt.blockNumber);
      
      // Parse events to find token and pool addresses
      const tokenCreatedEvent = receipt.logs.find(log => {
        try {
          const parsed = tokenFactory.interface.parseLog(log);
          return parsed && parsed.name === "TokenCreated";
        } catch {
          return false;
        }
      });
      
      if (tokenCreatedEvent) {
        const parsedEvent = tokenFactory.interface.parseLog(tokenCreatedEvent);
        const tokenAddress = parsedEvent.args.tokenAddress;
        console.log("Demo token created at:", tokenAddress);
        
        // Get the pool address
        const poolAddress = await tokenFactory.tokenToPool(tokenAddress);
        console.log("Demo pool created at:", poolAddress);
      }
    } catch (error) {
      console.error("Error creating token:", error.message);
    }
  } else {
    console.log("Not enough ETH to create sample token. Skipping...");
  }

  // Print verification command
  console.log("\n----- Verification Command -----");
  console.log(`npx hardhat verify --network ${network.name} ${tokenFactoryAddress}`);
  console.log("-------------------------------");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
