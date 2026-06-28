// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

contract CommitRevealBounty is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public nextBountyId = 1;

    struct Commitment {
        address submitter;
        bytes32 commitHash;
        string  answer;
        bool    revealed;
    }

    struct Bounty {
        address owner;
        string  title;
        string  rubric;
        uint256 reward;
        uint256 submitDeadline;
        uint256 revealDeadline;
        bool    judged;
        bool    finalized;
        bytes   aiReview;
        uint256 winnerIndex;
        Commitment[] commitments;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;

    event BountyCreated(uint256 indexed bountyId, address indexed owner, string title, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, uint256 indexed index, address indexed submitter);
    event AnswerRevealed(uint256 indexed bountyId, uint256 indexed index, address indexed submitter);
    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);
    event WinnerFinalized(uint256 indexed bountyId, uint256 indexed winnerIndex, address indexed winner, uint256 reward);

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "bounty not found");
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submitDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(revealDeadline > submitDeadline, "reveal must be after submit");
        bountyId = nextBountyId++;
        Bounty storage b = bounties[bountyId];
        b.owner          = msg.sender;
        b.title          = title;
        b.rubric         = rubric;
        b.reward         = msg.value;
        b.submitDeadline = submitDeadline;
        b.revealDeadline = revealDeadline;
        b.winnerIndex    = type(uint256).max;
        emit BountyCreated(bountyId, msg.sender, title, msg.value);
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp < b.submitDeadline, "submission phase over");
        require(!b.judged && !b.finalized, "bounty closed");
        require(b.commitments.length < MAX_SUBMISSIONS, "too many submissions");
        b.commitments.push(Commitment({
            submitter:  msg.sender,
            commitHash: commitment,
            answer:     "",
            revealed:   false
        }));
        emit CommitmentSubmitted(bountyId, b.commitments.length - 1, msg.sender);
    }

    function revealAnswer(
        uint256 bountyId,
        uint256 index,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp >= b.submitDeadline, "reveal phase not started");
        require(block.timestamp < b.revealDeadline, "reveal phase over");
        require(!b.judged && !b.finalized, "bounty closed");
        Commitment storage c = b.commitments[index];
        require(c.submitter == msg.sender, "not your commitment");
        require(!c.revealed, "already revealed");
        bytes32 expected = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(expected == c.commitHash, "hash mismatch");
        c.answer  = answer;
        c.revealed = true;
        emit AnswerRevealed(bountyId, index, msg.sender);
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp >= b.revealDeadline, "reveal phase not over");
        require(!b.judged, "already judged");
        require(b.commitments.length > 0, "no submissions");
        bytes memory output = _executePrecompile(LLM_INFERENCE_PRECOMPILE, llmInput);
        (bool hasError, bytes memory completionData, , string memory errorMessage,) =
            abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));
        require(!hasError, errorMessage);
        b.judged   = true;
        b.aiReview = completionData;
        emit AllAnswersJudged(bountyId, completionData);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(b.judged, "not judged yet");
        require(!b.finalized, "already finalized");
        require(b.commitments[winnerIndex].revealed, "winner did not reveal");
        b.finalized   = true;
        b.winnerIndex = winnerIndex;
        address winner = b.commitments[winnerIndex].submitter;
        uint256 reward = b.reward;
        b.reward = 0;
        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");
        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    function getBounty(uint256 bountyId) external view bountyExists(bountyId) returns (
        address owner, string memory title, string memory rubric,
        uint256 reward, uint256 submitDeadline, uint256 revealDeadline,
        bool judged, bool finalized, uint256 submissionCount, uint256 winnerIndex
    ) {
        Bounty storage b = bounties[bountyId];
        return (b.owner, b.title, b.rubric, b.reward, b.submitDeadline,
                b.revealDeadline, b.judged, b.finalized, b.commitments.length, b.winnerIndex);
    }

    function getCommitment(uint256 bountyId, uint256 index) external view bountyExists(bountyId) returns (
        address submitter, bytes32 commitHash, string memory answer, bool revealed
    ) {
        Commitment storage c = bounties[bountyId].commitments[index];
        return (c.submitter, c.commitHash, c.answer, c.revealed);
    }
}
