// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LendingPool
 * @dev EIP-4626 based vault for storing USDC from retail investors
 *      with fixed 8% APY using shares for ownership representation.
 *      Supports 20/80 prefunding model for leverage trading.
 */
contract LendingPool is ERC20, IERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============
    
    /// @notice The underlying asset token (USDC)
    IERC20 private immutable _asset;
    
    /// @notice Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing
    function asset() public view override returns (address) {
        return address(_asset);
    }
    
    /// @notice Total assets stored in the vault
    uint256 public totalAssets;
    
    /// @notice Total shares in circulation
    uint256 public totalShares;
    
    /// @notice Mapping of user shares
    mapping(address => uint256) public userShares;
    
    /// @notice Last timestamp when yield was updated
    uint256 public lastUpdateTimestamp;
    
    /// @notice Fixed APY of 8% (in basis points: 800 = 8%)
    uint256 public constant FIXED_APY = 800;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    /// @notice LoanManager address that can allocate loans
    address public loanManager;

    /// @notice CollateralManager address for managing collateral
    address public collateralManager;

    /// @notice Mapping to track funds allocated to smart wallets
    mapping(address => uint256) public allocatedFunds;

    /// @notice Total funds allocated for leverage
    uint256 public totalAllocatedFunds;

    // ============ Events ============
    
    event YieldAccrued(uint256 totalYield, uint256 timestamp);
    event LoanAllocated(uint256 amount, address indexed smartWallet);
    event RepaymentReceived(uint256 amount, address indexed smartWallet);
    event LoanManagerUpdated(address indexed oldManager, address indexed newManager);
    event CollateralManagerUpdated(address indexed oldManager, address indexed newManager);
    event FundsAllocated(uint256 amount, address indexed smartWallet);
    event FundsRepaid(uint256 amount, address indexed smartWallet);

    // ============ Modifiers ============

    modifier onlyLoanManager() {
        require(msg.sender == loanManager, "Only loan manager can call");
        _;
    }

    modifier onlyCollateralManager() {
        require(msg.sender == collateralManager, "Only collateral manager can call");
        _;
    }

    // ============ Constructor ============
    
    constructor(
        address assetAddress,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        _asset = IERC20(assetAddress);
        lastUpdateTimestamp = block.timestamp;
    }

    // ============ EIP-4626 Implementation ============
    
    /**
     * @dev Deposits assets and mints shares for the receiver
     * @param assets Amount of assets to deposit
     * @param receiver Address that will receive the shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) 
        external 
        override 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets > 0, "Cannot deposit zero assets");
        require(receiver != address(0), "Invalid receiver address");
        
        // Update yield before deposit
        _accrueYield();
        
        // Calculate shares to mint (1:1 ratio)
        shares = convertToShares(assets);
        
        // Update state
        totalAssets += assets;
        totalShares += shares;
        userShares[receiver] += shares;
        
        // Transfer assets from user to vault
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        
        // Mint shares token
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Withdraws assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address that will receive the assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) 
        external 
        override 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets > 0, "Cannot withdraw zero assets");
        require(receiver != address(0), "Invalid receiver address");
        require(assets <= totalAssets, "Insufficient vault assets");
        
        // Update yield before withdrawal
        _accrueYield();
        
        // Calculate shares to burn
        shares = convertToShares(assets);
        
        // Check allowance if not owner
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(allowed >= shares, "Insufficient allowance");
            _spendAllowance(owner, msg.sender, shares);
        }
        
        require(balanceOf(owner) >= shares, "Insufficient shares");
        require(userShares[owner] >= shares, "Insufficient user shares");
        
        // Update state
        totalAssets -= assets;
        totalShares -= shares;
        userShares[owner] -= shares;
        
        // Burn shares and transfer assets
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @dev Mints shares for the receiver
     * @param shares Amount of shares to mint
     * @param receiver Address that will receive the shares
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Cannot mint zero shares");
        require(receiver != address(0), "Invalid receiver address");
        
        // Update yield before minting
        _accrueYield();
        
        // Calculate required assets (1:1 ratio)
        assets = convertToAssets(shares);
        
        // Update state
        totalAssets += assets;
        totalShares += shares;
        userShares[receiver] += shares;
        
        // Transfer assets and mint shares
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Redeem shares for getting assets
     */
    function redeem(uint256 shares, address receiver, address owner) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Cannot redeem zero shares");
        require(receiver != address(0), "Invalid receiver");
        
        // Update yield before redeem
        _accrueYield();
        
        // Calculate assets to return
        assets = convertToAssets(shares);
        require(assets <= totalAssets, "Insufficient vault assets");
        
        // Check allowance if not owner
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(allowed >= shares, "Insufficient allowance");
            _spendAllowance(owner, msg.sender, shares);
        }
        
        require(balanceOf(owner) >= shares, "Insufficient shares");
        require(userShares[owner] >= shares, "Insufficient user shares");
        
        // Update state
        totalAssets -= assets;
        totalShares -= shares;
        userShares[owner] -= shares;
        
        // Burn shares and transfer assets
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // ============ Conversion Functions ============
    
    /**
     * @dev Convert assets to shares (1:1 ratio)
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        if (totalShares == 0) {
            return assets;
        }
        return (assets * totalShares) / totalAssets;
    }

    /**
     * @dev Convert shares to assets (1:1 ratio)
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (totalShares == 0) {
            return shares;
        }
        return (shares * totalAssets) / totalShares;
    }

    // ============ Preview Functions ============
    
    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return convertToAssets(shares);
    }

    // ============ Max Functions ============
    
    function maxDeposit(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }

    // ============ Additional Functions ============
    
    /**
     * @dev Calculate and simulate APY yield for user
     */
    function calculateAPYYield(address user) external view returns (uint256) {
        if (userShares[user] == 0) {
            return 0;
        }
        
        uint256 userAssets = convertToAssets(userShares[user]);
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        
        // Calculate yield with APY 8% (linear approximation)
        uint256 annualYield = (userAssets * FIXED_APY) / BASIS_POINTS;
        uint256 yield = (annualYield * timeElapsed) / SECONDS_PER_YEAR;
        
        return yield;
    }

    /**
     * @dev Allocate loan funds (PoC spec function - called by LoanManager)
     * @param amount Amount to allocate for loan
     */
    function allocateLoan(uint256 amount) external onlyLoanManager {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= totalAssets - totalAllocatedFunds, "Insufficient available funds");
        require(amount <= _asset.balanceOf(address(this)), "Insufficient available funds");
        
        totalAllocatedFunds += amount;
        totalAssets -= amount;
        
        emit LoanAllocated(amount, msg.sender);
    }

    /**
     * @dev Allocate funds for loan (called by LoanManager)
     */
    function allocateFunds(address smartWallet, uint256 amount) external onlyLoanManager {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= totalAssets - totalAllocatedFunds, "Insufficient available funds");
        require(amount <= _asset.balanceOf(address(this)), "Insufficient available funds");
        allocatedFunds[smartWallet] += amount;
        totalAllocatedFunds += amount;
        totalAssets -= amount;
        // Transfer USDC from vault to smartWallet
        _asset.safeTransfer(smartWallet, amount);
        emit FundsAllocated(amount, smartWallet);
    }

    /**
     * @dev Receive loan repayment (PoC spec function)
     * @param amount Amount being repaid
     */
    function receiveRepayment(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer repayment from sender to vault
        _asset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Reduce allocated funds and increase total assets
        if (amount >= totalAllocatedFunds) {
            totalAssets += totalAllocatedFunds;
            totalAllocatedFunds = 0;
        } else {
            totalAllocatedFunds -= amount;
            totalAssets += amount;
        }
        
        emit RepaymentReceived(amount, msg.sender);
    }

    /**
     * @dev Receive repayment from loan (internal function)
     */
    function repayFunds(address smartWallet, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        uint256 alloc = allocatedFunds[smartWallet];
        if (amount >= alloc) {
            allocatedFunds[smartWallet] = 0;
            totalAllocatedFunds -= alloc;
        } else {
            allocatedFunds[smartWallet] -= amount;
            totalAllocatedFunds -= amount;
        }
        // Add repayment to totalAssets vault
        totalAssets += amount;
        emit FundsRepaid(amount, smartWallet);
    }

    /**
     * @dev Update yield based on time elapsed
     */
    function accrueYield() external {
        _accrueYield();
    }

    // ============ Internal Functions ============
    
    /**
     * @dev Internal function to accrue yield
     */
    function _accrueYield() internal {
        if (totalAssets == 0) {
            lastUpdateTimestamp = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) {
            return;
        }
        
        // Calculate yield with APY 8% (linear approximation)
        uint256 annualYield = (totalAssets * FIXED_APY) / BASIS_POINTS;
        uint256 totalYield = (annualYield * timeElapsed) / SECONDS_PER_YEAR;
        
        // Update total assets with yield
        totalAssets += totalYield;
        lastUpdateTimestamp = block.timestamp;
        
        emit YieldAccrued(totalYield, block.timestamp);
    }

    // ============ Admin Functions ============
    
    /**
     * @dev Set loan manager address
     */
    function setLoanManager(address _loanManager) external onlyOwner {
        require(_loanManager != address(0), "Invalid loan manager");
        emit LoanManagerUpdated(loanManager, _loanManager);
        loanManager = _loanManager;
    }

    /**
     * @dev Set collateral manager address
     */
    function setCollateralManager(address _collateralManager) external onlyOwner {
        require(_collateralManager != address(0), "Invalid collateral manager");
        emit CollateralManagerUpdated(collateralManager, _collateralManager);
        collateralManager = _collateralManager;
    }

    /**
     * @dev Emergency function to withdraw assets (only owner)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= _asset.balanceOf(address(this)), "Insufficient balance");
        _asset.safeTransfer(owner(), amount);
    }

    // ============ View Functions ============
    
    /**
     * @dev Get vault information
     */
    function getVaultInfo() external view returns (
        uint256 _totalAssets,
        uint256 _totalShares,
        uint256 _lastUpdate,
        uint256 _apy
    ) {
        return (totalAssets, totalShares, lastUpdateTimestamp, FIXED_APY);
    }

    /**
     * @dev Get user information
     */
    function getUserInfo(address user) external view returns (
        uint256 shares,
        uint256 assets,
        uint256 pendingYield
    ) {
        shares = userShares[user];
        assets = convertToAssets(shares);
        pendingYield = this.calculateAPYYield(user);
    }
}
