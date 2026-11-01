// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "../src/Pepe.sol";

/// @dev Restricts recipients to four actors so their balances account for every base unit.
contract PepeHandler is Test {
    Pepe public immutable token;
    address[4] public actors;
    // Track successful call inputs, never copy a post-call balance into the oracle.
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Pepe token_) {
        token = token_;
        actors[0] = makeAddr("holder 0");
        actors[1] = makeAddr("holder 1");
        actors[2] = makeAddr("holder 2");
        actors[3] = makeAddr("holder 3");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        sent[from] += amount;
        received[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 limit = fromBefore < allowanceBefore ? fromBefore : allowanceBefore;
        uint256 amount = bound(rawAmount, 0, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(
            token.allowance(from, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
        sent[from] += amount;
        received[to] += amount;
        if (expectedAllowance[from][spender] != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    /// @dev Guarantees a positive delegated spend, including exact and unlimited approvals.
    function approveAndSpend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount, bool infinite)
        external
    {
        uint256 fromIndex = fromSeed % actors.length;
        for (uint256 i; i < actors.length && token.balanceOf(actors[fromIndex]) == 0; ++i) {
            fromIndex = (fromIndex + 1) % actors.length;
        }
        assertGt(token.balanceOf(actors[fromIndex]), 0, "all holders lost their tokens");
        uint256 amount = bound(rawAmount, 1, token.balanceOf(actors[fromIndex]));
        approve(fromIndex, spenderSeed, infinite ? type(uint256).max : amount);
        transferFrom(fromIndex, toSeed, spenderSeed, amount);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, fromBefore);
        transfer(fromSeed, toSeed, amount);
        transfer(toSeed, fromSeed, amount);
        assertEq(token.balanceOf(from), fromBefore, "round trip changed sender balance");
        assertEq(token.balanceOf(to), toBefore, "round trip changed recipient balance");
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: all balances and allowances must still match in the invariants.
    }

    function transferFromOverAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        // When funded, the balance is sufficient and only the allowance can reject the call.
        uint256 allowed = bound(rawAmount, 0, balance == 0 ? 0 : balance - 1);
        approve(fromSeed, spenderSeed, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, allowed + 1);
    }

    function transferFromOverBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 rawAmount,
        bool infinite
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        approve(fromSeed, spenderSeed, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(owner));
        if (operation % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (operation % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), rawAmount);
        } else {
            approve(ownerSeed, spenderSeed, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PepeInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Pepe private token;
    PepeHandler private handler;

    function setUp() public {
        token = new Pepe();
        handler = new PepeHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = PepeHandler.transfer.selector;
        selectors[1] = PepeHandler.approve.selector;
        selectors[2] = PepeHandler.transferFrom.selector;
        selectors[3] = PepeHandler.approveAndSpend.selector;
        selectors[4] = PepeHandler.roundTrip.selector;
        selectors[5] = PepeHandler.transferOverBalance.selector;
        selectors[6] = PepeHandler.transferFromOverAllowance.selector;
        selectors[7] = PepeHandler.transferFromOverBalance.selector;
        selectors[8] = PepeHandler.rejectZeroAddress.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesRemainConserved() public view {
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            accounted += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(accounted, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Pepe");
        assertEq(token.symbol(), "PEPE");
        assertEq(token.decimals(), 18);
    }

    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 initial = i == 0 ? SUPPLY : 0;
            assertEq(token.balanceOf(actor) + handler.sent(actor), initial + handler.received(actor));
        }
    }

    function invariant_allAllowancesMatchOwnerInstructions() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Every holder can still send its entire balance after any generated history.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(i, 0, token.balanceOf(handler.actors(i)));
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        handler.transfer(0, 1, SUPPLY);
        assertEq(token.balanceOf(handler.actors(0)), 0);
        assertEq(token.balanceOf(handler.actors(1)), SUPPLY);
        invariant_supplyAndBalancesRemainConserved();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allAllowancesMatchOwnerInstructions();
    }
}
