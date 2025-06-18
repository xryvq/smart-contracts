// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/LendingPool.sol";
import "../src/CollateralManager.sol";

/**
 * @title CollateralManagerTest
 * @dev Basic unit tests for CollateralManager contract
 */
contract CollateralManagerTest is Test {
    MockUSDC public usdcToken;
    LendingPool public lendingPool;
    CollateralManager public collateralManager;
    
    address public borrower1 = address(0x1);
    address public borrower2 = address(0x2);
    address public restrictedWallet1 = address(0x3);
    address public restrictedWallet2 = address(0x4);
    
    uint256 public constant COLLATERAL_AMOUNT = 5_000 * 1e6; // $5k USDC
    uint256 public constant LOAN_AMOUNT = 25_000 * 1e6; // $25k USDC

    function setUp() public {
        usdcToken = new MockUSDC();
        lendingPool = new LendingPool(address(usdcToken), "Lending Pool USDC", "LP-USDC");
        collateralManager = new CollateralManager(address(usdcToken), address(lendingPool));
        
        // Mint USDC to borrowers
        usdcToken.mint(borrower1, COLLATERAL_AMOUNT * 2);
        usdcToken.mint(borrower2, COLLATERAL_AMOUNT * 2);
        
        // Approve spending
        vm.prank(borrower1);
        usdcToken.approve(address(collateralManager), type(uint256).max);
        
        vm.prank(borrower2);
        usdcToken.approve(address(collateralManager), type(uint256).max);
    }

    function test_InitialState() public {
        assertEq(address(collateralManager.usdcToken()), address(usdcToken));
        assertEq(address(collateralManager.lendingPool()), address(lendingPool));
        assertEq(collateralManager.BASIS_POINTS(), 10000);
        assertEq(collateralManager.MIN_COLLATERAL_RATIO(), 2000); // 20%
        assertEq(collateralManager.LIQUIDATION_THRESHOLD(), 1500); // 15%
        assertEq(collateralManager.MAX_LEVERAGE_RATIO(), 50000); // 500%
    }

    function test_DepositCollateral() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        (uint256 collateral, uint256 borrowed) = collateralManager.getPositionInfo(restrictedWallet1);
        assertEq(collateral, COLLATERAL_AMOUNT);
        assertEq(borrowed, 0);
        assertEq(usdcToken.balanceOf(address(collateralManager)), COLLATERAL_AMOUNT);
    }

    function test_MultipleCollateralDeposits() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        vm.prank(borrower2);
        collateralManager.depositCollateral(restrictedWallet2, COLLATERAL_AMOUNT / 2, LOAN_AMOUNT / 2);
        
        (uint256 collateral1,) = collateralManager.getPositionInfo(restrictedWallet1);
        (uint256 collateral2,) = collateralManager.getPositionInfo(restrictedWallet2);
        
        assertEq(collateral1, COLLATERAL_AMOUNT);
        assertEq(collateral2, COLLATERAL_AMOUNT / 2);
        assertEq(usdcToken.balanceOf(address(collateralManager)), COLLATERAL_AMOUNT + COLLATERAL_AMOUNT / 2);
    }

    function test_WithdrawCollateral() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        uint256 withdrawAmount = COLLATERAL_AMOUNT / 2;
        vm.prank(restrictedWallet1);
        collateralManager.withdrawCollateral(restrictedWallet1, withdrawAmount);
        
        (uint256 collateral,) = collateralManager.getPositionInfo(restrictedWallet1);
        assertEq(collateral, COLLATERAL_AMOUNT - withdrawAmount);
        assertEq(usdcToken.balanceOf(restrictedWallet1), withdrawAmount);
    }

    function test_ReleaseCollateral() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.releaseCollateral(restrictedWallet1);
        
        (uint256 collateral,) = collateralManager.getPositionInfo(restrictedWallet1);
        assertEq(collateral, 0);
        assertEq(usdcToken.balanceOf(restrictedWallet1), COLLATERAL_AMOUNT);
    }

    function test_UpdateBorrowedAmount() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        
        (, uint256 borrowed) = collateralManager.getPositionInfo(restrictedWallet1);
        assertEq(borrowed, LOAN_AMOUNT);
    }

    function test_IsPositionSafe() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        // Position is safe with no borrowed amount
        assertTrue(collateralManager.isPositionSafe(restrictedWallet1));
        
        // Position is safe with proper collateral ratio
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        assertTrue(collateralManager.isPositionSafe(restrictedWallet1));
    }

    function test_GetCollateralRatio() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        
        uint256 ratio = collateralManager.getCollateralRatio(restrictedWallet1);
        uint256 expectedRatio = (COLLATERAL_AMOUNT * 10000) / LOAN_AMOUNT; // 20%
        assertEq(ratio, expectedRatio);
    }

    function test_GetMaxBorrowable() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        uint256 maxBorrowable = collateralManager.getMaxBorrowable(restrictedWallet1);
        uint256 expectedMax = (COLLATERAL_AMOUNT * 50000) / 10000; // 5x leverage
        assertEq(maxBorrowable, expectedMax);
    }

    function test_IsLiquidatable() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        // Not liquidatable with no borrowed amount
        assertFalse(collateralManager.isLiquidatable(restrictedWallet1));
        
        // Not liquidatable with safe ratio
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        assertFalse(collateralManager.isLiquidatable(restrictedWallet1));
        
        // Liquidatable with unsafe ratio (borrowed more than safe)
        uint256 unsafeBorrowAmount = (COLLATERAL_AMOUNT * 10000) / 1400; // Below 15% threshold
        collateralManager.updateBorrowedAmount(restrictedWallet1, unsafeBorrowAmount);
        assertTrue(collateralManager.isLiquidatable(restrictedWallet1));
    }

    function test_LiquidatePosition() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        // Set unsafe borrowed amount
        uint256 unsafeBorrowAmount = (COLLATERAL_AMOUNT * 10000) / 1400; // Below 15% threshold
        collateralManager.updateBorrowedAmount(restrictedWallet1, unsafeBorrowAmount);
        
        address liquidator = address(0x5);
        vm.prank(liquidator);
        collateralManager.liquidatePosition(restrictedWallet1);
        
        (uint256 collateral, uint256 borrowed) = collateralManager.getPositionInfo(restrictedWallet1);
        assertEq(collateral, 0);
        assertEq(borrowed, 0);
        assertEq(usdcToken.balanceOf(liquidator), COLLATERAL_AMOUNT);
    }

    function test_RevertWhen_DepositZeroCollateral() public {
        vm.prank(borrower1);
        vm.expectRevert("Amount must be greater than 0");
        collateralManager.depositCollateral(restrictedWallet1, 0, LOAN_AMOUNT);
    }

    function test_RevertWhen_DepositInsufficientCollateral() public {
        uint256 insufficientCollateral = LOAN_AMOUNT / 10; // Only 10% instead of 20%
        
        vm.prank(borrower1);
        vm.expectRevert("Collateral less than 20% of loan amount");
        collateralManager.depositCollateral(restrictedWallet1, insufficientCollateral, LOAN_AMOUNT);
    }

    function test_RevertWhen_WithdrawWithActiveLoan() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        
        vm.prank(restrictedWallet1);
        vm.expectRevert("Loan not fully repaid");
        collateralManager.withdrawCollateral(restrictedWallet1, COLLATERAL_AMOUNT / 2);
    }

    function test_RevertWhen_UnauthorizedWithdraw() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        vm.prank(borrower2);
        vm.expectRevert("Only restricted wallet can withdraw");
        collateralManager.withdrawCollateral(restrictedWallet1, COLLATERAL_AMOUNT / 2);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        vm.prank(restrictedWallet1);
        vm.expectRevert("Insufficient collateral");
        collateralManager.withdrawCollateral(restrictedWallet1, COLLATERAL_AMOUNT * 2);
    }

    function test_RevertWhen_ReleaseWithActiveLoan() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        
        vm.expectRevert("Loan not fully repaid");
        collateralManager.releaseCollateral(restrictedWallet1);
    }

    function test_RevertWhen_LiquidateSafePosition() public {
        vm.prank(borrower1);
        collateralManager.depositCollateral(restrictedWallet1, COLLATERAL_AMOUNT, LOAN_AMOUNT);
        
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
        
        vm.expectRevert("Position not liquidatable");
        collateralManager.liquidatePosition(restrictedWallet1);
    }

    function test_RevertWhen_UnauthorizedUpdateBorrowedAmount() public {
        vm.prank(borrower1);
        vm.expectRevert("Only lending pool, loan manager, or owner can update");
        collateralManager.updateBorrowedAmount(restrictedWallet1, LOAN_AMOUNT);
    }
} 