// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/LoanManager.sol";

/**
 * @title TestGas
 * @dev Script untuk testing gas consumption dari initiateLoan function
 */
contract TestGas is Script {
    
    address constant MOCK_USDC = 0xCafbd1e6875a1dEfC6a7a3Aa1283e99bc5B3091D;
    address constant LOAN_MANAGER = 0x86f637c568f57E2e41eA69e1ceb9270faD7108F7;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== GAS ESTIMATION TEST ===");
        console.log("Tester address:", deployer);
        
        MockUSDC mockUSDC = MockUSDC(MOCK_USDC);
        LoanManager loanManager = LoanManager(LOAN_MANAGER);
        
        // Test parameters
        uint256 desiredLoanAmount = 1000 * 10**6; // $1000 USDC
        uint256 requiredCollateral = 200 * 10**6; // $200 USDC (20%)
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Ensure we have enough USDC
        uint256 currentBalance = mockUSDC.balanceOf(deployer);
        console.log("Current USDC balance:", currentBalance);
        
        if (currentBalance < requiredCollateral) {
            console.log("Minting additional USDC...");
            mockUSDC.mint(deployer, requiredCollateral);
        }
        
        // 2. Approve USDC for loan manager
        console.log("Approving USDC...");
        mockUSDC.approve(address(loanManager), requiredCollateral);
        
        // 3. Record gas before transaction
        uint256 gasBefore = gasleft();
        console.log("Gas before initiateLoan:", gasBefore);
        
        // 4. Call initiateLoan with gas estimation
        console.log("Calling initiateLoan...");
        console.log("Desired loan amount:", desiredLoanAmount);
        console.log("Required collateral:", requiredCollateral);
        
        try loanManager.initiateLoan{gas: 1000000}(desiredLoanAmount) returns (uint256 loanId) {
            uint256 gasAfter = gasleft();
            uint256 gasUsed = gasBefore - gasAfter;
            
            console.log("SUCCESS!");
            console.log("Loan ID:", loanId);
            console.log("Gas used:", gasUsed);
            console.log("Estimated gas limit needed:", gasUsed + 100000); // Add buffer
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with low-level error");
        }
        
        vm.stopBroadcast();
        
        console.log("\\n=== RECOMMENDATIONS ===");
        console.log("1. Use gas limit: 800,000 - 1,000,000");
        console.log("2. Use gas price: 0.1 gwei");
        console.log("3. Max priority fee: 0.05 gwei");
        console.log("4. Expected cost on Arbitrum: $0.50 - $2.00");
    }
} 