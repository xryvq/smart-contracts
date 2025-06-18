// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RestrictedWallet
 * @dev Non-custodial smart wallet with restricted interactions to whitelisted DEX only
 *      For leverage protocol borrowers to manage borrowed funds safely
 */
contract RestrictedWallet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice Mapping of approved target contracts (DEX addresses)
    mapping(address => bool) public approvedTargets;
    
    /// @notice Mapping of approved function selectors
    mapping(bytes4 => bool) public approvedFunctions;
    
    /// @notice Mapping of approved tokens for interaction
    mapping(address => bool) public approvedTokens;

    // ============ Events ============

    event TargetWhitelisted(address indexed target, bool approved);
    event FunctionWhitelisted(bytes4 indexed selector, bool approved);
    event TokenWhitelisted(address indexed token, bool approved);
    event TransactionExecuted(address indexed target, bytes data, uint256 value);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ External Functions ============

    /**
     * @dev Execute transaction to whitelisted target with approved function
     * @param target Target contract address (must be whitelisted)
     * @param data Transaction data (function selector must be approved)
     */
    function execute(address target, bytes calldata data) external onlyOwner nonReentrant {
        require(target != address(0), "Invalid target address");
        require(approvedTargets[target], "Target not whitelisted");
        
        if (data.length >= 4) {
            bytes4 selector = bytes4(data[:4]);
            require(approvedFunctions[selector], "Function not whitelisted");
        }
        
        (bool success, ) = target.call(data);
        require(success, "Transaction execution failed");
        
        emit TransactionExecuted(target, data, 0);
    }

    /**
     * @dev Whitelist or remove target contract (DEX address)
     * @param target Target contract address
     */
    function whitelistTarget(address target) external onlyOwner {
        require(target != address(0), "Invalid target address");
        approvedTargets[target] = true;
        emit TargetWhitelisted(target, true);
    }

    /**
     * @dev Remove target from whitelist
     * @param target Target contract address
     */
    function removeTarget(address target) external onlyOwner {
        approvedTargets[target] = false;
        emit TargetWhitelisted(target, false);
    }

    /**
     * @dev Whitelist function selector for approved transactions
     * @param selector Function selector (bytes4)
     */
    function whitelistSelector(bytes4 selector) external onlyOwner {
        approvedFunctions[selector] = true;
        emit FunctionWhitelisted(selector, true);
    }

    /**
     * @dev Remove function selector from whitelist
     * @param selector Function selector (bytes4)
     */
    function removeSelector(bytes4 selector) external onlyOwner {
        approvedFunctions[selector] = false;
        emit FunctionWhitelisted(selector, false);
    }

    /**
     * @dev Whitelist token for validation in ERC20 operations
     * @param token Token contract address
     */
    function whitelistToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        approvedTokens[token] = true;
        emit TokenWhitelisted(token, true);
    }

    /**
     * @dev Remove token from whitelist
     * @param token Token contract address
     */
    function removeToken(address token) external onlyOwner {
        approvedTokens[token] = false;
        emit TokenWhitelisted(token, false);
    }

    /**
     * @dev Get current balance of specific token
     * @param token Token contract address (0x0 for ETH)
     * @return balance Current balance
     */
    function getBalance(address token) external view returns (uint256 balance) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @dev Get current balance of the wallet (ETH)
     * @return balance Current ETH balance
     */
    function getBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @dev Emergency withdraw function for owner
     * @param token Token address (0x0 for ETH)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ============ Receive Functions ============

    /**
     * @dev Receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}


