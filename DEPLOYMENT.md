# 🚀 Levra Protocol - Deployment Guide

## ✅ Deployment Status: BERHASIL

Tanggal: $(date)
Network: Arbitrum Sepolia Testnet (Chain ID: 421614)
Total Gas Used: ~12M gas

## 📋 Contract Addresses

| Contract | Address | Status |
|----------|---------|--------|
| **MockUSDC** | `0xE61995E2728bd2d2B1abd9e089213B542db7916A` | ✅ Deployed |
| **LendingPool** | `0xa7e82B23460233c71e8553387b2D870003A34A50` | ✅ Deployed |
| **CollateralManager** | `0x23C369A4991a477E4B9DD13F179b2e68203AbC1D` | ✅ Deployed |
| **RestrictedWalletFactory** | `0x752168dD102D1C4b9390aB6abf3Ec39f2164aD11` | ✅ Deployed |
| **LoanManager** | `0x7364EeB345989C757616988B70976BBa163B7571` | ✅ Deployed |

## 🌐 Network Information

- **Network**: Arbitrum Sepolia Testnet
- **Chain ID**: 421614
- **RPC URL**: `https://sepolia-rollup.arbitrum.io/rpc`
- **Explorer**: `https://sepolia.arbiscan.io/`
- **Gas Price**: 0.1 gwei

## 🔗 Explorer Links

- [MockUSDC](https://sepolia.arbiscan.io/address/0xE61995E2728bd2d2B1abd9e089213B542db7916A)
- [LendingPool](https://sepolia.arbiscan.io/address/0xa7e82B23460233c71e8553387b2D870003A34A50)
- [CollateralManager](https://sepolia.arbiscan.io/address/0x23C369A4991a477E4B9DD13F179b2e68203AbC1D)
- [RestrictedWalletFactory](https://sepolia.arbiscan.io/address/0x752168dD102D1C4b9390aB6abf3Ec39f2164aD11)
- [LoanManager](https://sepolia.arbiscan.io/address/0x7364EeB345989C757616988B70976BBa163B7571)

## 🧪 Testing Contracts

### 1. Mint Test USDC
```bash
cast send 0xE61995E2728bd2d2B1abd9e089213B542db7916A \
  "mint(address,uint256)" \
  <YOUR_ADDRESS> 1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

### 2. Check USDC Balance
```bash
cast call 0xE61995E2728bd2d2B1abd9e089213B542db7916A \
  "balanceOf(address)" <YOUR_ADDRESS> \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

### 3. Approve dan Deposit ke LendingPool
```bash
# Approve USDC
cast send 0xE61995E2728bd2d2B1abd9e089213B542db7916A \
  "approve(address,uint256)" \
  0xa7e82B23460233c71e8553387b2D870003A34A50 1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Deposit 100 USDC
cast send 0xa7e82B23460233c71e8553387b2D870003A34A50 \
  "deposit(uint256,address)" \
  100000000 <YOUR_ADDRESS> \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

### 4. Test Loan Initiation
```bash
# Approve USDC untuk LoanManager
cast send 0xE61995E2728bd2d2B1abd9e089213B542db7916A \
  "approve(address,uint256)" \
  0x7364EeB345989C757616988B70976BBa163B7571 200000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Initiate loan: 400 USDC loan dengan 100 USDC collateral (25% ratio)
cast send 0x7364EeB345989C757616988B70976BBa163B7571 \
  "initiateLoan(uint256,uint256)" \
  400000000 100000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --gas-limit 1000000
```

## 📁 ABI Files untuk Frontend

Generate ABI files untuk integrasi frontend:

```bash
# Run script untuk generate ABIs
chmod +x script/GenerateABIs.sh
./script/GenerateABIs.sh
```

ABI files akan tersimpan di folder `abis/`:
- `MockUSDC.json`
- `LendingPool.json` 
- `CollateralManager.json`
- `LoanManager.json`
- `RestrictedWalletFactory.json`
- `RestrictedWallet.json`

## 🔧 Konfigurasi untuk Frontend

### Web3 Configuration
```javascript
const contracts = {
  MOCK_USDC: "0xE61995E2728bd2d2B1abd9e089213B542db7916A",
  LENDING_POOL: "0xa7e82B23460233c71e8553387b2D870003A34A50",
  COLLATERAL_MANAGER: "0x23C369A4991a477E4B9DD13F179b2e68203AbC1D",
  WALLET_FACTORY: "0x752168dD102D1C4b9390aB6abf3Ec39f2164aD11",
  LOAN_MANAGER: "0x7364EeB345989C757616988B70976BBa163B7571"
};

const chainConfig = {
  chainId: 421614,
  name: "Arbitrum Sepolia",
  rpcUrl: "https://sepolia-rollup.arbitrum.io/rpc",
  blockExplorer: "https://sepolia.arbiscan.io/"
};
```

### Environment Variables untuk Frontend
```env
NEXT_PUBLIC_CHAIN_ID=421614
NEXT_PUBLIC_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
NEXT_PUBLIC_MOCK_USDC=0xE61995E2728bd2d2B1abd9e089213B542db7916A
NEXT_PUBLIC_LENDING_POOL=0xa7e82B23460233c71e8553387b2D870003A34A50
NEXT_PUBLIC_COLLATERAL_MANAGER=0x23C369A4991a477E4B9DD13F179b2e68203AbC1D
NEXT_PUBLIC_WALLET_FACTORY=0x752168dD102D1C4b9390aB6abf3Ec39f2164aD11
NEXT_PUBLIC_LOAN_MANAGER=0x7364EeB345989C757616988B70976BBa163B7571
```

## ⚠️ Important Notes

1. **Gas Limit**: Gunakan gas limit 500k-1M untuk `initiateLoan()` function
2. **USDC Decimals**: 6 decimals (1 USDC = 1,000,000 wei)
3. **Collateral Ratio**: Minimum 20% collateral required
4. **Maximum Leverage**: 5x leverage (400 USDC loan dengan 100 USDC collateral)
5. **Interest Rate**: 10% per tahun
6. **Loan Duration**: 30 hari

## 🔄 Re-deployment

Jika perlu deploy ulang contracts:

```bash
# Hapus broadcast history
rm -rf broadcast/

# Deploy fresh contracts
forge script script/Deploy.s.sol \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## 🎯 Next Steps

1. ✅ Smart contracts deployed berhasil
2. 🔄 Generate ABI files (`./script/GenerateABIs.sh`)
3. 🖥️ Integrate dengan frontend
4. 🧪 Testing end-to-end flow
5. 🔒 Security audit (recommended)
6. 🚀 Mainnet deployment

---

**Deployment berhasil! Smart contract Levra Protocol sudah siap untuk integrasi frontend dan testing PoC.** 🎉 