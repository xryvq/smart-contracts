// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./RestrictedWallet.sol";

/**
 * @title RestrictedWalletFactory
 * @dev Factory contract for creating restricted wallets for borrowers
 *      Each borrower gets one wallet for managing their leveraged positions
 */
contract RestrictedWalletFactory is Ownable, ReentrancyGuard {
    // ============ State Variables ============

    /// @notice Mapping to track if wallet has been created for user
    mapping(address => bool) public isWalletCreated;

    /// @notice Array of all created wallet addresses
    address[] public wallets;

    /// @notice Mapping of user addresses to their wallet addresses
    mapping(address => address) public userToWallet;

    // ============ Events ============

    event WalletCreated(address indexed wallet, address indexed owner);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ External Functions ============

    /**
     * @dev Creates a new restricted wallet for the caller
     * @return walletAddress The address of the newly created wallet
     */
    function createWallet() public nonReentrant returns (address walletAddress) {
        require(!isWalletCreated[msg.sender], "Wallet already exists for this user");
        
        // Deploy new restricted wallet
        RestrictedWallet wallet = new RestrictedWallet();
        
        // Transfer ownership to the caller
        wallet.transferOwnership(msg.sender);
        
        // Update state mappings
        isWalletCreated[msg.sender] = true;
        userToWallet[msg.sender] = address(wallet);
        wallets.push(address(wallet));
        
        emit WalletCreated(address(wallet), msg.sender);
        return address(wallet);
    }

    /**
     * @dev Gets existing wallet or creates a new one for the specified user
     * @param user The address of the user
     * @return walletAddress The wallet address
     */
    function getOrCreateWallet(address user) external nonReentrant returns (address walletAddress) {
        require(user != address(0), "Invalid user address");
        
        if (isWalletCreated[user]) {
            return userToWallet[user];
        } else {
            // Deploy new wallet for user
            RestrictedWallet wallet = new RestrictedWallet();
            
            // Transfer ownership to the user
            wallet.transferOwnership(user);
            
            // Update state mappings
            isWalletCreated[user] = true;
            userToWallet[user] = address(wallet);
            wallets.push(address(wallet));
            
            emit WalletCreated(address(wallet), user);
            return address(wallet);
        }
    }

    // ============ View Functions ============

    /**
     * @dev Returns all created wallet addresses
     * @return Array of wallet addresses
     */
    function getAllWallets() external view returns (address[] memory) {
        return wallets;
    }

    /**
     * @dev Returns the wallet address for a specific user
     * @param user The user address
     * @return walletAddress The wallet address (returns zero address if no wallet exists)
     */
    function getWallet(address user) external view returns (address walletAddress) {
        return userToWallet[user];
    }

    /**
     * @dev Check if a user has a wallet created
     * @param user The user address
     * @return hasWallet True if user has a wallet
     */
    function hasWallet(address user) external view returns (bool) {
        return isWalletCreated[user];
    }

    /**
     * @dev Get the total number of wallets created
     * @return count Total number of wallets
     */
    function getWalletCount() external view returns (uint256) {
        return wallets.length;
    }
}
