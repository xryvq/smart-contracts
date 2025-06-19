#!/bin/bash

echo "🔧 Generating ABI files for Levra Protocol..."

# Create abis directory if it doesn't exist
mkdir -p abis

# Generate ABI files in proper JSON format from build artifacts
echo "Extracting MockUSDC ABI..."
jq '.abi' out/MockUSDC.sol/MockUSDC.json > abis/MockUSDC.json

echo "Extracting LendingPool ABI..."
jq '.abi' out/LendingPool.sol/LendingPool.json > abis/LendingPool.json

echo "Extracting CollateralManager ABI..."
jq '.abi' out/CollateralManager.sol/CollateralManager.json > abis/CollateralManager.json

echo "Extracting LoanManager ABI..."
jq '.abi' out/LoanManager.sol/LoanManager.json > abis/LoanManager.json

echo "Extracting RestrictedWalletFactory ABI..."
jq '.abi' out/RestrictedWalletFactory.sol/RestrictedWalletFactory.json > abis/RestrictedWalletFactory.json

echo "Extracting RestrictedWallet ABI..."
jq '.abi' out/RestrictedWallet.sol/RestrictedWallet.json > abis/RestrictedWallet.json

echo ""
echo "✅ ABI generation completed!"
echo "📁 ABI files saved in ./abis/ directory:"
ls -la abis/

echo ""
echo "🌐 Contract Addresses (Arbitrum Sepolia):"
echo "Mock USDC:               0xE61995E2728bd2d2B1abd9e089213B542db7916A"
echo "LendingPool:             0xa7e82B23460233c71e8553387b2D870003A34A50"
echo "CollateralManager:       0x23C369A4991a477E4B9DD13F179b2e68203AbC1D"
echo "RestrictedWalletFactory: 0x752168dD102D1C4b9390aB6abf3Ec39f2164aD11"
echo "LoanManager:             0x7364EeB345989C757616988B70976BBa163B7571"
echo ""
echo "📖 Ready for frontend integration!" 