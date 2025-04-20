// script/verify.js
const hre = require("hardhat");

async function main() {
  // Get contract address from command line
  const contractAddress = process.argv[2];
  if (!contractAddress) {
    console.error("Please provide a contract address");
    process.exit(1);
  }

  console.log(`Verifying contract at ${contractAddress} on ${network.name}...`);
  
  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: []
    });
    console.log("Contract verified successfully");
  } catch (error) {
    console.error("Verification failed:", error.message);
    
    // If verification fails, create a flattened file for manual verification
    console.log("\nGenerating flattened contract for manual verification...");
    
    // Create directory if it doesn't exist
    const fs = require("fs");
    if (!fs.existsSync("./flattened")) {
      fs.mkdirSync("./flattened");
    }
    
    // Try to determine which contract to flatten
    console.log("Flattening TokenFactory...");
    await hre.run("flatten", {
      files: ["./src/TokenFactory.sol"],
      output: "./flattened/TokenFactory.flat.sol"
    });
    
    // Clean up SPDX identifiers
    const flattenedFile = fs.readFileSync("./flattened/TokenFactory.flat.sol", "utf8");
    const cleanedFile = flattenedFile.replace(/\/\/ SPDX-License-Identifier: MIT\n/g, "");
    fs.writeFileSync(
      "./flattened/TokenFactory.flat.sol",
      "// SPDX-License-Identifier: MIT\n" + cleanedFile
    );
    
    console.log("Flattened contract saved to ./flattened/TokenFactory.flat.sol");
    console.log("\nFor manual verification:");
    console.log("1. Go to https://sepolia.arbiscan.io/verifyContract");
    console.log("2. Use 'Solidity (Single file)' option");
    console.log("3. Enter contract address:", contractAddress);
    console.log("4. Set compiler version to 0.8.20");
    console.log("5. Enable optimization (200 runs)");
    console.log("6. Paste the content of the flattened file");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
