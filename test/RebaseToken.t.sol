// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");
    uint256 public constant SEND_VALUE = 1e5;
    uint256 public constant INTEREST_RATE = 5e10;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        (bool success,) = payable(address(vault)).call{value: amount}("");
        require(success, "Transfer to vault failed");
    }

    function testInterestRate() public view {
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, INTEREST_RATE);
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);

        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("middleBalance", middleBalance);
        assertGt(middleBalance, startBalance);

        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        // Deposit funds
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // Redeem all funds
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 balance = rebaseToken.balanceOf(user);
        console.log("User balance: %d", balance);
        assertEq(balance, 0);
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1e3, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        // Deposit funds
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // check the balance has increased after some time has passed
        vm.warp(time);
        uint256 balance = rebaseToken.balanceOf(user);
        assertGt(balance, depositAmount);

        // Add rewards to the vault
        vm.deal(owner, balance - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balance - depositAmount);

        // Redeem funds
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
        assertGt(balance, depositAmount);
    }

    function testCannotCallMint() public {
        uint256 interestRate = rebaseToken.getInterestRate();

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, SEND_VALUE, interestRate);
    }

    function testCannotCallBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, SEND_VALUE);
    }

    function testCannotWithdrawMoreThanBalance() public {
        vm.deal(user, SEND_VALUE);

        vm.startPrank(user);
        vault.deposit{value: SEND_VALUE}();
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        // make a deposit by just the sender
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address recipient = makeAddr("recipient");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 recipientBalance = rebaseToken.balanceOf(recipient);
        assertEq(userBalance, amount);
        assertEq(recipientBalance, 0);

        // Update the interest rate so we can check the user interest rates are different after transferring.
        vm.prank(owner);
        rebaseToken.setInterestRate(INTEREST_RATE * 4 / 5);

        // Send a portion of the balance to another user
        vm.prank(user);
        rebaseToken.transfer(recipient, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 recipientBalancAfterTransfer = rebaseToken.balanceOf(recipient);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(recipientBalancAfterTransfer, recipientBalance + amountToSend);

        // After some time has passed, check the balance of the two users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfterWarp = rebaseToken.balanceOf(recipient);
        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(recipientBalanceAfterWarp, recipientBalancAfterTransfer);

        // check their interest rates are as expected
        // since recipient hadn't minted before, their interest rate should be the same as in the contract
        uint256 recipientInterestRate = rebaseToken.getUserInterestRate(recipient);
        assertEq(recipientInterestRate, INTEREST_RATE);

        // since user had minted before, their interest rate should be the previous interest rate
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, INTEREST_RATE);
    }

    function testSetInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, 0, INTEREST_RATE - 1);

        // Update the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, newInterestRate);

        // interest rate is 0 for a user who has't interacted with the contract
        assertEq(rebaseToken.getUserInterestRate(user), 0);

        // check that if someone deposits, this is their new interest rate
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, newInterestRate);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);

        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    function testGetPrincipleAmount(uint256 amount, uint256 time) public {
        time = bound(time, 1e3, type(uint96).max);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, amount);
    }
}
