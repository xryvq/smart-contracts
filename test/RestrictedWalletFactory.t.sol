// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/RestrictedWalletFactory.sol";
import "../src/RestrictedWallet.sol";

/**
 * @title RestrictedWalletFactoryTest
 * @dev Unit tests for RestrictedWalletFactory contract
 */
contract RestrictedWalletFactoryTest is Test {
    RestrictedWalletFactory public walletFactory;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public unauthorizedUser = address(0x3);

    function setUp() public {
        walletFactory = new RestrictedWalletFactory();
    }

    function test_InitialState() public {
        assertEq(walletFactory.getWalletCount(), 0);
        assertFalse(walletFactory.hasWallet(user1));
        assertEq(walletFactory.getWallet(user1), address(0));
    }

    function test_CreateWallet() public {
        vm.prank(user1);
        address walletAddress = walletFactory.createWallet();
        
        assertTrue(walletAddress != address(0), "Wallet address should not be zero");
        assertEq(walletFactory.getWallet(user1), walletAddress);
        assertTrue(walletFactory.hasWallet(user1));
        assertEq(walletFactory.getWalletCount(), 1);
        
        // Verify wallet ownership
        RestrictedWallet wallet = RestrictedWallet(payable(walletAddress));
        assertEq(wallet.owner(), user1);
    }

    function test_CreateMultipleWallets() public {
        vm.prank(user1);
        address wallet1 = walletFactory.createWallet();
        
        vm.prank(user2);
        address wallet2 = walletFactory.createWallet();
        
        assertTrue(wallet1 != wallet2, "Wallets should have different addresses");
        assertEq(walletFactory.getWallet(user1), wallet1);
        assertEq(walletFactory.getWallet(user2), wallet2);
        assertTrue(walletFactory.hasWallet(user1));
        assertTrue(walletFactory.hasWallet(user2));
        assertEq(walletFactory.getWalletCount(), 2);
    }

    function test_GetWalletForNonExistentUser() public {
        assertEq(walletFactory.getWallet(user1), address(0));
        assertFalse(walletFactory.hasWallet(user1));
    }

    function test_HasWalletAfterCreation() public {
        assertFalse(walletFactory.hasWallet(user1));
        
        vm.prank(user1);
        walletFactory.createWallet();
        
        assertTrue(walletFactory.hasWallet(user1));
    }

    function test_GetWalletCount() public {
        assertEq(walletFactory.getWalletCount(), 0);
        
        vm.prank(user1);
        walletFactory.createWallet();
        assertEq(walletFactory.getWalletCount(), 1);
        
        vm.prank(user2);
        walletFactory.createWallet();
        assertEq(walletFactory.getWalletCount(), 2);
    }

    function test_GetOrCreateWallet() public {
        // First call should create wallet
        address wallet1 = walletFactory.getOrCreateWallet(user1);
        assertTrue(wallet1 != address(0));
        assertTrue(walletFactory.hasWallet(user1));
        
        // Second call should return existing wallet
        address wallet2 = walletFactory.getOrCreateWallet(user1);
        assertEq(wallet1, wallet2);
        
        // Verify count stays the same
        assertEq(walletFactory.getWalletCount(), 1);
    }

    function test_GetOrCreateWalletForNewUser() public {
        // User doesn't have wallet yet
        assertFalse(walletFactory.hasWallet(user1));
        
        // getOrCreateWallet should create new wallet
        address walletAddress = walletFactory.getOrCreateWallet(user1);
        
        // Verify wallet was created
        assertTrue(walletAddress != address(0));
        assertTrue(walletFactory.hasWallet(user1));
        assertEq(walletFactory.getWallet(user1), walletAddress);
        assertEq(walletFactory.getWalletCount(), 1);
        
        // Verify ownership
        RestrictedWallet wallet = RestrictedWallet(payable(walletAddress));
        assertEq(wallet.owner(), user1);
    }

    function test_GetAllWallets() public {
        vm.prank(user1);
        walletFactory.createWallet();
        
        vm.prank(user2);
        walletFactory.createWallet();
        
        address[] memory allWallets = walletFactory.getAllWallets();
        assertEq(allWallets.length, 2);
        
        // Verify that the wallets in the array are correct
        address wallet1 = walletFactory.getWallet(user1);
        address wallet2 = walletFactory.getWallet(user2);
        
        assertTrue(
            (allWallets[0] == wallet1 && allWallets[1] == wallet2) ||
            (allWallets[0] == wallet2 && allWallets[1] == wallet1),
            "All wallets should match created wallets"
        );
    }

    function test_WalletFunctionality() public {
        vm.prank(user1);
        address walletAddress = walletFactory.createWallet();
        
        RestrictedWallet wallet = RestrictedWallet(payable(walletAddress));
        
        // Test basic wallet functionality
        assertTrue(wallet.getBalance() == 0);
        
        // Test that wallet can receive ETH
        vm.deal(walletAddress, 1 ether);
        assertEq(wallet.getBalance(), 1 ether);
    }

    function test_MultipleWalletsIndependence() public {
        vm.prank(user1);
        address wallet1 = walletFactory.createWallet();
        
        vm.prank(user2);
        address wallet2 = walletFactory.createWallet();
        
        RestrictedWallet restrictedWallet1 = RestrictedWallet(payable(wallet1));
        RestrictedWallet restrictedWallet2 = RestrictedWallet(payable(wallet2));
        
        // Give different ETH amounts to each wallet
        vm.deal(wallet1, 1 ether);
        vm.deal(wallet2, 2 ether);
        
        assertEq(restrictedWallet1.getBalance(), 1 ether);
        assertEq(restrictedWallet2.getBalance(), 2 ether);
        
        // Verify owners are correct
        assertEq(restrictedWallet1.owner(), user1);
        assertEq(restrictedWallet2.owner(), user2);
    }

    // ============ Revert Tests ============

    function test_RevertWhen_CreateWalletForExistingUser() public {
        vm.prank(user1);
        walletFactory.createWallet();
        
        vm.prank(user1);
        vm.expectRevert("Wallet already exists for this user");
        walletFactory.createWallet();
    }

    function test_RevertWhen_GetOrCreateWalletForZeroAddress() public {
        vm.expectRevert("Invalid user address");
        walletFactory.getOrCreateWallet(address(0));
    }

    // ============ Edge Cases ============

    function test_EmptyWalletsList() public {
        address[] memory allWallets = walletFactory.getAllWallets();
        assertEq(allWallets.length, 0);
    }

    function test_WalletCountConsistency() public {
        // Initially 0
        assertEq(walletFactory.getWalletCount(), 0);
        
        // Create wallet
        vm.prank(user1);
        walletFactory.createWallet();
        assertEq(walletFactory.getWalletCount(), 1);
        
        // Try to create again (should revert)
        vm.prank(user1);
        vm.expectRevert("Wallet already exists for this user");
        walletFactory.createWallet();
        
        // Count should remain 1
        assertEq(walletFactory.getWalletCount(), 1);
        
        // getOrCreateWallet for existing user shouldn't increment count
        walletFactory.getOrCreateWallet(user1);
        assertEq(walletFactory.getWalletCount(), 1);
        
        // getOrCreateWallet for new user should increment count
        walletFactory.getOrCreateWallet(user2);
        assertEq(walletFactory.getWalletCount(), 2);
    }
} 