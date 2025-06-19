// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LendingPool.sol";
import "./CollateralManager.sol";
import "./RestrictedWalletFactory.sol";

/**
 * @title LoanManager
 * @dev Central coordinator for the leverage protocol lending system
 *      Handles loan origination, management, and repayment
 */
contract LoanManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Enums ============
    
    enum LoanStatus {
        Pending,    // Loan request submitted
        Active,     // Loan disbursed and active
        Repaid,     // Loan fully repaid
        Defaulted   // Loan defaulted (liquidated)
    }

    // ============ Structs ============
    
    struct LoanInfo {
        address borrower;           // Borrower address
        uint256 loanAmount;         // Total loan amount in USDC
        uint256 collateralAmount;   // USDC collateral amount (20%)
        uint256 interestRate;       // Annual interest rate (basis points)
        uint256 duration;           // Loan duration in seconds
        uint256 startTime;          // Loan start timestamp
        uint256 dueDate;            // Loan due date
        uint256 repaidAmount;       // Amount repaid so far
        address restrictedWallet;   // Borrower's restricted wallet
        LoanStatus status;          // Current loan status
    }

    // ============ State Variables ============
    
    /// @notice Lending pool contract
    LendingPool public immutable lendingPool;
    
    /// @notice Collateral manager contract
    CollateralManager public immutable collateralManager;
    
    /// @notice Restricted wallet factory
    RestrictedWalletFactory public immutable walletFactory;
    
    /// @notice USDC token contract
    IERC20 public immutable usdcToken;
    
    /// @notice Mapping of loan ID to loan information
    mapping(uint256 => LoanInfo) public loans;
    
    /// @notice Mapping of borrower to their active loan IDs
    mapping(address => uint256[]) public borrowerLoans;
    
    /// @notice Next loan ID counter
    uint256 public nextLoanId = 1;
    
    /// @notice Default annual interest rate (10% = 1000 basis points)
    uint256 public constant DEFAULT_INTEREST_RATE = 1000; // 10%
    uint256 public constant BASIS_POINTS = 10000;
    
    /// @notice Default loan duration (30 days)
    uint256 public constant DEFAULT_DURATION = 30 days;
    
    /// @notice Minimum and maximum loan amounts
    uint256 public constant MIN_LOAN_AMOUNT = 100 * 10**6;     // $100 USDC
    uint256 public constant MAX_LOAN_AMOUNT = 100000 * 10**6;  // $100k USDC
    
    /// @notice Collateral ratio constants
    uint256 public constant COLLATERAL_RATIO = 2000;  // 20% in basis points
    uint256 public constant POOL_RATIO = 8000;        // 80% in basis points
    
    /// @notice Loan statistics
    uint256 public totalLoansIssued;
    uint256 public totalLoansRepaid;
    uint256 public totalActiveLoans;
    uint256 public totalDefaultedLoans;

    // ============ Events ============
    
    event LoanInitiated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 loanAmount,
        uint256 collateralAmount,
        address restrictedWallet
    );
    
    event LoanRepaid(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 repaidAmount,
        uint256 remainingBalance
    );
    
    event LoanFullyRepaid(uint256 indexed loanId, address indexed borrower);
    event LoanDefaulted(uint256 indexed loanId, address indexed borrower);

    // ============ Modifiers ============
    
    modifier validLoanId(uint256 loanId) {
        require(loanId > 0 && loanId < nextLoanId, "Invalid loan ID");
        _;
    }

    modifier onlyBorrower(uint256 loanId) {
        require(loans[loanId].borrower == msg.sender, "Not loan borrower");
        _;
    }

    // ============ Constructor ============
    
    constructor(
        address _lendingPool,
        address _collateralManager,
        address _walletFactory,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_lendingPool != address(0), "Invalid lending pool address");
        require(_collateralManager != address(0), "Invalid collateral manager address");
        require(_walletFactory != address(0), "Invalid wallet factory address");
        require(_usdcToken != address(0), "Invalid USDC token address");
        
        lendingPool = LendingPool(_lendingPool);
        collateralManager = CollateralManager(_collateralManager);
        walletFactory = RestrictedWalletFactory(_walletFactory);
        usdcToken = IERC20(_usdcToken);
    }

    // ============ External Functions ============
    
    /**
     * @dev Initiate a new loan with USDC collateral
     * @param desiredLoanAmount Total amount to borrow in USDC
     * @return loanId The newly created loan ID
     */
    function initiateLoan(
        uint256 desiredLoanAmount
    ) external nonReentrant returns (uint256 loanId) {
        require(desiredLoanAmount >= MIN_LOAN_AMOUNT && desiredLoanAmount <= MAX_LOAN_AMOUNT, "Invalid loan amount");
        
        // More efficient: Check only if borrower has active loans using simple boolean check
        require(!_hasActiveLoan(msg.sender), "Active loan exists");
        
        // Calculate required collateral (20% of desired loan amount)
        uint256 requiredCollateral = (desiredLoanAmount * COLLATERAL_RATIO) / BASIS_POINTS;
        
        // Single balance check - cache the balance to avoid multiple calls
        uint256 userBalance = usdcToken.balanceOf(msg.sender);
        require(userBalance >= requiredCollateral, "Insufficient USDC balance for collateral");
        
        // Validate loan amount equals 5x collateral
        uint256 maxLoanAmount = requiredCollateral * 5;
        require(maxLoanAmount == desiredLoanAmount, "Loan amount must be 5x collateral");
        
        // Calculate pool allocation (80% of loan amount)
        uint256 poolAllocation = (desiredLoanAmount * POOL_RATIO) / BASIS_POINTS;
        
        // Deploy or get existing restricted wallet
        address restrictedWallet = walletFactory.getOrCreateWallet(msg.sender);
        
        // Transfer collateral (20%) directly to restricted wallet
        usdcToken.safeTransferFrom(msg.sender, restrictedWallet, requiredCollateral);
        
        // Batch the manager updates to reduce external calls
        collateralManager.updateBorrowedAmount(restrictedWallet, desiredLoanAmount);
        lendingPool.allocateFunds(restrictedWallet, poolAllocation);
        
        // Create loan record with optimized struct assignment
        loanId = nextLoanId++;
        LoanInfo storage newLoan = loans[loanId];
        newLoan.borrower = msg.sender;
        newLoan.loanAmount = desiredLoanAmount;
        newLoan.collateralAmount = requiredCollateral;
        newLoan.interestRate = DEFAULT_INTEREST_RATE;
        newLoan.duration = DEFAULT_DURATION;
        newLoan.startTime = block.timestamp;
        newLoan.dueDate = block.timestamp + DEFAULT_DURATION;
        newLoan.repaidAmount = 0;
        newLoan.restrictedWallet = restrictedWallet;
        newLoan.status = LoanStatus.Active;
        
        borrowerLoans[msg.sender].push(loanId);
        
        // Update statistics
        totalLoansIssued++;
        totalActiveLoans++;
        
        emit LoanInitiated(loanId, msg.sender, desiredLoanAmount, requiredCollateral, restrictedWallet);
    }

    /**
     * @dev Repay loan (partial or full)
     * @param loanId Loan ID to repay
     * @param repayAmount Amount to repay in USDC
     */
    function repayLoan(uint256 loanId, uint256 repayAmount) external validLoanId(loanId) onlyBorrower(loanId) nonReentrant {
        LoanInfo storage loan = loans[loanId];
        require(loan.status == LoanStatus.Active, "Loan not active");
        require(repayAmount > 0, "Repay amount must be greater than 0");
        
        uint256 totalDue = calculateTotalDue(loanId);
        require(repayAmount <= totalDue - loan.repaidAmount, "Repay amount exceeds remaining debt");
        
        // Transfer repayment from borrower to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        
        // Transfer to lending pool
        usdcToken.approve(address(lendingPool), repayAmount);
        lendingPool.repayFunds(loan.restrictedWallet, repayAmount);
        
        // Update loan record
        loan.repaidAmount += repayAmount;
        uint256 remainingBalance = totalDue - loan.repaidAmount;
        
        emit LoanRepaid(loanId, msg.sender, repayAmount, remainingBalance);
        
        // Check if loan is fully repaid
        if (remainingBalance == 0) {
            loan.status = LoanStatus.Repaid;
            totalActiveLoans--;
            totalLoansRepaid++;
            
            // Reset borrowed amount in collateral manager
            collateralManager.updateBorrowedAmount(loan.restrictedWallet, 0);
            
            emit LoanFullyRepaid(loanId, msg.sender);
        } else {
            // Update remaining borrowed amount in collateral manager
            collateralManager.updateBorrowedAmount(loan.restrictedWallet, remainingBalance);
        }
    }
    
    /**
     * @dev Calculate total amount due for a loan (principal + interest)
     * @param loanId The loan ID
     * @return totalDue The total amount due
     */
    function calculateTotalDue(uint256 loanId) public view validLoanId(loanId) returns (uint256 totalDue) {
        LoanInfo memory loan = loans[loanId];
        
        // Simple interest calculation: principal + (principal * rate * time / year)
        uint256 timeElapsed = block.timestamp - loan.startTime;
        uint256 interest = (loan.loanAmount * loan.interestRate * timeElapsed) / (BASIS_POINTS * 365 days);
        
        totalDue = loan.loanAmount + interest;
    }

    /**
     * @dev Get loan information
     * @param loanId The loan ID
     * @return LoanInfo struct containing all loan details
     */
    function getLoanInfo(uint256 loanId) external view validLoanId(loanId) returns (LoanInfo memory) {
        return loans[loanId];
    }

    /**
     * @dev Get all loan IDs for a borrower
     * @param borrower The borrower address
     * @return Array of loan IDs
     */
    function getBorrowerLoans(address borrower) external view returns (uint256[] memory) {
        return borrowerLoans[borrower];
    }

    /**
     * @dev Get loan status (PoC spec function)
     * @param borrower The borrower address
     * @return status Current loan status for borrower
     */
    function getLoanStatus(address borrower) external view returns (LoanStatus status) {
        uint256[] memory userLoans = borrowerLoans[borrower];
        if (userLoans.length == 0) {
            return LoanStatus.Pending;
        }
        
        // Return status of most recent loan
        uint256 latestLoanId = userLoans[userLoans.length - 1];
        return loans[latestLoanId].status;
    }

    /**
     * @dev Internal function to check if borrower has any active loans (gas optimized)
     * @param borrower The borrower address
     * @return hasActive True if borrower has active loans
     */
    function _hasActiveLoan(address borrower) internal view returns (bool hasActive) {
        uint256[] storage userLoans = borrowerLoans[borrower];
        uint256 length = userLoans.length;
        
        // Early return if no loans
        if (length == 0) return false;
        
        // Check loans in reverse order (most recent first)
        for (uint256 i = length; i > 0; i--) {
            if (loans[userLoans[i - 1]].status == LoanStatus.Active) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Check if borrower has any active loans (external wrapper)
     * @param borrower The borrower address
     * @return hasActive True if borrower has active loans
     */
    function hasActiveLoan(address borrower) external view returns (bool hasActive) {
        return _hasActiveLoan(borrower);
    }
}
