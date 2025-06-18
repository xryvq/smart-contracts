// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/LendingPool.sol";
import "../src/CollateralManager.sol";
import "../src/RestrictedWalletFactory.sol";
import "../src/LoanManager.sol";

/**
 * @title LoanManagerTest
 * @dev Basic unit tests for LoanManager contract
 */
contract LoanManagerTest is Test {
    MockUSDC public usdcToken;
    LendingPool public lendingPool;
    CollateralManager public collateralManager;
    RestrictedWalletFactory public walletFactory;
    LoanManager public loanManager;
    
    address public borrower1 = address(0x1);
    address public borrower2 = address(0x2);
    address public investor = address(0x3);
    
    uint256 public constant LOAN_AMOUNT = 25_000 * 1e6; // $25k USDC
    uint256 public constant COLLATERAL_AMOUNT = 5_000 * 1e6; // $5k USDC
    uint256 public constant POOL_DEPOSIT = 100_000 * 1e6; // $100k USDC

    function setUp() public {
        // Deploy contracts
        usdcToken = new MockUSDC();
        lendingPool = new LendingPool(address(usdcToken), "Lending Pool USDC", "LP-USDC");
        collateralManager = new CollateralManager(address(usdcToken), address(lendingPool));
        walletFactory = new RestrictedWalletFactory();
        loanManager = new LoanManager(address(lendingPool), address(collateralManager), address(walletFactory), address(usdcToken));
        
        // Setup dependencies
        lendingPool.setCollateralManager(address(collateralManager));
        lendingPool.setLoanManager(address(loanManager));
        collateralManager.setLoanManager(address(loanManager));
        
        // Mint USDC and setup approvals
        usdcToken.mint(borrower1, COLLATERAL_AMOUNT * 2);
        usdcToken.mint(borrower2, COLLATERAL_AMOUNT * 2);
        usdcToken.mint(investor, POOL_DEPOSIT);
        
        vm.prank(borrower1);
        usdcToken.approve(address(loanManager), type(uint256).max);
        
        vm.prank(borrower2);
        usdcToken.approve(address(loanManager), type(uint256).max);
        
        vm.prank(investor);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        
        // Add liquidity to pool
        vm.prank(investor);
        lendingPool.deposit(POOL_DEPOSIT, investor);
    }

    function test_InitialState() public {
        assertEq(address(loanManager.lendingPool()), address(lendingPool));
        assertEq(address(loanManager.collateralManager()), address(collateralManager));
        assertEq(address(loanManager.walletFactory()), address(walletFactory));
        assertEq(address(loanManager.usdcToken()), address(usdcToken));
        assertEq(loanManager.COLLATERAL_RATIO(), 2000); // 20%
        assertEq(loanManager.POOL_RATIO(), 8000); // 80%
        assertEq(loanManager.nextLoanId(), 1);
    }

    function test_InitiateLoan() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        LoanManager.LoanInfo memory loanInfo = loanManager.getLoanInfo(loanId);
        
        assertEq(loanId, 1);
        assertEq(loanInfo.borrower, borrower1);
        assertEq(loanInfo.loanAmount, LOAN_AMOUNT);
        assertEq(loanInfo.collateralAmount, COLLATERAL_AMOUNT);
        assertEq(uint8(loanInfo.status), uint8(LoanManager.LoanStatus.Active));
        assertTrue(loanInfo.restrictedWallet != address(0));
        assertEq(loanInfo.startTime, block.timestamp);
        
        // Verify collateral was deposited (should be 0 after release)
        (uint256 collateral,) = collateralManager.getPositionInfo(loanInfo.restrictedWallet);
        assertEq(collateral, 0); // Collateral is released to wallet after deposit
        
        // Verify wallet was created and funded
        assertTrue(walletFactory.hasWallet(borrower1));
        assertEq(usdcToken.balanceOf(loanInfo.restrictedWallet), LOAN_AMOUNT);
    }

    function test_MultipleLoansFromDifferentBorrowers() public {
        vm.prank(borrower1);
        uint256 loanId1 = loanManager.initiateLoan(LOAN_AMOUNT);
        
        vm.prank(borrower2);
        uint256 loanId2 = loanManager.initiateLoan(LOAN_AMOUNT / 2);
        
        assertEq(loanId1, 1);
        assertEq(loanId2, 2);
        
        LoanManager.LoanInfo memory loan1 = loanManager.getLoanInfo(loanId1);
        LoanManager.LoanInfo memory loan2 = loanManager.getLoanInfo(loanId2);
        
        assertEq(loan1.borrower, borrower1);
        assertEq(loan2.borrower, borrower2);
        assertEq(loan1.loanAmount, LOAN_AMOUNT);
        assertEq(loan2.loanAmount, LOAN_AMOUNT / 2);
    }

    function test_CalculateTotalDue() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        
        // Should be just principal since no time has elapsed (timeElapsed = 0)
        assertEq(totalDue, LOAN_AMOUNT);
        
        // Fast forward 1 year to test full interest
        vm.warp(block.timestamp + 365 days);
        
        uint256 totalDueAfterYear = loanManager.calculateTotalDue(loanId);
        uint256 expectedInterest = (LOAN_AMOUNT * 1000) / 10000; // 10% APR
        uint256 expectedTotal = LOAN_AMOUNT + expectedInterest;
        
        assertEq(totalDueAfterYear, expectedTotal);
    }

    function test_CalculateTotalDueWithTimeProgression() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        // Fast forward 6 months
        vm.warp(block.timestamp + 180 days);
        
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        
        // Should be principal + 6 months interest (10% APR)
        uint256 expectedInterest = (LOAN_AMOUNT * 1000 * 180 days) / (10000 * 365 days);
        uint256 expectedTotal = LOAN_AMOUNT + expectedInterest;
        
        assertApproxEqAbs(totalDue, expectedTotal, 1e6); // Allow 1 USDC difference for rounding
    }

    function test_RepayLoan() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        
        // Mint additional USDC for repayment
        usdcToken.mint(borrower1, totalDue);
        
        vm.prank(borrower1);
        loanManager.repayLoan(loanId, totalDue);
        
        LoanManager.LoanInfo memory loanInfo = loanManager.getLoanInfo(loanId);
        assertEq(uint8(loanInfo.status), uint8(LoanManager.LoanStatus.Repaid));
        
        // Verify collateral was returned (should still be 0 as it was already released)
        (uint256 collateral,) = collateralManager.getPositionInfo(loanInfo.restrictedWallet);
        assertEq(collateral, 0);
    }

    function test_PartialRepayment() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        uint256 partialAmount = totalDue / 2;
        
        usdcToken.mint(borrower1, partialAmount);
        
        vm.prank(borrower1);
        loanManager.repayLoan(loanId, partialAmount);
        
        LoanManager.LoanInfo memory loanInfo = loanManager.getLoanInfo(loanId);
        assertEq(uint8(loanInfo.status), uint8(LoanManager.LoanStatus.Active));
        assertEq(loanInfo.repaidAmount, partialAmount);
    }

    function test_GetBorrowerLoans() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        uint256[] memory borrowerLoanIds = loanManager.getBorrowerLoans(borrower1);
        assertEq(borrowerLoanIds.length, 1);
        assertEq(borrowerLoanIds[0], loanId);
    }

    function test_GetBorrowerLoansForNonBorrower() public {
        uint256[] memory borrowerLoanIds = loanManager.getBorrowerLoans(borrower1);
        assertEq(borrowerLoanIds.length, 0);
    }

    function test_HasActiveLoan() public {
        assertFalse(loanManager.hasActiveLoan(borrower1));
        
        vm.prank(borrower1);
        loanManager.initiateLoan(LOAN_AMOUNT);
        
        assertTrue(loanManager.hasActiveLoan(borrower1));
    }

    function test_RevertWhen_InitiateLoanWithActiveLoan() public {
        vm.prank(borrower1);
        loanManager.initiateLoan(LOAN_AMOUNT);
        
        vm.prank(borrower1);
        vm.expectRevert("Active loan exists");
        loanManager.initiateLoan(LOAN_AMOUNT);
    }

    function test_RevertWhen_InitiateLoanWithInvalidAmount() public {
        vm.prank(borrower1);
        vm.expectRevert("Invalid loan amount");
        loanManager.initiateLoan(0);
    }

    function test_RevertWhen_InitiateLoanWithInsufficientCollateral() public {
        // Create a new borrower with insufficient USDC balance
        address poorBorrower = address(0x999);
        usdcToken.mint(poorBorrower, 1000 * 1e6); // Only $1k USDC
        
        vm.prank(poorBorrower);
        usdcToken.approve(address(loanManager), type(uint256).max);
        
        // Try to borrow $25k (needs $5k collateral but only has $1k)
        vm.prank(poorBorrower);
        vm.expectRevert("Insufficient USDC balance for collateral");
        loanManager.initiateLoan(LOAN_AMOUNT);
    }

    function test_RevertWhen_InitiateLoanWithInsufficientPoolLiquidity() public {
        // Drain the pool first - use withdraw instead of redeem
        uint256 investorShares = lendingPool.balanceOf(investor);
        uint256 withdrawAmount = lendingPool.previewRedeem(investorShares);
        
        vm.prank(investor);
        lendingPool.withdraw(withdrawAmount, investor, investor);
        
        // Now the pool has no funds, so allocateFunds should fail
        vm.prank(borrower1);
        vm.expectRevert("Insufficient available funds");
        loanManager.initiateLoan(LOAN_AMOUNT);
    }

    function test_RevertWhen_RepayNonExistentLoan() public {
        vm.prank(borrower1);
        vm.expectRevert("Invalid loan ID");
        loanManager.repayLoan(999, 1000 * 1e6);
    }

    function test_RevertWhen_RepayLoanByNonBorrower() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        vm.prank(borrower2);
        vm.expectRevert("Not loan borrower");
        loanManager.repayLoan(loanId, 1000 * 1e6);
    }

    function test_RevertWhen_RepayAlreadyRepaidLoan() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        uint256 totalDue = loanManager.calculateTotalDue(loanId);
        usdcToken.mint(borrower1, totalDue);
        
        vm.prank(borrower1);
        loanManager.repayLoan(loanId, totalDue);
        
        vm.prank(borrower1);
        vm.expectRevert("Loan not active");
        loanManager.repayLoan(loanId, 1000 * 1e6);
    }

    function test_RevertWhen_RepayZeroAmount() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.initiateLoan(LOAN_AMOUNT);
        
        vm.prank(borrower1);
        vm.expectRevert("Repay amount must be greater than 0");
        loanManager.repayLoan(loanId, 0);
    }

    function test_RevertWhen_GetLoanInfoForNonExistentLoan() public {
        vm.expectRevert("Invalid loan ID");
        loanManager.getLoanInfo(999);
    }
} 