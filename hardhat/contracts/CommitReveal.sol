// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AIJudge} from "./AIJudge.sol";

/// @title CommitReveal — Extension for AIJudge
/// @notice Adds commit-reveal support: submitter commits hash(secret+answer),
/// then reveals after deadline. Prevents plaintext answer leakage.
contract CommitReveal is AIJudge {
    uint256 public constant COMMIT_WINDOW = 3600; // 1h

    mapping(uint256 => mapping(uint256 => bytes32)) public commits;

    event AnswerCommitted(uint256 indexed bountyId, uint256 indexed submissionIndex, bytes32 commitment);

    /// @notice Submit a commit (hash of answer + secret) — no plaintext
    function commitAnswer(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp < bounty.deadline, "submissions closed");
        require(!bounty.judged, "already judged");

        bounty.submissions.push(Submission({submitter: msg.sender, answer: ""}));
        uint256 idx = bounty.submissions.length - 1;
        commits[bountyId][idx] = commitment;

        emit AnswerCommitted(bountyId, idx, commitment);
    }

    /// @notice Reveal the committed answer
    function revealAnswer(
        uint256 bountyId,
        uint256 submissionIdx,
        string calldata answer,
        bytes32 secret
    ) external {
        bytes32 expected = keccak256(abi.encodePacked(secret, answer));
        require(commits[bountyId][submissionIdx] == expected, "commit mismatch");
        require(block.timestamp >= bounty.deadline + COMMIT_WINDOW, "too early");

        Bounty storage bounty = bounties[bountyId];
        bounty.submissions[submissionIdx].answer = answer;
    }

    /// @notice Override — getBounty with commit info
    function getBounty(uint256 bountyId)
        external
        view
        override
        returns (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 deadline,
            bool judged,
            bool finalized,
            uint256 submissionCount,
            uint256 winnerIndex,
            bytes memory aiReview
        )
    {
        Bounty storage bounty = bounties[bountyId];
        return (
            bounty.owner,
            bounty.title,
            bounty.rubric,
            bounty.reward,
            bounty.deadline,
            bounty.judged,
            bounty.finalized,
            bounty.submissions.length,
            bounty.winnerIndex,
            bounty.aiReview
        );
    }
}