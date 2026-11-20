// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRF_CONTRACT} from "./IVRF.sol";

/**
 * @title VRFCoinFlip
 * @dev On-chain Over/Under game using the VRF beacon precompile.
 *
 * Flow:
 *   1. Player calls commit(guessOver, threshold) — locks in their guess at the current block.
 *   2. After 2 blocks, anyone calls reveal(player) — the contract reads the beacon
 *      from the reveal block and determines the outcome.
 *
 * The beacon is produced by the chain's VRF module at the end of each block,
 * so nobody can know the outcome when committing.
 *
 * Expiry:
 *   The chain only keeps beacons for a lookback window (the x/vrf
 *   `lookback_blocks` param, 256 by default). A game that is not revealed
 *   within that window can never settle, so once the reveal block's beacon is
 *   gone anyone may call expire(player). An expired game is recorded as a
 *   loss (result 0), so a player cannot escape a known losing round by
 *   waiting it out.
 */
contract VRFCoinFlip {
    struct Game {
        bool active;
        bool guessOver;
        uint64 threshold;    // 1-99
        uint64 commitBlock;
        uint64 revealBlock;
        uint256 gameId;
    }

    struct GameResult {
        bool guessOver;
        uint64 threshold;
        uint64 result;       // 1-100
        bool won;
        bytes32 beacon;
        uint64 revealBlock;
    }

    /// @notice Blocks the chain keeps a beacon for (x/vrf `lookback_blocks`, default 256).
    /// @dev expire() also requires the beacon to be gone, so a larger on-chain
    /// window only delays expiry, it never cuts a revealable game short.
    uint64 public constant BEACON_LOOKBACK = 256;

    event GameCommitted(
        address indexed player,
        uint256 indexed gameId,
        bool guessOver,
        uint64 threshold,
        uint64 commitBlock,
        uint64 revealBlock
    );

    event GameRevealed(
        address indexed player,
        uint256 indexed gameId,
        uint64 result,
        bool won,
        bytes32 beacon
    );

    event GameExpired(
        address indexed player,
        uint256 indexed gameId,
        uint64 revealBlock
    );

    /// @dev Active game per player.
    mapping(address => Game) private _games;

    /// @dev Game counter per player (used as gameId).
    mapping(address => uint256) public gameCount;

    /// @dev Past game results: player => gameId => result.
    mapping(address => mapping(uint256 => GameResult)) private _results;

    /// @notice Commit a guess. One active game per player.
    /// @param guessOver True = guess OVER threshold, False = guess UNDER.
    /// @param threshold The threshold (1-99). Result will be 1-100.
    function commit(bool guessOver, uint64 threshold) external {
        require(threshold >= 1 && threshold <= 99, "threshold must be 1-99");
        require(!_games[msg.sender].active, "game already active");

        uint256 id = ++gameCount[msg.sender];
        uint64 commitBlock = uint64(block.number);
        uint64 revealBlock = commitBlock + 2;

        _games[msg.sender] = Game({
            active: true,
            guessOver: guessOver,
            threshold: threshold,
            commitBlock: commitBlock,
            revealBlock: revealBlock,
            gameId: id
        });

        emit GameCommitted(msg.sender, id, guessOver, threshold, commitBlock, revealBlock);
    }

    /// @notice Reveal the outcome of a player's committed game.
    /// @param player The player whose game to reveal.
    function reveal(address player) external {
        Game memory game = _games[player];
        require(game.active, "no active game");
        require(block.number >= game.revealBlock, "too early");

        bytes32 beacon = IVRF_CONTRACT.getBeacon(game.revealBlock);
        require(beacon != bytes32(0), "beacon not available");

        // Derive result: 1-100
        uint256 raw = uint256(keccak256(abi.encodePacked(beacon, player, game.gameId)));
        uint64 result = uint64(1 + (raw % 100));

        // Determine outcome
        bool won;
        if (result == game.threshold) {
            won = false; // push counts as not-won
        } else if (game.guessOver) {
            won = result > game.threshold;
        } else {
            won = result < game.threshold;
        }

        // Store result
        _results[player][game.gameId] = GameResult({
            guessOver: game.guessOver,
            threshold: game.threshold,
            result: result,
            won: won,
            beacon: beacon,
            revealBlock: game.revealBlock
        });

        // Clear active game
        delete _games[player];

        emit GameRevealed(player, game.gameId, result, won, beacon);
    }

    /// @notice Clear a game whose reveal beacon has been pruned by the chain.
    /// @dev Callable by anyone, like reveal(). The game is recorded as a loss
    /// with result 0 (real results are 1-100) and a zero beacon.
    /// @param player The player whose game to expire.
    function expire(address player) external {
        Game memory game = _games[player];
        require(game.active, "no active game");
        require(block.number > uint256(game.revealBlock) + BEACON_LOOKBACK, "not expired");
        require(IVRF_CONTRACT.getBeacon(game.revealBlock) == bytes32(0), "beacon still available");

        _results[player][game.gameId] = GameResult({
            guessOver: game.guessOver,
            threshold: game.threshold,
            result: 0,
            won: false,
            beacon: bytes32(0),
            revealBlock: game.revealBlock
        });

        delete _games[player];

        emit GameExpired(player, game.gameId, game.revealBlock);
    }

    /// @notice Get a player's active game.
    function getGame(address player) external view returns (Game memory) {
        return _games[player];
    }

    /// @notice Get a past game result.
    function getGameResult(address player, uint256 gameId) external view returns (GameResult memory) {
        return _results[player][gameId];
    }
}
