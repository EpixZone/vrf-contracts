// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.18;

/// @dev The IVRF contract's address.
address constant IVRF_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000901;

/// @dev The IVRF contract's instance.
IVRF constant IVRF_CONTRACT = IVRF(IVRF_PRECOMPILE_ADDRESS);

/**
 * @author Epix Team
 * @title VRF Precompile Interface
 * @dev Interface for accessing verifiable random beacons from the VRF module.
 * @custom:address 0x0000000000000000000000000000000000000901
 */
interface IVRF {
    /// @dev Get the random beacon at a specific block height.
    /// @param blockHeight The block height to query.
    /// @return beacon The 32-byte random beacon value (zero if not found).
    function getBeacon(uint64 blockHeight) external view returns (bytes32 beacon);

    /// @dev Get the most recent random beacon.
    /// @return beacon The latest 32-byte random beacon value.
    /// @return blockHeight The block height of the latest beacon.
    function latestBeacon() external view returns (bytes32 beacon, uint64 blockHeight);

    /// @dev Get a combined beacon from N consecutive blocks.
    /// @param endHeight The ending block height (inclusive).
    /// @param blocks The number of consecutive blocks to hash together (1-256).
    /// @return beacon The SHA-256 hash of the concatenated beacons.
    function getMultiBlockBeacon(uint64 endHeight, uint64 blocks) external view returns (bytes32 beacon);
}
