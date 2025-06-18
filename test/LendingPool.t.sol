// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/LendingPool.sol";

/**
 * @title LendingPoolTest
 * @dev Basic unit tests for LendingPool contract
 */
contract LendingPoolTest is Test {
    MockUSDC public usdcToken;
    LendingPool public lendingPool;
    
    address public investor1 = address(0x1);
    address public investor2 = address(0x2);
    address public loanManager = address(0x3);
    address public collateralManager = address(0x4);
    
    uint256 public constant DEPOSIT_AMOUNT = 10_000 * 1e6; // $10k USDC

    function setUp() public {
        usdcToken = new MockUSDC();
        lendingPool = new LendingPool(address(usdcToken), "Lending Pool USDC", "LP-USDC");
        
        // Set up dependencies
        lendingPool.setLoanManager(loanManager);
        lendingPool.setCollateralManager(collateralManager);
        
        // Mint USDC to investors
        usdcToken.mint(investor1, DEPOSIT_AMOUNT * 2);
        usdcToken.mint(investor2, DEPOSIT_AMOUNT * 2);
        
        // Approve spending
        vm.prank(investor1);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        
        vm.prank(investor2);
        usdcToken.approve(address(lendingPool), type(uint256).max);
    }

    function test_InitialState() public {
        assertEq(lendingPool.name(), "Lending Pool USDC");
        assertEq(lendingPool.symbol(), "LP-USDC");
        assertEq(lendingPool.asset(), address(usdcToken));
        assertEq(lendingPool.totalAssets(), 0);
        assertEq(lendingPool.totalSupply(), 0);
        assertEq(lendingPool.FIXED_APY(), 800); // 8%
    }

    function test_Deposit() public {
        vm.prank(investor1);
        uint256 shares = lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        assertEq(shares, DEPOSIT_AMOUNT); // 1:1 ratio initially
        assertEq(lendingPool.balanceOf(investor1), DEPOSIT_AMOUNT);
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(lendingPool.totalSupply(), DEPOSIT_AMOUNT);
        assertEq(usdcToken.balanceOf(address(lendingPool)), DEPOSIT_AMOUNT);
    }

    function test_MultipleDeposits() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        vm.prank(investor2);
        lendingPool.deposit(DEPOSIT_AMOUNT / 2, investor2);
        
        assertEq(lendingPool.balanceOf(investor1), DEPOSIT_AMOUNT);
        assertEq(lendingPool.balanceOf(investor2), DEPOSIT_AMOUNT / 2);
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2);
        assertEq(lendingPool.totalSupply(), DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2);
    }

    function test_Withdraw() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        vm.prank(investor1);
        uint256 shares = lendingPool.withdraw(withdrawAmount, investor1, investor1);
        
        assertEq(shares, withdrawAmount); // 1:1 ratio
        assertEq(lendingPool.balanceOf(investor1), DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(usdcToken.balanceOf(investor1), DEPOSIT_AMOUNT + withdrawAmount);
    }

    function test_Redeem() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        uint256 redeemShares = DEPOSIT_AMOUNT / 2;
        vm.prank(investor1);
        uint256 assets = lendingPool.redeem(redeemShares, investor1, investor1);
        
        assertEq(assets, redeemShares); // 1:1 ratio
        assertEq(lendingPool.balanceOf(investor1), DEPOSIT_AMOUNT - redeemShares);
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT - redeemShares);
    }

    function test_Mint() public {
        uint256 sharesToMint = DEPOSIT_AMOUNT;
        vm.prank(investor1);
        uint256 assets = lendingPool.mint(sharesToMint, investor1);
        
        assertEq(assets, sharesToMint); // 1:1 ratio
        assertEq(lendingPool.balanceOf(investor1), sharesToMint);
        assertEq(lendingPool.totalAssets(), sharesToMint);
    }

    function test_ConvertToShares() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        uint256 shares = lendingPool.convertToShares(DEPOSIT_AMOUNT);
        assertEq(shares, DEPOSIT_AMOUNT); // 1:1 ratio initially
    }

    function test_ConvertToAssets() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        uint256 assets = lendingPool.convertToAssets(DEPOSIT_AMOUNT);
        assertEq(assets, DEPOSIT_AMOUNT); // 1:1 ratio initially
    }

    function test_AllocateFunds() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        address borrower = address(0x5);
        uint256 allocateAmount = DEPOSIT_AMOUNT / 2;
        
        vm.prank(loanManager);
        lendingPool.allocateFunds(borrower, allocateAmount);
        
        assertEq(usdcToken.balanceOf(borrower), allocateAmount);
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT - allocateAmount);
        assertEq(lendingPool.totalAllocatedFunds(), allocateAmount);
    }

    function test_RepayFunds() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        address borrower = address(0x5);
        uint256 allocateAmount = DEPOSIT_AMOUNT / 2;
        
        vm.prank(loanManager);
        lendingPool.allocateFunds(borrower, allocateAmount);
        
        // Borrower repays
        usdcToken.mint(loanManager, allocateAmount);
        vm.startPrank(loanManager);
        usdcToken.approve(address(lendingPool), allocateAmount);
        lendingPool.repayFunds(borrower, allocateAmount);
        vm.stopPrank();
        
        assertEq(lendingPool.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(lendingPool.totalAllocatedFunds(), 0);
    }

    function test_YieldAccrual() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        uint256 initialAssets = lendingPool.totalAssets();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Trigger yield update
        vm.prank(investor2);
        lendingPool.deposit(1 * 1e6, investor2);
        
        uint256 finalAssets = lendingPool.totalAssets();
        assertTrue(finalAssets > initialAssets, "Assets should increase due to yield");
    }

    function test_RevertWhen_DepositZeroAssets() public {
        vm.prank(investor1);
        vm.expectRevert("Cannot deposit zero assets");
        lendingPool.deposit(0, investor1);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        vm.prank(investor1);
        vm.expectRevert("Insufficient vault assets");
        lendingPool.withdraw(DEPOSIT_AMOUNT * 2, investor1, investor1);
    }

    function test_RevertWhen_UnauthorizedAllocateFunds() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        vm.prank(investor1);
        vm.expectRevert("Only loan manager can call");
        lendingPool.allocateFunds(address(0x5), DEPOSIT_AMOUNT / 2);
    }

    function test_RepayFundsFromAnyAddress() public {
        // Setup: allocate funds first
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        address borrower = address(0x5);
        vm.prank(loanManager);
        lendingPool.allocateFunds(borrower, DEPOSIT_AMOUNT / 2);
        
        // Anyone can repay funds (not restricted)
        usdcToken.mint(investor1, 1000);
        vm.prank(investor1);
        usdcToken.approve(address(lendingPool), 1000);
        lendingPool.repayFunds(borrower, 1000);
        
        // Verify repayment was processed
        assertTrue(lendingPool.totalAssets() > DEPOSIT_AMOUNT / 2);
    }

    function test_RevertWhen_AllocateMoreThanAvailable() public {
        vm.prank(investor1);
        lendingPool.deposit(DEPOSIT_AMOUNT, investor1);
        
        vm.prank(loanManager);
        vm.expectRevert("Insufficient available funds");
        lendingPool.allocateFunds(address(0x5), DEPOSIT_AMOUNT * 2);
    }
} 