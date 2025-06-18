// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/RestrictedWallet.sol";

/**
 * @title RestrictedWalletTest
 * @dev Unit tests for RestrictedWallet with whitelist functionality
 */
contract RestrictedWalletTest is Test {
    MockUSDC public usdcToken;
    RestrictedWallet public restrictedWallet;
    
    address public owner = address(0x1);
    address public unauthorizedUser = address(0x2);
    address public dexAddress = address(0x3);
    address public tokenAddress = address(0x4);
    
    bytes4 public constant SWAP_SELECTOR = bytes4(keccak256("swap(uint256,uint256,address[],address,uint256)"));
    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    
    uint256 public constant INITIAL_AMOUNT = 10_000 * 1e6; // $10k USDC

    function setUp() public {
        usdcToken = new MockUSDC();
        
        vm.prank(owner);
        restrictedWallet = new RestrictedWallet();
        
        // Mint USDC for testing
        usdcToken.mint(owner, INITIAL_AMOUNT);
        usdcToken.mint(address(this), INITIAL_AMOUNT * 2); // For test contract
    }

    function test_InitialState() public {
        assertEq(restrictedWallet.owner(), owner);
        assertEq(restrictedWallet.getBalance(), 0); // Should be 0 initially, not INITIAL_AMOUNT
        assertFalse(restrictedWallet.approvedTargets(dexAddress));
        assertFalse(restrictedWallet.approvedFunctions(SWAP_SELECTOR));
        assertFalse(restrictedWallet.approvedTokens(address(usdcToken)));
    }

    function test_WhitelistTarget() public {
        vm.prank(owner);
        restrictedWallet.whitelistTarget(dexAddress);
        
        assertTrue(restrictedWallet.approvedTargets(dexAddress));
    }

    function test_WhitelistSelector() public {
        vm.prank(owner);
        restrictedWallet.whitelistSelector(SWAP_SELECTOR);
        
        assertTrue(restrictedWallet.approvedFunctions(SWAP_SELECTOR));
    }

    function test_WhitelistToken() public {
        vm.prank(owner);
        restrictedWallet.whitelistToken(address(usdcToken));
        
        assertTrue(restrictedWallet.approvedTokens(address(usdcToken)));
    }

    function test_RemoveTarget() public {
        vm.startPrank(owner);
        restrictedWallet.whitelistTarget(dexAddress);
        assertTrue(restrictedWallet.approvedTargets(dexAddress));
        
        restrictedWallet.removeTarget(dexAddress);
        assertFalse(restrictedWallet.approvedTargets(dexAddress));
        vm.stopPrank();
    }

    function test_RemoveSelector() public {
        vm.startPrank(owner);
        restrictedWallet.whitelistSelector(SWAP_SELECTOR);
        assertTrue(restrictedWallet.approvedFunctions(SWAP_SELECTOR));
        
        restrictedWallet.removeSelector(SWAP_SELECTOR);
        assertFalse(restrictedWallet.approvedFunctions(SWAP_SELECTOR));
        vm.stopPrank();
    }

    function test_RemoveToken() public {
        vm.startPrank(owner);
        restrictedWallet.whitelistToken(address(usdcToken));
        assertTrue(restrictedWallet.approvedTokens(address(usdcToken)));
        
        restrictedWallet.removeToken(address(usdcToken));
        assertFalse(restrictedWallet.approvedTokens(address(usdcToken)));
        vm.stopPrank();
    }

    function test_GetBalanceETH() public {
        vm.deal(address(restrictedWallet), 1 ether);
        assertEq(restrictedWallet.getBalance(), 1 ether);
    }

    function test_GetBalanceToken() public {
        // Transfer some USDC to wallet first
        usdcToken.transfer(address(restrictedWallet), INITIAL_AMOUNT);
        uint256 balance = restrictedWallet.getBalance(address(usdcToken));
        assertEq(balance, INITIAL_AMOUNT);
    }

    function test_EmergencyWithdrawToken() public {
        // Transfer USDC to wallet first
        usdcToken.transfer(address(restrictedWallet), INITIAL_AMOUNT);
        uint256 initialBalance = usdcToken.balanceOf(owner);
        
        vm.prank(owner);
        restrictedWallet.emergencyWithdraw(address(usdcToken), owner, INITIAL_AMOUNT);
        
        assertEq(usdcToken.balanceOf(owner), initialBalance + INITIAL_AMOUNT);
        assertEq(usdcToken.balanceOf(address(restrictedWallet)), 0);
    }

    
    function test_ReceiveETH() public {
        uint256 ethAmount = 1 ether;
        vm.deal(address(this), ethAmount);
        
        (bool success, ) = address(restrictedWallet).call{value: ethAmount}("");
        assertTrue(success);
        assertEq(address(restrictedWallet).balance, ethAmount);
    }

    // ============ Revert Tests ============

    function test_RevertWhen_UnauthorizedWhitelistTarget() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        restrictedWallet.whitelistTarget(dexAddress);
    }

    function test_RevertWhen_UnauthorizedWhitelistSelector() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        restrictedWallet.whitelistSelector(SWAP_SELECTOR);
    }

    function test_RevertWhen_UnauthorizedWhitelistToken() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        restrictedWallet.whitelistToken(address(usdcToken));
    }

    function test_RevertWhen_UnauthorizedEmergencyWithdraw() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        restrictedWallet.emergencyWithdraw(address(usdcToken), unauthorizedUser, INITIAL_AMOUNT);
    }

    function test_RevertWhen_WhitelistZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid target address");
        restrictedWallet.whitelistTarget(address(0));
    }

    function test_RevertWhen_WhitelistTokenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        restrictedWallet.whitelistToken(address(0));
    }

    function test_RevertWhen_EmergencyWithdrawZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert("Invalid recipient address");
        restrictedWallet.emergencyWithdraw(address(usdcToken), address(0), INITIAL_AMOUNT);
    }

    function test_RevertWhen_EmergencyWithdrawZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        restrictedWallet.emergencyWithdraw(address(usdcToken), owner, 0);
    }

    function test_RevertWhen_ExecuteTargetNotWhitelisted() public {
        bytes memory data = abi.encodeWithSelector(TRANSFER_SELECTOR, owner, 1000);
        
        vm.prank(owner);
        vm.expectRevert("Target not whitelisted");
        restrictedWallet.execute(dexAddress, data);
    }

    function test_RevertWhen_ExecuteFunctionNotWhitelisted() public {
        vm.startPrank(owner);
        restrictedWallet.whitelistTarget(dexAddress);
        
        bytes memory data = abi.encodeWithSelector(TRANSFER_SELECTOR, owner, 1000);
        
        vm.expectRevert("Function not whitelisted");
        restrictedWallet.execute(dexAddress, data);
        vm.stopPrank();
    }

    function test_RevertWhen_ExecuteInvalidTarget() public {
        vm.prank(owner);
        vm.expectRevert("Invalid target address");
        restrictedWallet.execute(address(0), "");
    }

    // ============ Integration Tests ============

    function test_ExecuteWhitelistedFunction() public {
        // Setup mock DEX contract
        MockDEX mockDex = new MockDEX();
        
        vm.startPrank(owner);
        restrictedWallet.whitelistTarget(address(mockDex));
        restrictedWallet.whitelistSelector(MockDEX.mockSwap.selector);
        
        bytes memory data = abi.encodeWithSelector(MockDEX.mockSwap.selector, 1000);
        restrictedWallet.execute(address(mockDex), data);
        vm.stopPrank();
        
        assertTrue(mockDex.swapCalled());
    }
}

// Mock DEX contract for testing
contract MockDEX {
    bool public swapCalled = false;
    
    function mockSwap(uint256 amount) external {
        swapCalled = true;
    }
} 