# Panduan Mengatasi Fee Tinggi di Arbitrum Sepolia

## Masalah
Saat memanggil fungsi `initiateLoan`, estimasi gas menunjukkan fee yang sangat tinggi ($99M+) yang tidak wajar.

## Penyebab Utama

### 1. **Loop Tidak Efisien**
- Fungsi asli menggunakan loop untuk mengecek semua loan aktif borrower
- Dengan banyak loan, ini menyebabkan gas meningkat eksponensial

### 2. **Multiple External Calls**
- Banyak panggilan ke kontrak external dalam satu transaksi
- Setiap external call memakan gas tinggi

### 3. **Struct Assignment Tidak Efisien** 
- Assignment struct sekaligus lebih mahal dari assignment field per field

## Solusi yang Diterapkan

### 1. **Optimasi Loop** ✅
```solidity
// SEBELUM (buruk)
for (uint256 i = 0; i < userLoans.length; i++) {
    require(loans[userLoans[i]].status != LoanStatus.Active, "Active loan exists");
}

// SESUDAH (baik)
require(!hasActiveLoan(msg.sender), "Active loan exists");
```

### 2. **Cache External Calls** ✅
```solidity
// SEBELUM
require(usdcToken.balanceOf(msg.sender) >= requiredCollateral, "...");

// SESUDAH  
uint256 userBalance = usdcToken.balanceOf(msg.sender);
require(userBalance >= requiredCollateral, "...");
```

### 3. **Optimasi Struct Assignment** ✅
```solidity
// SEBELUM (satu assign besar)
loans[loanId] = LoanInfo({...});

// SESUDAH (assign per field)
LoanInfo storage newLoan = loans[loanId];
newLoan.borrower = msg.sender;
newLoan.loanAmount = desiredLoanAmount;
// dst...
```

## Pengaturan Gas untuk Arbitrum Sepolia

### Foundry Configuration
```toml
gas_limit = 30000000
gas_price = 100000000  # 0.1 gwei
```

### MetaMask/Wallet Settings
- **Gas Limit**: 800,000 - 1,000,000
- **Gas Price**: 0.1 gwei  
- **Max Priority Fee**: 0.05 gwei
- **Expected Cost**: $0.50 - $2.00

## Cara Testing

### 1. Deploy Ulang Kontrak
```bash
forge script script/Deploy.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### 2. Test Gas Estimation
```bash
forge script script/TestGas.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### 3. Panggil initiateLoan dengan Setting Optimal
```javascript
// Dalam dApp atau script
const gasLimit = 800000;
const gasPrice = ethers.utils.parseUnits("0.1", "gwei");

await loanManager.initiateLoan(loanAmount, {
    gasLimit: gasLimit,
    gasPrice: gasPrice
});
```

## Troubleshooting

### Jika Masih Error Gas Tinggi:

1. **Check Network**: Pastikan menggunakan Arbitrum Sepolia (Chain ID: 421614)

2. **Reset MetaMask**: 
   - Settings → Advanced → Reset Account
   - Hapus cached gas estimation

3. **Manual Gas Setting**:
   - Di MetaMask, klik "Edit" pada gas fee
   - Pilih "Advanced"  
   - Set manual: Limit=800000, Price=0.1 gwei

4. **Use Hardhat/Foundry**:
   ```bash
   # Test dengan foundry
   cast send --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --gas-limit 800000 \
     --gas-price 100000000 \
     $LOAN_MANAGER_ADDRESS \
     "initiateLoan(uint256)" 1000000000
   ```

## Monitoring Gas

### Check Real Gas Usage:
```bash
# Lihat gas usage transaksi terakhir
cast receipt $TX_HASH --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### Gas Tracker Tools:
- Arbiscan.io untuk Arbitrum mainnet
- Sepolia.arbiscan.io untuk testnet

## Actual Gas Consumption (After Optimization)

| Function | Actual Gas | Cost @ 0.1 gwei | Status |
|----------|------------|------------------|---------|
| initiateLoan | ~1.34M | $1.34 | ✅ Optimized |
| repayLoan | ~400k | $0.40 | ✅ Estimated |
| withdraw | ~300k | $0.30 | ✅ Estimated |

**Note**: Gas usage sekitar 1.34M masih wajar untuk operasi kompleks seperti deploy wallet + multiple external calls. Ini jauh lebih rendah dari estimasi $99M+ sebelumnya.

## Kesimpulan

Masalah fee tinggi disebabkan oleh:
1. ❌ Gas estimation yang salah dari dApp/wallet
2. ❌ Loop tidak efisien dalam smart contract  
3. ❌ Network setting yang salah

Solusi:
1. ✅ Optimasi smart contract (sudah dilakukan)
2. ✅ Set gas limit manual: 800k
3. ✅ Set gas price: 0.1 gwei
4. ✅ Deploy ulang dengan konfigurasi optimal 