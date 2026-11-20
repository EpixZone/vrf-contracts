// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VRFCoinFlip} from "../src/VRFCoinFlip.sol";
import {IVRF_PRECOMPILE_ADDRESS} from "../src/IVRF.sol";

/// @dev Stand-in for the VRF precompile. Etched at 0x0901 so its storage lives
/// there; tests set a beacon to simulate the chain's EndBlock and clear it to
/// simulate pruning. Unknown heights return zero, like the real precompile.
contract MockVRF {
    mapping(uint64 => bytes32) public beacons;

    function setBeacon(uint64 height, bytes32 beacon) external {
        beacons[height] = beacon;
    }

    function getBeacon(uint64 height) external view returns (bytes32) {
        return beacons[height];
    }
}

contract VRFCoinFlipTest is Test {
    VRFCoinFlip public game;
    MockVRF public vrf;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    event GameRevealed(address indexed player, uint256 indexed gameId, uint64 result, bool won, bytes32 beacon);
    event GameExpired(address indexed player, uint256 indexed gameId, uint64 revealBlock);

    function setUp() public {
        game = new VRFCoinFlip();
        vm.etch(IVRF_PRECOMPILE_ADDRESS, address(new MockVRF()).code);
        vrf = MockVRF(IVRF_PRECOMPILE_ADDRESS);
        vm.roll(100);
    }

    /// @dev Commit for `player` and return the reveal block.
    function _commit(address player, bool guessOver, uint64 threshold) internal returns (uint64) {
        vm.prank(player);
        game.commit(guessOver, threshold);
        return game.getGame(player).revealBlock;
    }

    function _expectedResult(bytes32 beacon, address player, uint256 gameId) internal pure returns (uint64) {
        return uint64(1 + (uint256(keccak256(abi.encodePacked(beacon, player, gameId))) % 100));
    }

    /// @dev Find a beacon whose result for (player, gameId) satisfies `wantHigh`
    /// (result > 50) or not (result < 50), so tests can force a win or a loss.
    function _beaconFor(address player, uint256 gameId, bool wantHigh) internal pure returns (bytes32 beacon) {
        for (uint256 i = 1;; i++) {
            beacon = keccak256(abi.encode("beacon", i));
            uint64 r = _expectedResult(beacon, player, gameId);
            if (wantHigh ? r > 50 : r < 50) return beacon;
        }
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

    function test_RevealOneBlockAfterCommitIsTooEarly() public {
        uint64 revealBlock = _commit(alice, true, 50);

        vm.roll(revealBlock - 1);
        vm.expectRevert("too early");
        game.reveal(alice);
    }

    function test_RevealInRevealBlockBeaconNotAvailable() public {
        uint64 revealBlock = _commit(alice, true, 50);

        // The beacon for the reveal block is written at that block's EndBlock,
        // so a reveal inside the reveal block itself sees no beacon yet.
        vm.roll(revealBlock);
        vm.expectRevert("beacon not available");
        game.reveal(alice);

        assertTrue(game.getGame(alice).active);
    }

    function test_RevealSucceedsAfterBeaconStored() public {
        uint64 revealBlock = _commit(alice, true, 50);
        bytes32 beacon = _beaconFor(alice, 1, true);
        uint64 expected = _expectedResult(beacon, alice, 1);

        vm.roll(revealBlock);
        vrf.setBeacon(revealBlock, beacon); // EndBlock of the reveal block
        vm.roll(revealBlock + 1);

        vm.expectEmit(true, true, false, true, address(game));
        emit GameRevealed(alice, 1, expected, true, beacon);
        vm.prank(bob); // anyone may reveal
        game.reveal(alice);

        assertFalse(game.getGame(alice).active);
        VRFCoinFlip.GameResult memory r = game.getGameResult(alice, 1);
        assertEq(r.result, expected);
        assertTrue(r.won);
        assertEq(r.beacon, beacon);
        assertEq(r.revealBlock, revealBlock);
        assertTrue(r.guessOver);
        assertEq(r.threshold, 50);

        // The player can play again.
        _commit(alice, false, 50);
        assertEq(game.getGame(alice).gameId, 2);
    }

    function test_RevealLosingGuess() public {
        uint64 revealBlock = _commit(alice, true, 50);
        bytes32 beacon = _beaconFor(alice, 1, false);

        vrf.setBeacon(revealBlock, beacon);
        vm.roll(revealBlock + 1);
        game.reveal(alice);

        VRFCoinFlip.GameResult memory r = game.getGameResult(alice, 1);
        assertLt(r.result, 50);
        assertFalse(r.won);
    }

    function test_ExpireNoGameReverts() public {
        vm.expectRevert("no active game");
        game.expire(alice);
    }

    function test_ExpireWithinWindowReverts() public {
        uint64 revealBlock = _commit(alice, true, 50);

        vm.roll(uint256(revealBlock) + game.BEACON_LOOKBACK());
        vm.expectRevert("not expired");
        game.expire(alice);
    }

    function test_ExpireRevertsWhileBeaconStillAvailable() public {
        // A losing game past the window whose beacon the chain still holds
        // (e.g. a larger lookback_blocks) must be revealed, not expired.
        uint64 revealBlock = _commit(alice, true, 50);
        vrf.setBeacon(revealBlock, _beaconFor(alice, 1, false));

        vm.roll(uint256(revealBlock) + game.BEACON_LOOKBACK() + 1);
        vm.prank(alice);
        vm.expectRevert("beacon still available");
        game.expire(alice);

        game.reveal(alice);
        assertFalse(game.getGameResult(alice, 1).won);
    }

    function test_ExpireAfterBeaconPrunedRecordsLoss() public {
        uint64 revealBlock = _commit(alice, true, 50);
        // Even a game that would have won is a loss once nobody revealed it.
        vrf.setBeacon(revealBlock, _beaconFor(alice, 1, true));

        // The chain prunes the beacon once it falls out of the lookback window.
        uint256 expiredAt = uint256(revealBlock) + game.BEACON_LOOKBACK() + 1;
        vm.roll(expiredAt);
        vrf.setBeacon(revealBlock, bytes32(0));

        vm.expectRevert("beacon not available");
        game.reveal(alice);

        vm.expectEmit(true, true, false, true, address(game));
        emit GameExpired(alice, 1, revealBlock);
        vm.prank(bob); // anyone may expire
        game.expire(alice);

        assertFalse(game.getGame(alice).active);
        VRFCoinFlip.GameResult memory r = game.getGameResult(alice, 1);
        assertEq(r.result, 0);
        assertFalse(r.won);
        assertEq(r.beacon, bytes32(0));
        assertEq(r.revealBlock, revealBlock);
        assertTrue(r.guessOver);
        assertEq(r.threshold, 50);

        vm.expectRevert("no active game");
        game.reveal(alice);

        // The player is unblocked.
        _commit(alice, true, 10);
        assertEq(game.getGame(alice).gameId, 2);
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
