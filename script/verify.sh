#!/bin/bash
# script/verify.sh - Helper script for contract verification

CONTRACT_ADDRESS=$1
CONTRACT_NAME=${2:-"TokenFactory"}
CHAIN=${3:-"arbitrum-sepolia"}

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "Usage: ./script/verify.sh <contract_address> [contract_name] [chain]"
    echo "Example: ./script/verify.sh 0x123... TokenFactory arbitrum-sepolia"
    exit 1
fi

echo "Verifying $CONTRACT_NAME at $CONTRACT_ADDRESS on $CHAIN..."

# Generate flattened file for manual verification
echo "Creating flattened file..."
mkdir -p flattened
forge flatten src/$CONTRACT_NAME.sol > flattened/$CONTRACT_NAME.flat.sol

# Clean up SPDX license identifiers
sed -i '' '2,$ s/\/\/ SPDX-License-Identifier: MIT//' flattened/$CONTRACT_NAME.flat.sol

echo "Flattened file created at flattened/$CONTRACT_NAME.flat.sol"

# Try automated verification first
echo "Attempting automated verification..."
forge verify-contract --chain $CHAIN $CONTRACT_ADDRESS $CONTRACT_NAME --watch

echo "If automated verification failed, use the flattened file for manual verification:"
echo "1. Go to https://sepolia.arbiscan.io/verifyContract"
echo "2. Use 'Solidity (Single file)' option"
echo "3. Enter contract address: $CONTRACT_ADDRESS"
echo "4. Set compiler version to 0.8.20"
echo "5. Enable optimization (200 runs)"
echo "6. Paste the content of the flattened file"
