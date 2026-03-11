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

    /// @notice Get a player's active game.
    function getGame(address player) external view returns (Game memory) {
        return _games[player];
    }

    /// @notice Get a past game result.
    function getGameResult(address player, uint256 gameId) external view returns (GameResult memory) {
        return _results[player][gameId];
    }
}
