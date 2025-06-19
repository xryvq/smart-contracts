# Flow Protocol Leverage 20/80 Prefunding

## Deskripsi Protocol
Protocol leverage berbasis USDC yang memungkinkan borrower melakukan trading dengan leverage 5x menggunakan model prefunding 20/80:
- **20% Collateral**: User deposit sendiri sebagai jaminan
- **80% Pool Funds**: Dana dari retail investor di LendingPool
- **Non-custodial**: User memiliki kontrol penuh melalui RestrictedWallet
- **Whitelist DEX**: Trading hanya bisa dilakukan di DEX yang disetujui

---

## Flow Lengkap User Borrow

### 1. Persiapan Awal (Setup)
```
🏦 Retail Investor → Deposit USDC ke LendingPool (Earn 8% APY)
💰 User → Minta USDC test tokens dari MockUSDC.mint()
```

### 2. Proses Borrowing
```
👤 User (Borrower)
   ↓
📋 Submit Loan Request via LoanManager.initiateLoan()
   ├─ Input: desiredLoanAmount (contoh: 1000 USDC)
   ├─ Validasi: amount antara $100-$100k
   └─ Validasi: tidak ada loan aktif
   ↓
🏭 RestrictedWalletFactory.getOrCreateWallet()
   ├─ Deploy RestrictedWallet baru (jika belum ada)
   └─ Set user sebagai owner wallet
   ↓
💸 Transfer Collateral (20% = 200 USDC)
   ├─ User → RestrictedWallet (langsung transfer)
   └─ CollateralManager.updateBorrowedAmount() (tracking)
   ↓
🏦 Pool Allocation (80% = 800 USDC)
   ├─ LendingPool.allocateFunds()
   ├─ Transfer dari Pool → RestrictedWallet
   └─ Update totalAllocatedFunds
   ↓
📝 Loan Record Created
   ├─ LoanID generated
   ├─ Status: Active
   ├─ Duration: 30 hari
   ├─ Interest: 10% per tahun
   └─ DueDate: startTime + 30 hari
```

### 3. Trading Phase
```
💼 RestrictedWallet (1000 USDC total)
   ↓
🛡️ Whitelist Setup
   ├─ whitelistTarget(dexAddress)
   ├─ whitelistSelector(swapFunction)
   └─ whitelistToken(tokenAddress)
   ↓
🔄 Execute Trading
   ├─ execute(target, data) → DEX calls only
   ├─ Semua transaksi harus ke DEX yang disetujui
   └─ Function selector harus dalam whitelist
```

### 4. Repayment Process
```
💰 User Repayment
   ↓
🔙 LoanManager.repayLoan(loanId, amount)
   ├─ Bisa partial atau full repayment
   ├─ Hitung total due (principal + interest)
   └─ Validasi amount tidak melebihi debt
   ↓
🏦 Funds Flow
   ├─ User → LoanManager (transfer repayment)
   ├─ LoanManager → LendingPool (repayFunds)
   └─ Update totalAssets pool
   ↓
📊 Update Status
   ├─ Loan.repaidAmount += amount
   ├─ CollateralManager.updateBorrowedAmount()
   └─ Jika full repaid: Status = Repaid
```

### 5. Collateral Release
```
✅ Loan Fully Repaid
   ↓
🔓 CollateralManager.releaseCollateral()
   ├─ Validasi totalBorrowed = 0
   ├─ Transfer collateral back to RestrictedWallet
   └─ Reset collateralAmount = 0
   ↓
💸 User Withdraw
   └─ RestrictedWallet.emergencyWithdraw() atau manual transfer
```

### 6. Liquidation (jika diperlukan)
```
📉 Collateral Ratio < 15%
   ↓
⚠️ CollateralManager.isLiquidatable() = true
   ↓
🔥 Liquidator calls liquidatePosition()
   ├─ Transfer collateral to liquidator
   ├─ Reset position (collateral = 0, borrowed = 0)
   └─ Loan status = Defaulted
```

---

## Dokumentasi Lengkap Fungsi Per Kontrak

### 1. MockUSDC.sol
**Purpose**: Token USDC simulasi untuk testing
```solidity
// Public Functions
mint(address to, uint256 amount)           // Mint USDC ke address
decimals() → uint8                         // Return 6 (USDC standard)

// Inherited from ERC20
totalSupply() → uint256
balanceOf(address account) → uint256
transfer(address to, uint256 amount) → bool
transferFrom(address from, address to, uint256 amount) → bool
approve(address spender, uint256 amount) → bool
allowance(address owner, address spender) → uint256
```

### 2. LendingPool.sol (EIP-4626 Vault)
**Purpose**: Pool untuk retail investor dengan 8% APY

#### EIP-4626 Core Functions
```solidity
// Deposit/Withdraw
deposit(uint256 assets, address receiver) → uint256 shares
withdraw(uint256 assets, address receiver, address owner) → uint256 shares
mint(uint256 shares, address receiver) → uint256 assets
redeem(uint256 shares, address receiver, address owner) → uint256 assets

// Conversion
convertToShares(uint256 assets) → uint256
convertToAssets(uint256 shares) → uint256

// Preview Functions
previewDeposit(uint256 assets) → uint256
previewMint(uint256 shares) → uint256
previewWithdraw(uint256 assets) → uint256
previewRedeem(uint256 shares) → uint256

// Max Functions
maxDeposit(address) → uint256
maxMint(address) → uint256
maxWithdraw(address owner) → uint256
maxRedeem(address owner) → uint256

// Asset Info
asset() → address                          // Return USDC address
totalAssets() → uint256                    // Total assets in vault
```

#### Leverage Protocol Functions
```solidity
// Loan Management (onlyLoanManager)
allocateLoan(uint256 amount)               // Allocate funds for loan
allocateFunds(address smartWallet, uint256 amount) // Transfer to wallet
repayFunds(address smartWallet, uint256 amount)    // Receive repayment
receiveRepayment(uint256 amount)           // Direct repayment receiver

// Yield Management
accrueYield()                             // Update yield manually
calculateAPYYield(address user) → uint256  // Calculate user pending yield

// Admin Functions (onlyOwner)
setLoanManager(address _loanManager)
setCollateralManager(address _collateralManager)
emergencyWithdraw(uint256 amount)

// View Functions
getVaultInfo() → (uint256 totalAssets, uint256 totalShares, uint256 lastUpdate, uint256 apy)
getUserInfo(address user) → (uint256 shares, uint256 assets, uint256 pendingYield)
```

### 3. CollateralManager.sol
**Purpose**: Mengelola kolateral USDC dan monitoring posisi

#### Core Functions
```solidity
// Collateral Management
submitCollateral(uint256 amount)           // Submit collateral (PoC spec)
depositCollateral(address restrictedWallet, uint256 amount, uint256 desiredLoanAmount)
withdrawCollateral(address restrictedWallet, uint256 amount)
releaseCollateral(address restrictedWallet) // Release all collateral

// Position Monitoring
validateCollateral(address user) → bool    // Check 20% minimum
isUnderCollateralized(address user) → bool // Check if under 20%
isPositionSafe(address restrictedWallet) → bool
isLiquidatable(address restrictedWallet) → bool

// Liquidation
liquidatePosition(address restrictedWallet) // Liquidate if ratio < 15%

// Data Management
updateBorrowedAmount(address restrictedWallet, uint256 amount)

// View Functions
getCollateralRatio(address restrictedWallet) → uint256
getMaxBorrowable(address restrictedWallet) → uint256
getPositionInfo(address restrictedWallet) → (uint256 collateral, uint256 borrowed)

// Admin
setLoanManager(address _loanManager)       // Set loan manager address
```

#### Constants
```solidity
LIQUIDATION_THRESHOLD = 1500               // 15% in basis points
MIN_COLLATERAL_RATIO = 2000               // 20% in basis points  
MAX_LEVERAGE_RATIO = 50000                // 500% (5x leverage)
BASIS_POINTS = 10000
```

### 4. LoanManager.sol
**Purpose**: Koordinator utama untuk loan management

#### Core Functions
```solidity
// Loan Lifecycle
initiateLoan(uint256 desiredLoanAmount) → uint256 loanId
repayLoan(uint256 loanId, uint256 repayAmount)

// Calculation
calculateTotalDue(uint256 loanId) → uint256 // Principal + interest

// Query Functions
getLoanInfo(uint256 loanId) → LoanInfo
getBorrowerLoans(address borrower) → uint256[]
getLoanStatus(address borrower) → LoanStatus // PoC spec
hasActiveLoan(address borrower) → bool
```

#### Loan Status Enum
```solidity
enum LoanStatus {
    Pending,    // Loan request submitted
    Active,     // Loan disbursed and active
    Repaid,     // Loan fully repaid
    Defaulted   // Loan defaulted (liquidated)
}
```

#### Constants
```solidity
DEFAULT_INTEREST_RATE = 1000              // 10% annual
DEFAULT_DURATION = 30 days
MIN_LOAN_AMOUNT = 100 * 10**6             // $100 USDC
MAX_LOAN_AMOUNT = 100000 * 10**6          // $100k USDC
COLLATERAL_RATIO = 2000                   // 20%
POOL_RATIO = 8000                         // 80%
```

### 5. RestrictedWallet.sol
**Purpose**: Smart wallet non-custodial dengan kontrol akses

#### Core Functions
```solidity
// Transaction Execution
execute(address target, bytes calldata data) // Execute ke whitelisted target

// Whitelist Management (onlyOwner)
whitelistTarget(address target)            // Add DEX to whitelist
removeTarget(address target)               // Remove DEX from whitelist
whitelistSelector(bytes4 selector)         // Add function selector
removeSelector(bytes4 selector)            // Remove function selector
whitelistToken(address token)              // Add token to whitelist
removeToken(address token)                 // Remove token from whitelist

// Balance Query
getBalance(address token) → uint256        // Get token balance
getBalance() → uint256                     // Get ETH balance

// Emergency Functions (onlyOwner)
emergencyWithdraw(address token, address to, uint256 amount)

// Receive Functions
receive()                                  // Accept ETH
fallback()                                 // Fallback function
```

### 6. RestrictedWalletFactory.sol
**Purpose**: Factory untuk deploy RestrictedWallet

#### Core Functions
```solidity
// Wallet Creation
createWallet() → address                   // Create wallet for msg.sender
getOrCreateWallet(address user) → address // Get existing or create new

// Query Functions
getAllWallets() → address[]                // Get all wallet addresses
getWallet(address user) → address         // Get wallet for user
hasWallet(address user) → bool            // Check if user has wallet
getWalletCount() → uint256                // Total wallets created
```

---

## Event Logging

### LendingPool Events
```solidity
event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares)
event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)
event YieldAccrued(uint256 totalYield, uint256 timestamp)
event LoanAllocated(uint256 amount, address indexed smartWallet)
event RepaymentReceived(uint256 amount, address indexed smartWallet)
```

### LoanManager Events
```solidity
event LoanInitiated(uint256 indexed loanId, address indexed borrower, uint256 loanAmount, uint256 collateralAmount, address restrictedWallet)
event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 repaidAmount, uint256 remainingBalance)
event LoanFullyRepaid(uint256 indexed loanId, address indexed borrower)
event LoanDefaulted(uint256 indexed loanId, address indexed borrower)
```

### CollateralManager Events
```solidity
event CollateralDeposited(address indexed restrictedWallet, uint256 amount)
event CollateralWithdrawn(address indexed restrictedWallet, uint256 amount)
event CollateralReleased(address indexed restrictedWallet, uint256 amount)
event PositionLiquidated(address indexed restrictedWallet, uint256 collateralAmount, uint256 debtAmount)
```

### RestrictedWallet Events
```solidity
event TargetWhitelisted(address indexed target, bool approved)
event FunctionWhitelisted(bytes4 indexed selector, bool approved)
event TokenWhitelisted(address indexed token, bool approved)
event TransactionExecuted(address indexed target, bytes data, uint256 value)
```

---

## Security Features

### Access Control
- **Ownable**: Kontrol admin functions
- **ReentrancyGuard**: Perlindungan dari reentrancy attacks
- **Whitelist System**: Hanya DEX yang disetujui bisa diakses
- **Function Selector Control**: Hanya function tertentu yang bisa dipanggil

### Risk Management
- **Collateral Ratio Monitoring**: Min 20%, liquidation di 15%
- **Loan Amount Limits**: $100 - $100k USDC
- **Duration Limits**: Fixed 30 hari
- **Single Active Loan**: Satu user hanya bisa punya satu loan aktif

### Validation Checks
- **Address Validation**: Semua input address dicek != address(0)
- **Amount Validation**: Semua amount > 0
- **Balance Checks**: Sufficient balance sebelum transfer
- **Status Checks**: Loan status validation di setiap operasi

---

## Integration Notes

### Deployment Order
1. MockUSDC
2. LendingPool
3. CollateralManager 
4. RestrictedWalletFactory
5. LoanManager
6. Set addresses (setLoanManager, setCollateralManager)

### Frontend Integration
- User perlu approve USDC spending ke kontrak
- Monitor events untuk update UI real-time
- Calculate APY dan interest untuk display
- Handle transaction confirmations dan error states