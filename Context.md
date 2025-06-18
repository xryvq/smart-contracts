# Context.md - Frontend Development Guide untuk Levra PoC

## Overview Protokol Leverage Levra

Levra adalah leverage protocol berbasis USDC prefunding dengan model 20/80, dimana borrower menyediakan 20% kolateral dan 80% dipinjam dari lending pool retail investor.

### Arsitektur Smart Contract

```
MockUSDC (Token USDC simulasi)
├── LendingPool (EIP-4626 Vault - 8% APY untuk retail)  
├── CollateralManager (Manajemen kolateral & liquidation)
├── LoanManager (Koordinator loan lifecycle)
├── RestrictedWalletFactory (Factory deploy wallet)
└── RestrictedWallet (Non-custodial smart wallet dengan whitelist)
```

## Core Flow PoC

### 1. **Retail Investor Flow**
- Deposit USDC ke LendingPool → dapat LP tokens
- Earn 8% APY otomatis
- Withdraw kapan saja (sesuai available liquidity)

### 2. **Borrower Flow**  
- Deploy RestrictedWallet via Factory
- Submit 20% kolateral USDC ke CollateralManager
- Request loan 80% dari LoanManager
- Trading via RestrictedWallet (whitelist DEX only)
- Repay loan + interest atau liquidation jika under-collateralized

## Frontend Architecture Plan

### Tech Stack Recommended
```
├── Framework: Next.js 14 (App Router)
├── Web3: wagmi v2 + viem
├── UI: shadcn/ui + Tailwind CSS
├── State: Zustand
└── Charts: Chart.js atau Recharts
```

### Environment Setup
```bash
# 1. Create NextJS project
npx create-next-app@latest levra-frontend --typescript --tailwind --app

# 2. Install Web3 dependencies  
npm install wagmi viem @tanstack/react-query
npm install @rainbow-me/rainbowkit

# 3. Install UI components
npx shadcn-ui@latest init
npx shadcn-ui@latest add button card input label

# 4. Install additional tools
npm install zustand date-fns
```

## Contract Integration Setup

### 1. Contract Addresses & ABIs
```typescript
// config/contracts.ts
export const CONTRACTS = {
  MockUSDC: "0x...",
  LendingPool: "0x...", 
  CollateralManager: "0x...",
  LoanManager: "0x...",
  RestrictedWalletFactory: "0x..."
} as const;

// Import ABIs dari abis/ folder hasil compile
import MockUSDCABI from "../abis/MockUSDC.json";
import LendingPoolABI from "../abis/LendingPool.json";
// ... dst
```

### 2. Wagmi Configuration
```typescript
// config/wagmi.ts
import { createConfig, http } from 'wagmi'
import { mainnet, sepolia, foundry } from 'wagmi/chains'

export const config = createConfig({
  chains: [foundry, sepolia], // Start dengan local/testnet
  transports: {
    [foundry.id]: http('http://127.0.0.1:8545'),
    [sepolia.id]: http()
  }
})
```

## Phase 1: Basic Connection & Display

### MVP Features (Week 1)
1. **Wallet Connection**
   - Connect/disconnect wallet
   - Display address & balance
   - Network switching

2. **Read-Only Dashboard**
   - LendingPool stats (TVL, APY, available liquidity)
   - User's LP token balance & USD value
   - Mock USDC balance

3. **Basic UI Components**
   - Header dengan wallet connection
   - Dashboard cards untuk stats
   - Responsive layout

### Essential Hooks
```typescript
// hooks/useContractReads.ts
export function useLendingPoolStats() {
  // Read totalAssets, totalSupply, available liquidity
}

export function useUserBalances(address: string) {
  // Read USDC balance, LP tokens, dll
}
```

## Phase 2: Retail Investor Features

### Core Functions (Week 2-3)
1. **Deposit Flow**
   - Input amount USDC
   - Approve transaction
   - Deposit ke LendingPool
   - Show preview shares received

2. **Withdraw Flow**  
   - Input LP tokens atau USD amount
   - Preview USDC received
   - Execute withdrawal

3. **Portfolio Tracking**
   - Deposited amount history
   - Earned interest visualization
   - APY calculation real-time

### Key Components
```typescript
// components/DepositForm.tsx
- Input field dengan balance validation
- Approve/Deposit button logic
- Transaction status tracking

// components/WithdrawForm.tsx  
- LP token input dengan max button
- Preview calculation
- Slippage protection

// components/PortfolioStats.tsx
- Chart showing deposit growth
- Current position summary
```

## Phase 3: Borrower Features

### Advanced Functions (Week 3-4)
1. **Wallet Management**
   - Deploy RestrictedWallet
   - View deployed wallets
   - Check wallet balances

2. **Loan Origination**
   - Collateral submission flow
   - Loan request interface
   - Terms preview & confirmation

3. **Loan Management**
   - Active loan dashboard
   - Repayment interface
   - Collateralization ratio monitoring

### Critical Components
```typescript
// components/WalletDeployment.tsx
- One-click deploy restricted wallet
- Display deployed wallet address

// components/CollateralSubmission.tsx
- USDC amount input (min 20% ratio)
- Calculate max borrowable
- Submit collateral transaction

// components/LoanDashboard.tsx
- Loan health ratio
- Interest accrued
- Repayment options
```

## Phase 4: Integration & Polish

### Finishing Touches (Week 4-5)
1. **Error Handling**
   - Transaction failed states
   - Network error recovery
   - User-friendly error messages

2. **Loading States**
   - Skeleton loading
   - Transaction pending states
   - Optimistic updates

3. **Notifications**
   - Toast notifications
   - Transaction success/fail
   - Important alerts

## Development Environment

### Local Development Setup
```bash
# 1. Start local blockchain
cd smart-contract/
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# 2. Note deployed addresses untuk frontend config

# 3. Start frontend
cd ../levra-frontend/
npm run dev
```

### Testing Strategy
1. **Unit Tests**: Component logic testing
2. **Integration Tests**: Contract interaction flows  
3. **E2E Tests**: Complete user journeys
4. **Manual Testing**: Cross-browser compatibility

## Security Considerations

### Frontend Security
- Input validation & sanitization
- Transaction parameter verification
- Slippage protection
- Maximum approval amounts
- Contract address verification

### UX Security
- Clear transaction confirmations
- Warning untuk high-value transactions
- Liquidation risk indicators
- Real-time health ratio updates

## Key Metrics to Track

### Protocol Metrics
- Total Value Locked (TVL)
- Active loans count
- Liquidation ratio
- Pool utilization rate

### User Metrics
- Deposit/withdraw volume
- Average loan size
- User retention rate
- Transaction success rate

## Development Priorities

### Phase 1 (Basic): Minggu 1
- [ ] Wallet connection & basic UI
- [ ] Read-only contract data display
- [ ] Responsive design setup

### Phase 2 (Retail): Minggu 2-3  
- [ ] Deposit/withdraw functionality
- [ ] Portfolio tracking
- [ ] Transaction handling

### Phase 3 (Borrower): Minggu 3-4
- [ ] Wallet deployment
- [ ] Loan origination flow
- [ ] Loan management interface

### Phase 4 (Polish): Minggu 4-5
- [ ] Error handling & loading states
- [ ] Testing & optimization
- [ ] Documentation & deployment

## Next Steps

1. **Setup development environment** sesuai tech stack di atas
2. **Deploy contracts ke testnet** untuk stable testing
3. **Start dengan Phase 1** - basic connection & read-only features
4. **Iterate berdasarkan user feedback** setiap phase

## Contract Interaction Examples

### Read Operations
```typescript
// Get lending pool stats
const totalAssets = useReadContract({
  abi: LendingPoolABI,
  address: CONTRACTS.LendingPool,
  functionName: 'totalAssets'
})

// Get user's loan info
const loanInfo = useReadContract({
  abi: LoanManagerABI, 
  address: CONTRACTS.LoanManager,
  functionName: 'getLoanInfo',
  args: [userAddress]
})
```

### Write Operations
```typescript
// Deposit to lending pool
const { writeContract } = useWriteContract()

const handleDeposit = async (amount: bigint) => {
  // 1. Approve USDC first
  await writeContract({
    abi: MockUSDCABI,
    address: CONTRACTS.MockUSDC,
    functionName: 'approve',
    args: [CONTRACTS.LendingPool, amount]
  })
  
  // 2. Deposit to pool
  await writeContract({
    abi: LendingPoolABI,
    address: CONTRACTS.LendingPool, 
    functionName: 'deposit',
    args: [amount, userAddress]
  })
}
```

---

**Catatan:** Ini adalah panduan komprehensif untuk development bertahap. Mulai dari Phase 1 dan build incrementally untuk ensure stability dan user experience yang baik pada setiap tahap. 