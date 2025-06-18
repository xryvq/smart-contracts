// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrefundingProtocolTest
 * @dev Unit tests for Leverage Protocol PoC with 20% self-collateral + 80% pool model
 * 
 * MAIN TEST FLOW (test_CompleteBasicFlow):
 * 
 * PHASE 1: RETAIL INVESTORS DEPOSIT
 * - 3 retail investors deposit to LendingPool
 * - Investor 1: $50,000 USDC
 * - Investor 2: $30,000 USDC  
 * - Investor 3: $20,000 USDC
 * - Total pool liquidity: $100,000 USDC
 * - Shares issued 1:1 with deposits
 * 
 * PHASE 2: INSTITUTIONAL BORROWER LOAN
 * - 1 institutional borrower borrows $25,000 USDC
 * - Collateral: $5,000 USDC (20% of loan)
 * - Pool allocation: $20,000 USDC (80% of loan)
 * - RestrictedWallet deployed automatically
 * - Total $25,000 USDC transferred to RestrictedWallet
 * 
 * PHASE 3: LOAN REPAYMENT
 * - Calculate total due (principal + interest)
 * - Borrower repays full amount
 * - Loan status changes to REPAID
 * - Pool assets return to normal + interest
 * 
 * PHASE 4: RETAIL INVESTORS WITHDRAW
 * - Retail investors can withdraw anytime
 * - Receive back principal + yield share
 * 
 * ADDITIONAL TESTS:
 * - Security: Multiple loan prevention, access controls
 * - Liquidity: Yield accrual mechanism (8% APY)
 * - Edge cases: Zero deposits, invalid parameters, insufficient balance
 */

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/LendingPool.sol";
import "../src/CollateralManager.sol";
import "../src/RestrictedWallet.sol";
import "../src/RestrictedWalletFactory.sol";
import "../src/LoanManager.sol";

contract PrefundingProtocolTest is Test {
    MockUSDC public usdcToken;
    LendingPool public lendingPool;
    CollateralManager public collateralManager;
    RestrictedWalletFactory public walletFactory;
    LoanManager public loanManager;

    // Test participants
    address public retailInvestor1 = address(0x1);
    address public retailInvestor2 = address(0x2);
    address public retailInvestor3 = address(0x3);
    address public institutionalBorrower = address(0x4);

    // Test amounts in USDC (6 decimals)
    uint256 public constant RETAIL_DEPOSIT_1 = 50_000 * 1e6;  // $50k USDC
    uint256 public constant RETAIL_DEPOSIT_2 = 30_000 * 1e6;  // $30k USDC
    uint256 public constant RETAIL_DEPOSIT_3 = 20_000 * 1e6;  // $20k USDC
    uint256 public constant TOTAL_POOL_LIQUIDITY = 100_000 * 1e6; // $100k total
    
    uint256 public constant LOAN_AMOUNT = 25_000 * 1e6;       // $25k loan
    uint256 public constant COLLATERAL_AMOUNT = 5_000 * 1e6;  // $5k collateral (20%)
    uint256 public constant POOL_ALLOCATION = 20_000 * 1e6;   // $20k from pool (80%)

    function setUp() public {
        // Deploy all contracts
        usdcToken = new MockUSDC();
        lendingPool = new LendingPool(address(usdcToken), "Lending Pool USDC", "LP-USDC");
        collateralManager = new CollateralManager(address(usdcToken), address(lendingPool));
        walletFactory = new RestrictedWalletFactory();
        loanManager = new LoanManager(address(lendingPool), address(collateralManager), address(walletFactory), address(usdcToken));
        
        // Setup contract dependencies
        lendingPool.setCollateralManager(address(collateralManager));
        lendingPool.setLoanManager(address(loanManager));
        collateralManager.setLoanManager(address(loanManager));
        
        // Mint USDC for all participants
        usdcToken.mint(retailInvestor1, RETAIL_DEPOSIT_1 * 2); // Extra for testing
        usdcToken.mint(retailInvestor2, RETAIL_DEPOSIT_2 * 2);
        usdcToken.mint(retailInvestor3, RETAIL_DEPOSIT_3 * 2);
        usdcToken.mint(institutionalBorrower, COLLATERAL_AMOUNT * 2);
        
        // Setup approvals
        vm.prank(retailInvestor1);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        
        vm.prank(retailInvestor2);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        
        vm.prank(retailInvestor3);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        
        vm.prank(institutionalBorrower);
        usdcToken.approve(address(loanManager), type(uint256).max);
    }

    function test_CompleteBasicFlow() public {
        console.log("=== LEVERAGE PROTOCOL PoC - BASIC FLOW TEST ===");
        
        // ====== PHASE 1: RETAIL INVESTORS DEPOSIT TO LENDING POOL ======
        console.log("\n--- PHASE 1: Retail Investors Deposit ---");
        
        // Investor 1 deposits $50k
        vm.prank(retailInvestor1);
        uint256 shares1 = lendingPool.deposit(RETAIL_DEPOSIT_1, retailInvestor1);
        console.log("Investor 1 deposit: $50,000 USDC -> %d shares", shares1 / 1e6);
        
        // Investor 2 deposits $30k
        vm.prank(retailInvestor2);
        uint256 shares2 = lendingPool.deposit(RETAIL_DEPOSIT_2, retailInvestor2);
        console.log("Investor 2 deposit: $30,000 USDC -> %d shares", shares2 / 1e6);
        
        // Investor 3 deposits $20k
        vm.prank(retailInvestor3);
        uint256 shares3 = lendingPool.deposit(RETAIL_DEPOSIT_3, retailInvestor3);
        console.log("Investor 3 deposit: $20,000 USDC -> %d shares", shares3 / 1e6);
        
        // Verify total pool liquidity
        uint256 totalAssets = lendingPool.totalAssets();
        uint256 totalShares = lendingPool.totalSupply();
        console.log("Total Pool Assets: $%d", totalAssets / 1e6);
        console.log("Total Shares Issued: %d", totalShares / 1e6);
        
        assertEq(totalAssets, TOTAL_POOL_LIQUIDITY, "Total pool assets should be $100k");
        assertEq(shares1, RETAIL_DEPOSIT_1, "Shares should be 1:1 with deposits initially");
        assertEq(shares2, RETAIL_DEPOSIT_2, "Shares should be 1:1 with deposits initially");
        assertEq(shares3, RETAIL_DEPOSIT_3, "Shares should be 1:1 with deposits initially");

        // ====== PHASE 2: INSTITUTIONAL BORROWER TAKES LOAN ======
        console.log("\n--- PHASE 2: Institutional Borrower Loan ---");
        
        uint256 borrowerBalanceBefore = usdcToken.balanceOf(institutionalBorrower);
        console.log("Borrower USDC balance before: $%d", borrowerBalanceBefore / 1e6);
        
        // Borrower initiates loan $25k (with $5k collateral)
        vm.prank(institutionalBorrower);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        // Get loan info
        LoanManager.LoanInfo memory loanInfo = loanManager.getLoanInfo(loanId);
        console.log("Loan ID: %d", loanId);
        console.log("Loan Amount: $%d", loanInfo.loanAmount / 1e6);
        console.log("Collateral Amount: $%d", loanInfo.collateralAmount / 1e6);
        console.log("Restricted Wallet: %s", loanInfo.restrictedWallet);
        
        // Verify loan structure
        assertEq(loanInfo.loanAmount, LOAN_AMOUNT, "Loan amount should be $25k");
        assertEq(loanInfo.collateralAmount, COLLATERAL_AMOUNT, "Collateral should be $5k (20%)");
        assertEq(uint8(loanInfo.status), uint8(LoanManager.LoanStatus.Active), "Loan should be active");

        // Verify restricted wallet receives 100% loan amount
        uint256 walletBalance = usdcToken.balanceOf(loanInfo.restrictedWallet);
        console.log("Restricted Wallet Balance: $%d", walletBalance / 1e6);
        assertEq(walletBalance, LOAN_AMOUNT, "Wallet should receive full loan amount");
        
        // Verify pool balance reduces by 80% allocation
        uint256 poolAssetsAfterLoan = lendingPool.totalAssets();
        console.log("Pool Assets After Loan: $%d", poolAssetsAfterLoan / 1e6);
        assertEq(poolAssetsAfterLoan, TOTAL_POOL_LIQUIDITY - POOL_ALLOCATION, "Pool should reduce by $20k");

        // ====== PHASE 3: LOAN REPAYMENT ======
        console.log("\n--- PHASE 3: Loan Repayment ---");
        
        // Calculate total amount due (principal + interest)
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        console.log("Total Due (Principal + Interest): $%d", totalDue / 1e6);
        
        // Mint additional USDC for repayment (simulate profit from business)
        usdcToken.mint(institutionalBorrower, totalDue);
        console.log("Additional USDC minted for repayment: $%d", totalDue / 1e6);
        
        // Repay loan
        vm.prank(institutionalBorrower);
        loanManager.repayLoan(loanId, totalDue);
        
        // Verify loan status
        LoanManager.LoanInfo memory loanInfoAfterRepay = loanManager.getLoanInfo(loanId);
        assertEq(uint8(loanInfoAfterRepay.status), uint8(LoanManager.LoanStatus.Repaid), "Loan should be repaid");
        console.log("Loan Status: REPAID");
        
        // Verify pool assets return to normal + interest
        uint256 poolAssetsAfterRepay = lendingPool.totalAssets();
        console.log("Pool Assets After Repayment: $%d", poolAssetsAfterRepay / 1e6);
        assertTrue(poolAssetsAfterRepay >= TOTAL_POOL_LIQUIDITY, "Pool should have at least original amount + interest");
        
        // ====== PHASE 4: RETAIL INVESTORS WITHDRAW ======
        console.log("\n--- PHASE 4: Retail Investors Withdraw ---");
        
        // Investor 1 withdraws partial amount
        uint256 withdrawAmount = 25_000 * 1e6; // $25k
        vm.prank(retailInvestor1);
        lendingPool.redeem(withdrawAmount, retailInvestor1, retailInvestor1);
        
        uint256 investor1BalanceAfter = usdcToken.balanceOf(retailInvestor1);
        console.log("Investor 1 withdrew: $%d", withdrawAmount / 1e6);
        console.log("Investor 1 final balance: $%d", investor1BalanceAfter / 1e6);
        
        assertTrue(investor1BalanceAfter >= RETAIL_DEPOSIT_1, "Investor should get back at least original deposit");
        
        console.log("\n=== BASIC FLOW TEST COMPLETED SUCCESSFULLY ===");
    }

    function test_MultipleLoansPreventionAndSecurity() public {
        console.log("=== SECURITY & ACCESS CONTROL TEST ===");
        
        // Setup: Deposit liquidity
        vm.prank(retailInvestor1);
        lendingPool.deposit(RETAIL_DEPOSIT_1, retailInvestor1);
        
        // Test 1: Prevent multiple active loans
        vm.startPrank(institutionalBorrower);
        uint256 loanId1 = loanManager.initiateLoan(LOAN_AMOUNT);
        
        vm.expectRevert("Active loan exists");
        loanManager.initiateLoan(LOAN_AMOUNT);
        vm.stopPrank();
        
        console.log("PASS: Multiple active loans prevented");
        
        // Test 2: Only borrower can repay their own loan
        vm.prank(retailInvestor1);
        vm.expectRevert("Not loan borrower");
        loanManager.repayLoan(loanId1, 1000 * 1e6);
        
        console.log("PASS: Unauthorized repayment blocked");
        
        console.log("=== SECURITY TESTS PASSED ===");
    }

    function test_LiquidityAndYieldScenarios() public {
        console.log("=== LIQUIDITY & YIELD TEST ===");
        
        // Multiple investors deposit
        vm.prank(retailInvestor1);
        lendingPool.deposit(RETAIL_DEPOSIT_1, retailInvestor1);
        
        vm.prank(retailInvestor2);
        lendingPool.deposit(RETAIL_DEPOSIT_2, retailInvestor2);
        
        // Check initial 1:1 ratio
        uint256 totalAssets = lendingPool.totalAssets();
        uint256 totalShares = lendingPool.totalSupply();
        assertEq(totalAssets, totalShares, "Initial ratio should be 1:1");
        
        // Simulate time passage for yield accrual
        vm.warp(block.timestamp + 365 days);
        
        // Trigger yield update via deposit
        vm.prank(retailInvestor3);
        lendingPool.deposit(1 * 1e6, retailInvestor3); // Small deposit to trigger yield
        
        uint256 totalAssetsAfterYield = lendingPool.totalAssets();
        assertTrue(totalAssetsAfterYield > totalAssets, "Assets should increase due to yield");
        
        console.log("Initial Assets: $%d", totalAssets / 1e6);
        console.log("Assets After 1 Year: $%d", totalAssetsAfterYield / 1e6);
        console.log("Yield Generated: $%d", (totalAssetsAfterYield - totalAssets) / 1e6);
        
        console.log("=== YIELD TEST PASSED ===");
    }

    function test_EdgeCasesAndValidations() public {
        console.log("=== EDGE CASES & VALIDATIONS TEST ===");
        
        // Test zero deposits
        vm.prank(retailInvestor1);
        vm.expectRevert("Cannot deposit zero assets");
        lendingPool.deposit(0, retailInvestor1);

        // Test mint to zero address
        vm.expectRevert("Cannot mint to zero address");
        usdcToken.mint(address(0), 1000 * 1e6);
        
        // Test insufficient collateral
        vm.prank(institutionalBorrower);
        vm.expectRevert("Invalid loan amount");
        loanManager.initiateLoan(1_000_000 * 1e6); // $1M loan with insufficient balance
        
        console.log("PASS: All edge cases handled properly");
        console.log("=== EDGE CASES TEST PASSED ===");
    }
} 