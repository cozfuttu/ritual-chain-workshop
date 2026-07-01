// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AIJudge} from "./AIJudge.sol";

/// @title DisputableBounty — Adds dispute period after winner selection
contract DisputableBounty is AIJudge {
    uint256 public constant DISPUTE_PERIOD = 86400; // 24h

    mapping(uint256 => uint256) public disputesStart;

    event DisputeOpened(uint256 indexed bountyId, uint256 indexed submitterIdx);
    event DisputeResolved(uint256 indexed bountyId, address winner);

    /// @notice Open dispute — challenger pays bond
    function openDispute(
        uint256 bountyId,
        uint256 submissionIdx
    ) external payable bountyExists(bountyId) {
        require(msg.value > 0, "bond required");
        Bounty storage bounty = bounties[bountyId];
        require(bounty.finalized, "not finalized yet");
        require(block.timestamp < disputesStart[bountyId] + DISPUTE_PERIOD, "too late");

        disputesStart[bountyId] = block.timestamp;

        emit DisputeOpened(bountyId, submissionIdx);
    }

    /// @notice Resolve — if no rebuttal within period, winner stays
    function resolve(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];
        require(disputesStart[bountyId] > 0, "no dispute");
        require(block.timestamp >= disputesStart[bountyId] + DISPUTE_PERIOD, "not expired");

        emit DisputeResolved(bountyId, address(0));
    }
}