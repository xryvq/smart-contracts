// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";

/**
 * @title MockUSDCTest
 * @dev Basic unit tests for MockUSDC contract
 */
contract MockUSDCTest is Test {
    MockUSDC public usdcToken;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // $1000 USDC

    function setUp() public {
        usdcToken = new MockUSDC();
    }

    function test_InitialState() public {
        assertEq(usdcToken.name(), "Mock USDC");
        assertEq(usdcToken.symbol(), "USDC");
        assertEq(usdcToken.decimals(), 6);
        assertEq(usdcToken.totalSupply(), 0);
    }

    function test_Mint() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        assertEq(usdcToken.balanceOf(user1), MINT_AMOUNT);
        assertEq(usdcToken.totalSupply(), MINT_AMOUNT);
    }

    function test_MintToMultipleUsers() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        usdcToken.mint(user2, MINT_AMOUNT * 2);
        
        assertEq(usdcToken.balanceOf(user1), MINT_AMOUNT);
        assertEq(usdcToken.balanceOf(user2), MINT_AMOUNT * 2);
        assertEq(usdcToken.totalSupply(), MINT_AMOUNT * 3);
    }

    function test_Transfer() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        vm.prank(user1);
        usdcToken.transfer(user2, MINT_AMOUNT / 2);
        
        assertEq(usdcToken.balanceOf(user1), MINT_AMOUNT / 2);
        assertEq(usdcToken.balanceOf(user2), MINT_AMOUNT / 2);
    }

    function test_Approve() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        vm.prank(user1);
        usdcToken.approve(user2, MINT_AMOUNT);
        
        assertEq(usdcToken.allowance(user1, user2), MINT_AMOUNT);
    }

    function test_TransferFrom() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        vm.prank(user1);
        usdcToken.approve(user2, MINT_AMOUNT);
        
        vm.prank(user2);
        usdcToken.transferFrom(user1, user2, MINT_AMOUNT / 2);
        
        assertEq(usdcToken.balanceOf(user1), MINT_AMOUNT / 2);
        assertEq(usdcToken.balanceOf(user2), MINT_AMOUNT / 2);
        assertEq(usdcToken.allowance(user1, user2), MINT_AMOUNT / 2);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert("Cannot mint to zero address");
        usdcToken.mint(address(0), MINT_AMOUNT);
    }

    function test_RevertWhen_TransferInsufficientBalance() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        vm.prank(user1);
        vm.expectRevert();
        usdcToken.transfer(user2, MINT_AMOUNT + 1);
    }

    function test_RevertWhen_TransferFromInsufficientAllowance() public {
        usdcToken.mint(user1, MINT_AMOUNT);
        
        vm.prank(user2);
        vm.expectRevert();
        usdcToken.transferFrom(user1, user2, MINT_AMOUNT);
    }
} 