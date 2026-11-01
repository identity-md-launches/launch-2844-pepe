// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "src/Pepe.sol";

/// @dev Complements the deployment/basic ERC-20 tests with boundary and lifecycle properties.
/// forge-config: default.fuzz.runs = 1024
contract PepeBehaviorTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pepe private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pepe();
        holder = makeAddr("behavior holder");
        recipient = makeAddr("behavior recipient");
        spender = makeAddr("behavior spender");
        otherSpender = makeAddr("behavior other spender");
    }

    function test_oneBaseUnitCanMakeACompleteRoundTrip() public {
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillChecksBalance() public {
        assertTrue(token.transfer(holder, 1));
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(holder);
        token.transfer(holder, 2);
        assertEq(_stateDigest(), beforeState);

        vm.prank(holder);
        assertTrue(token.approve(spender, 2));
        beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(_stateDigest(), beforeState, "failed self-spend consumed allowance");
    }

    function test_maximumTransferAmountRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(recipient, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedTransferCannotOverflowOrMint() public {
        assertTrue(token.transfer(holder, SUPPLY));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.transfer(holder, SUPPLY));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY - 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function test_holderUsingTransferFromNeedsItsOwnApproval() public {
        assertTrue(token.transfer(holder, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);

        vm.startPrank(holder);
        assertTrue(token.approve(holder, 2));
        assertTrue(token.transferFrom(holder, holder, 1));
        assertEq(token.balanceOf(holder), 2);
        assertEq(token.allowance(holder, holder), 1);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, holder), 0);
    }

    function test_unlimitedAllowanceCanBeReducedThenRevoked() public {
        assertTrue(token.transfer(holder, 10));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max);

        vm.prank(holder);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 2));
        assertEq(token.allowance(holder, spender), 0);

        vm.startPrank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(_stateDigest(), beforeState);
        assertEq(token.balanceOf(holder), 7);
        assertEq(token.balanceOf(recipient), 3);
    }

    function test_approvalDoesNotReserveOrLockTokens() public {
        assertTrue(token.transfer(holder, SUPPLY));
        vm.startPrank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.transfer(recipient, SUPPLY));
        vm.stopPrank();
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, spender, 1);
        assertEq(_stateDigest(), beforeState);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, spender, 1));
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY - 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);
    }

    function test_zeroApprovalToZeroSpenderIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
    }

    function test_zeroDelegatedTransferEmitsEventAndPreservesAllowance() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroDelegatedTransferToZeroStillRevertsWithUnlimitedApproval() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_repeatedApprovalIsIdempotentAndStillEmits() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 1);
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        assertEq(_stateDigest(), beforeState);
    }

    function test_allowanceCannotBeSpentTwice() public {
        assertTrue(token.transfer(holder, 2));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(_stateDigest(), beforeState);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_wellTypedAdminCallsCannotFreezeOrSeizeHoldings() public {
        assertTrue(token.transfer(holder, SUPPLY));
        // A bool parameter must be ABI-encoded as a bool. Encoding an address here
        // could make an administrative entry point revert merely on malformed calldata.
        bytes[4] memory calls = [
            abi.encodeWithSignature("setBlacklist(address,bool)", holder, true),
            abi.encodeWithSignature("setBlocked(address,bool)", holder, true),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false),
            abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1)
        ];
        bytes32 beforeState = _stateDigest();
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer gained administrative powers");
            vm.prank(otherSpender);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger gained administrative powers");
            assertEq(_stateDigest(), beforeState);
        }
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingAllowanceImmediatelyRestrictsSpender(uint256 rawOld, uint256 rawNew) public {
        assertTrue(token.transfer(holder, SUPPLY));
        uint256 newAmount = bound(rawNew, 0, SUPPLY - 1);
        uint256 oldAmount = bound(rawOld, newAmount + 1, type(uint256).max);
        vm.startPrank(holder);
        assertTrue(token.approve(spender, oldAmount));
        assertTrue(token.approve(spender, newAmount));
        vm.stopPrank();

        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, newAmount, newAmount + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, newAmount + 1);
        assertEq(_stateDigest(), beforeState);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, newAmount));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - newAmount);
        assertEq(token.balanceOf(recipient), newAmount);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 rawBalance, uint256 rawAmount, uint256 rawAllowance)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        uint256 allowed = bound(rawAllowance, amount, type(uint256).max);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowed));
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(_stateDigest(), beforeState, "failed spend changed state");

        assertTrue(token.transfer(holder, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_spendersShareBalanceButCannotUseEachOthersAllowances(uint256 rawFirstSpend) public {
        uint256 firstSpend = bound(rawFirstSpend, 1, SUPPLY);
        assertTrue(token.transfer(holder, SUPPLY));
        vm.startPrank(holder);
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.approve(otherSpender, SUPPLY));
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, spender, firstSpend));
        assertEq(token.allowance(holder, spender), SUPPLY - firstSpend);
        assertEq(token.allowance(holder, otherSpender), SUPPLY);

        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY - firstSpend, SUPPLY)
        );
        vm.prank(otherSpender);
        token.transferFrom(holder, otherSpender, SUPPLY);
        assertEq(_stateDigest(), beforeState);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(holder, otherSpender, SUPPLY - firstSpend));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), firstSpend);
        assertEq(token.balanceOf(otherSpender), SUPPLY - firstSpend);
        assertEq(token.allowance(holder, spender), SUPPLY - firstSpend);
        assertEq(token.allowance(holder, otherSpender), firstSpend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingTransfersDoesNotChangeTheResult(uint256 rawAmount, uint256 rawFirstPart) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 firstPart = bound(rawFirstPart, 0, amount);
        Pepe splitToken = new Pepe();

        assertTrue(token.transfer(recipient, amount));
        assertTrue(splitToken.transfer(recipient, firstPart));
        assertTrue(splitToken.transfer(recipient, amount - firstPart));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(splitToken.balanceOf(recipient), token.balanceOf(recipient));
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(splitToken.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Public state for every address used by this suite, including all approval pairs.
    /// No storage layout assumptions or writes to token storage are needed for atomicity checks.
    function _stateDigest() private view returns (bytes32 digest) {
        address[7] memory accounts =
            [address(this), holder, recipient, spender, otherSpender, address(0), address(token)];
        digest = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
