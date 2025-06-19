// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/LendingPool.sol";
import "../src/CollateralManager.sol";
import "../src/RestrictedWalletFactory.sol";
import "../src/LoanManager.sol";

/**
 * @title Deploy
 * @dev Optimized deployment script for Levra lending system with gas optimization
 */
contract Deploy is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== LEVRA LENDING SYSTEM DEPLOYMENT ===");
        console.log("Deployer address:", deployer);
        console.log("Network: Arbitrum Sepolia");
        console.log("Gas Price: 0.1 gwei");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Mock USDC
        console.log("1. Deploying Mock USDC...");
        MockUSDC mockUSDC = new MockUSDC();
        console.log("   Mock USDC deployed at:", address(mockUSDC));
        
        // 2. Deploy LendingPool
        console.log("2. Deploying LendingPool...");
        LendingPool lendingPool = new LendingPool(
            address(mockUSDC),
            "Levra Vault Shares",
            "lvUSDC"
        );
        console.log("   LendingPool deployed at:", address(lendingPool));
        
        // 3. Deploy CollateralManager
        console.log("3. Deploying CollateralManager...");
        CollateralManager collateralManager = new CollateralManager(
            address(mockUSDC),
            address(lendingPool)
        );
        console.log("   CollateralManager deployed at:", address(collateralManager));
        
        // 4. Deploy RestrictedWalletFactory
        console.log("4. Deploying RestrictedWalletFactory...");
        RestrictedWalletFactory walletFactory = new RestrictedWalletFactory();
        console.log("   RestrictedWalletFactory deployed at:", address(walletFactory));
        
        // 5. Deploy LoanManager
        console.log("5. Deploying LoanManager...");
        LoanManager loanManager = new LoanManager(
            address(lendingPool),
            address(collateralManager),
            address(walletFactory),
            address(mockUSDC)
        );
        console.log("   LoanManager deployed at:", address(loanManager));
        
        // 6. Setup integrations
        console.log("6. Setting up integrations...");
        lendingPool.setLoanManager(address(loanManager));
        lendingPool.setCollateralManager(address(collateralManager));
        collateralManager.setLoanManager(address(loanManager));
        
        // 7. Mint some USDC to deployer for testing
        console.log("7. Minting test USDC...");
        mockUSDC.mint(deployer, 1000000 * 10**6); // 1M USDC for testing
        
        vm.stopBroadcast();
        
        // 8. Deployment Summary
        console.log("\\n=== DEPLOYMENT SUMMARY ===");
        console.log("Mock USDC:              ", address(mockUSDC));
        console.log("LendingPool:            ", address(lendingPool));
        console.log("CollateralManager:      ", address(collateralManager));
        console.log("RestrictedWalletFactory:", address(walletFactory));
        console.log("LoanManager:            ", address(loanManager));
        
        // 9. System Configuration
        console.log("\\n=== SYSTEM CONFIGURATION ===");
        console.log("USDC Decimals:           ", mockUSDC.decimals());
        console.log("Max Gas Limit:          30M");
        console.log("Estimated Total Gas:    ~12M");
        
        console.log("\\nDeployment completed successfully!");
        console.log("IMPORTANT: Use gas limit 500k-1M for initiateLoan function");
    }
} 