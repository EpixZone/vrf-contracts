// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VRFCoinFlip} from "../src/VRFCoinFlip.sol";

contract VRFCoinFlipTest is Test {
    VRFCoinFlip public game;
    address public alice = makeAddr("alice");

    function setUp() public {
        game = new VRFCoinFlip();
    }

    function test_CommitCreatesActiveGame() public {
        vm.prank(alice);
        game.commit(true, 50);

        VRFCoinFlip.Game memory g = game.getGame(alice);
        assertTrue(g.active);
        assertTrue(g.guessOver);
        assertEq(g.threshold, 50);
        assertEq(g.gameId, 1);
        assertEq(g.revealBlock, g.commitBlock + 2);
    }

    function test_CommitIncreasesGameCount() public {
        vm.startPrank(alice);

        game.commit(false, 30);
        assertEq(game.gameCount(alice), 1);

        // Can't commit while active
        vm.expectRevert("game already active");
        game.commit(true, 50);

        vm.stopPrank();
    }

    function test_CommitRejectsInvalidThreshold() public {
        vm.startPrank(alice);

        vm.expectRevert("threshold must be 1-99");
        game.commit(true, 0);

        vm.expectRevert("threshold must be 1-99");
        game.commit(true, 100);

        vm.stopPrank();
    }

    function test_RevealTooEarlyReverts() public {
        vm.prank(alice);
        game.commit(true, 50);

        // Same block — too early
        vm.expectRevert("too early");
        game.reveal(alice);
    }

    function test_RevealNoGameReverts() public {
        vm.expectRevert("no active game");
        game.reveal(alice);
    }

    function test_GetGameReturnsInactiveForNewPlayer() public view {
        VRFCoinFlip.Game memory g = game.getGame(alice);
        assertFalse(g.active);
        assertEq(g.gameId, 0);
    }

    function testFuzz_ThresholdBounds(uint64 threshold) public {
        vm.assume(threshold >= 1 && threshold <= 99);
        vm.prank(alice);
        game.commit(true, threshold);

        VRFCoinFlip.Game memory g = game.getGame(alice);
        assertEq(g.threshold, threshold);
    }
}
