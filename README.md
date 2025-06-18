# Levra Lending System

A simplified decentralized lending protocol using USDC as both the lending asset and collateral.

## Overview

Levra is a clean, efficient lending system that allows users to:
- Deposit USDC as collateral
- Borrow USDC against their collateral
- Earn yield by providing liquidity to the lending pool
- Use borrowed funds through restricted wallets for approved DeFi activities

## System Architecture

### Core Contracts

1. **MockUSDC** (`src/MockUSDC.sol`)
   - ERC20 token with 6 decimals
   - Mintable for testing purposes
   - Serves as both collateral and lending asset

2. **LendingPool** (`src/LendingPool.sol`)
   - EIP-4626 compliant vault for retail investors
   - Fixed 8% APY for depositors
   - Manages USDC deposits and loan allocations

3. **CollateralManager** (`src/CollateralManager.sol`)
   - Manages USDC collateral with 120% minimum ratio
   - Maximum 83.33% loan-to-value (LTV) ratio
   - Handles collateral validation and liquidation

4. **LoanManager** (`src/LoanManager.sol`)
   - Central coordinator for loan origination and repayment
   - 10% annual interest rate on loans
   - 30-day loan duration
   - Loan amounts: $100 - $100,000 USDC

5. **RestrictedWalletFactory** (`src/RestrictedWalletFactory.sol`)
   - Deploys non-custodial smart wallets for borrowers
   - Implements EIP-1167 minimal proxy pattern
   - Whitelisted DeFi protocol interactions only

## Key Features

### Simplified Design
- **USDC-Only**: No ETH or oracle dependencies
- **Clean Architecture**: English comments throughout
- **Minimal Dependencies**: Uses only OpenZeppelin contracts
- **Gas Efficient**: Proxy pattern for wallet deployment

### Risk Management
- **120% Minimum Collateral Ratio**: Borrowers must maintain adequate collateral
- **83.33% Maximum LTV**: Conservative lending limits
- **Automated Liquidation**: Protects lenders from defaults
- **Restricted Wallets**: Borrowed funds can only interact with approved protocols

### Yield Generation
- **Fixed 8% APY**: Predictable returns for liquidity providers
- **Compound Interest**: Daily yield accrual
- **EIP-4626 Compliance**: Standard vault interface

## Contract Specifications

### CollateralManager
```solidity
// Minimum collateral ratio: 120%
uint256 public constant MIN_COLLATERAL_RATIO = 12000; // 120%

// Maximum loan-to-value ratio: 83.33%
uint256 public constant MAX_LTV_RATIO = 8333; // 83.33%
```

### LoanManager
```solidity
// Default annual interest rate: 10%
uint256 public constant DEFAULT_INTEREST_RATE = 1000; // 10%

// Loan duration: 30 days
uint256 public constant DEFAULT_DURATION = 30 days;

// Loan limits
uint256 public constant MIN_LOAN_AMOUNT = 100 * 10**6;     // $100 USDC
uint256 public constant MAX_LOAN_AMOUNT = 100000 * 10**6;  // $100k USDC
```

## Usage Flow

### For Lenders (Liquidity Providers)
1. Approve USDC spending to LendingPool
2. Call `deposit(amount, receiver)` to provide liquidity
3. Earn 8% APY automatically
4. Withdraw anytime with `withdraw(amount, receiver, owner)`

### For Borrowers
1. Approve USDC spending to LoanManager
2. Call `initiateLoan(loanAmount, collateralAmount)`
3. Receive borrowed USDC in a restricted wallet
4. Use funds only for whitelisted DeFi protocols
5. Repay loan with `repayLoan(loanId, repayAmount)`

## Deployment

### Local Development
```bash
# Compile contracts
forge build

# Run tests
forge test

# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key <PRIVATE_KEY> --broadcast
```

### Testnet Deployment
```bash
# Deploy to Arbitrum Sepolia
forge script script/Deploy.s.sol \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify
```

### Interacting with Deployed Contracts

#### Using Cast (Command Line)
```bash
# Check MockUSDC balance
cast call 0xCafbd1e6875a1dEfC6a7a3Aa1283e99bc5B3091D "balanceOf(address)" <YOUR_ADDRESS> --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Mint USDC tokens (for testing)
cast send 0xCafbd1e6875a1dEfC6a7a3Aa1283e99bc5B3091D "mint(address,uint256)" <YOUR_ADDRESS> 1000000000 --private-key <PRIVATE_KEY> --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Deposit to LendingPool
cast send 0x91510D20eC2a48158e0bD57581f1a60bdFeA9e7F "deposit(uint256,address)" 100000000 <YOUR_ADDRESS> --private-key <PRIVATE_KEY> --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

#### Frontend Integration
ABI files are available in the `abis/` directory for frontend integration.

## Testing

The system includes comprehensive tests for:
- LendingPool functionality (34 tests)
- MockUSDC token operations (5 tests)
- All tests pass successfully

```bash
# Run all tests
forge test

# Run specific test suite
forge test --match-contract LendingPoolTest -v
```

## Security Features

1. **ReentrancyGuard**: Protects against reentrancy attacks
2. **Ownable**: Admin functions restricted to contract owner
3. **SafeERC20**: Secure token transfers
4. **Input Validation**: Comprehensive parameter checking
5. **Emergency Functions**: Admin withdrawal capabilities

## Contract Addresses

### Arbitrum Sepolia Testnet

- **MockUSDC**: `0xCafbd1e6875a1dEfC6a7a3Aa1283e99bc5B3091D`
- **LendingPool**: `0x91510D20eC2a48158e0bD57581f1a60bdFeA9e7F`
- **CollateralManager**: `0xaFe8bfA624dc21F74FC291435367Ab5b3c246bbD`
- **RestrictedWalletFactory**: `0xdcE10A5e79f88747497F488e9961af2d9070651f`
- **LoanManager**: `0x86f637c568f57E2e41eA69e1ceb9270faD7108F7`

### Network Information
- **Chain ID**: 421614 (Arbitrum Sepolia)
- **RPC URL**: https://sepolia-rollup.arbitrum.io/rpc
- **Block Explorer**: https://sepolia.arbiscan.io/

### Contract Verification Status
- ✅ MockUSDC: Verified on Sourcify
- ✅ LendingPool: Verified on Sourcify  
- ⏳ CollateralManager: Verification pending
- ⏳ RestrictedWalletFactory: Verification pending
- ⏳ LoanManager: Verification pending

## License

MIT License
