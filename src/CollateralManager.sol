// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LendingPool.sol";

/**
 * @title CollateralManager
 * @dev Manages USDC collateral for the 20/80 leverage protocol model
 *      Handles collateral deposits, withdrawals, and position monitoring
 */
contract CollateralManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Structs ============
    
    struct CollateralInfo {
        uint256 amount;              // Amount of collateral deposited
        uint256 borrowedAmount;      // Amount currently borrowed
        uint256 depositTimestamp;    // When collateral was deposited
        bool isActive;               // Whether collateral is active
    }

    // ============ State Variables ============

    /// @notice USDC token contract
    IERC20 public immutable usdcToken;

    /// @notice Lending pool contract
    LendingPool public immutable lendingPool;

    /// @notice Loan manager contract
    address public loanManager;

    /// @notice Mapping to track collateral per restricted wallet
    mapping(address => uint256) public collateralAmount;

    /// @notice Mapping to track total borrowed amount per restricted wallet
    mapping(address => uint256) public totalBorrowed;

    /// @notice Mapping of CollateralInfo per address (PoC spec)
    mapping(address => CollateralInfo) public collateralInfo;

    /// @notice Liquidation threshold (15% in basis points)
    uint256 public constant LIQUIDATION_THRESHOLD = 1500; // 15%

    /// @notice Minimum collateral ratio (20% in basis points)
    uint256 public constant MIN_COLLATERAL_RATIO = 2000; // 20%

    /// @notice Maximum leverage ratio (5x in basis points)
    uint256 public constant MAX_LEVERAGE_RATIO = 50000; // 500%

    /// @notice Basis points constant
    uint256 public constant BASIS_POINTS = 10000;

    // ============ Events ============

    event CollateralDeposited(address indexed restrictedWallet, uint256 amount);
    event CollateralWithdrawn(address indexed restrictedWallet, uint256 amount);
    event CollateralReleased(address indexed restrictedWallet, uint256 amount);
    event PositionLiquidated(address indexed restrictedWallet, uint256 collateralAmount, uint256 debtAmount);
    event BorrowedAmountUpdated(address indexed restrictedWallet, uint256 newAmount);

    // ============ Constructor ============

    constructor(
        address _usdcToken,
        address _lendingPool
    ) Ownable(msg.sender) {
        require(_usdcToken != address(0), "Invalid USDC token address");
        require(_lendingPool != address(0), "Invalid lending pool address");
        
        usdcToken = IERC20(_usdcToken);
        lendingPool = LendingPool(_lendingPool);
    }

    // ============ External Functions ============

    /**
     * @dev Submit collateral for a restricted wallet (PoC spec function)
     * @param amount Amount of USDC collateral to submit
     */
    function submitCollateral(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        // Use msg.sender as the restricted wallet for simplicity in PoC
        collateralAmount[msg.sender] += amount;
        
        // Update CollateralInfo struct
        collateralInfo[msg.sender].amount += amount;
        collateralInfo[msg.sender].depositTimestamp = block.timestamp;
        collateralInfo[msg.sender].isActive = true;
        
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @dev Deposit collateral for a restricted wallet (internal function)
     * @param restrictedWallet Address of the restricted wallet
     * @param amount Amount of USDC collateral to deposit
     * @param desiredLoanAmount Desired loan amount for validation (must be 5x collateral)
     */
    function depositCollateral(
        address restrictedWallet, 
        uint256 amount, 
        uint256 desiredLoanAmount
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(restrictedWallet != address(0), "Invalid restricted wallet address");
        require(desiredLoanAmount > 0, "Desired loan amount must be greater than 0");
        
        // Validate minimum collateral requirement (20% of desired loan)
        require(
            (amount * BASIS_POINTS) / desiredLoanAmount >= MIN_COLLATERAL_RATIO, 
            "Collateral less than 20% of loan amount"
        );

        collateralAmount[restrictedWallet] += amount;
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(restrictedWallet, amount);
    }

    /**
     * @dev Validate collateral for user (PoC spec function)
     * @param user Address of the user
     * @return isValid True if collateral is sufficient (20% of borrowed amount)
     */
    function validateCollateral(address user) external view returns (bool isValid) {
        uint256 collateral = collateralAmount[user];
        uint256 borrowed = totalBorrowed[user];
        
        if (borrowed == 0) return true;
        
        uint256 collateralRatio = (collateral * BASIS_POINTS) / borrowed;
        return collateralRatio >= MIN_COLLATERAL_RATIO;
    }

    /**
     * @dev Check if user is under collateralized (PoC spec function)
     * @param user Address of the user
     * @return isUnder True if user is under collateralized
     */
    function isUnderCollateralized(address user) external view returns (bool isUnder) {
        uint256 collateral = collateralAmount[user];
        uint256 borrowed = totalBorrowed[user];
        
        if (borrowed == 0) return false;
        
        uint256 collateralRatio = (collateral * BASIS_POINTS) / borrowed;
        return collateralRatio < MIN_COLLATERAL_RATIO;
    }

    /**
     * @dev Withdraw collateral from a restricted wallet (only when loan is repaid)
     * @param restrictedWallet Address of the restricted wallet
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(
        address restrictedWallet, 
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(restrictedWallet != address(0), "Invalid restricted wallet address");
        require(collateralAmount[restrictedWallet] >= amount, "Insufficient collateral");
        require(msg.sender == restrictedWallet, "Only restricted wallet can withdraw");
        require(totalBorrowed[restrictedWallet] == 0, "Loan not fully repaid");

        collateralAmount[restrictedWallet] -= amount;
        usdcToken.safeTransfer(restrictedWallet, amount);

        emit CollateralWithdrawn(restrictedWallet, amount);
    }

    /**
     * @dev Release all collateral to restricted wallet after loan is fully repaid
     * @param restrictedWallet Address of the restricted wallet
     */
    function releaseCollateral(address restrictedWallet) external nonReentrant {
        require(restrictedWallet != address(0), "Invalid restricted wallet address");
        require(totalBorrowed[restrictedWallet] == 0, "Loan not fully repaid");
        
        uint256 amount = collateralAmount[restrictedWallet];
        require(amount > 0, "No collateral to release");
        
        collateralAmount[restrictedWallet] = 0;
        usdcToken.safeTransfer(restrictedWallet, amount);

        emit CollateralReleased(restrictedWallet, amount);
    }

    /**
     * @dev Liquidate position if collateral ratio falls below threshold
     * @param restrictedWallet Address of the restricted wallet to liquidate
     */
    function liquidatePosition(address restrictedWallet) external nonReentrant {
        uint256 collateral = collateralAmount[restrictedWallet];
        uint256 borrowed = totalBorrowed[restrictedWallet];
        
        require(collateral > 0 && borrowed > 0, "No position to liquidate");
        
        uint256 collateralRatio = (collateral * BASIS_POINTS) / borrowed;
        require(collateralRatio < LIQUIDATION_THRESHOLD, "Position not liquidatable");

        // Transfer collateral to liquidator
        usdcToken.safeTransfer(msg.sender, collateral);
        
        // Reset position
        collateralAmount[restrictedWallet] = 0;
        totalBorrowed[restrictedWallet] = 0;

        emit PositionLiquidated(restrictedWallet, collateral, borrowed);
    }

    /**
     * @dev Update total borrowed amount for a restricted wallet
     * @param restrictedWallet Address of the restricted wallet
     * @param amount New borrowed amount
     */
    function updateBorrowedAmount(address restrictedWallet, uint256 amount) external {
        require(
            msg.sender == address(lendingPool) || msg.sender == owner() || 
            msg.sender == loanManager, 
            "Only lending pool, loan manager, or owner can update"
        );
        
        totalBorrowed[restrictedWallet] = amount;
        
        // Update CollateralInfo struct
        collateralInfo[restrictedWallet].borrowedAmount = amount;
        
        emit BorrowedAmountUpdated(restrictedWallet, amount);
    }

    // ============ View Functions ============

    /**
     * @dev Check if a position is safe (above minimum collateral ratio)
     * @param restrictedWallet Address of the restricted wallet
     * @return isSafe True if position is safe
     */
    function isPositionSafe(address restrictedWallet) external view returns (bool) {
        uint256 collateral = collateralAmount[restrictedWallet];
        uint256 borrowed = totalBorrowed[restrictedWallet];
        
        if (borrowed == 0) return true;
        
        uint256 collateralRatio = (collateral * BASIS_POINTS) / borrowed;
        return collateralRatio >= MIN_COLLATERAL_RATIO;
    }

    /**
     * @dev Get collateral ratio for a restricted wallet
     * @param restrictedWallet Address of the restricted wallet
     * @return ratio Collateral ratio in basis points
     */
    function getCollateralRatio(address restrictedWallet) external view returns (uint256) {
        uint256 collateral = collateralAmount[restrictedWallet];
        uint256 borrowed = totalBorrowed[restrictedWallet];
        
        if (borrowed == 0) return type(uint256).max;
        
        return (collateral * BASIS_POINTS) / borrowed;
    }

    /**
     * @dev Get maximum borrowable amount (5x collateral)
     * @param restrictedWallet Address of the restricted wallet
     * @return maxBorrowable Maximum amount that can be borrowed
     */
    function getMaxBorrowable(address restrictedWallet) external view returns (uint256) {
        uint256 collateral = collateralAmount[restrictedWallet];
        return (collateral * MAX_LEVERAGE_RATIO) / BASIS_POINTS;
    }

    /**
     * @dev Check if position is eligible for liquidation
     * @param restrictedWallet Address of the restricted wallet
     * @return isLiquidatable True if position can be liquidated
     */
    function isLiquidatable(address restrictedWallet) external view returns (bool) {
        uint256 collateral = collateralAmount[restrictedWallet];
        uint256 borrowed = totalBorrowed[restrictedWallet];
        
        if (borrowed == 0) return false;
        
        uint256 collateralRatio = (collateral * BASIS_POINTS) / borrowed;
        return collateralRatio < LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Get collateral and borrowed amounts for a restricted wallet
     * @param restrictedWallet Address of the restricted wallet
     * @return collateral Amount of collateral deposited
     * @return borrowed Amount currently borrowed
     */
    function getPositionInfo(address restrictedWallet) external view returns (
        uint256 collateral, 
        uint256 borrowed
    ) {
        return (collateralAmount[restrictedWallet], totalBorrowed[restrictedWallet]);
    }

    // ============ Admin Functions ============

    /**
     * @dev Set loan manager address (only owner)
     * @param _loanManager Address of the loan manager
     */
    function setLoanManager(address _loanManager) external onlyOwner {
        require(_loanManager != address(0), "Invalid loan manager address");
        loanManager = _loanManager;
    }
}
