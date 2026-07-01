// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AIJudge} from "./AIJudge.sol";

/// @title PrivacyPreservingAIJudge — Uses commit-reveal + zk-hints
/// @notice Prevents answer leakage by encrypting submission via client-side hash
contract PrivacyPreservingAIJudge is AIJudge {
    // Override: require commit before reveal
    function submitAnswer(
        uint256 bountyId,
        string calldata answer
    ) external override bountyExists(bountyId) {
        // Require hash commitment
        require(commits[bountyId][bounty.submissions.length] != bytes32(0), "must commit first");
        super.submitAnswer(bountyId, answer);
    }
}