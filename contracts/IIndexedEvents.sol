// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

/// @notice Emitted when an interaction occurs. Used by wavs-indexer.
/// @param addr The address that interacted.
/// @param interactionType The type of interaction.
/// @param tags Tags to index.
/// @param data Arbitrary data associated with the interaction.
event Interaction(
    address indexed addr,
    string interactionType,
    string[] tags,
    bytes data
);
