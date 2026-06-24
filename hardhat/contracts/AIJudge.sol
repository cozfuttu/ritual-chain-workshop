// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;

    function depositFor(address user, uint256 lockDuration) external payable;

    function withdraw(uint256 amount) external;

    function balanceOf(address) external view returns (uint256);

    function lockUntil(address) external view returns (uint256);
}

contract AIJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;

    uint256 public nextBountyId = 1;

    IRitualWallet public constant wallet =
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    struct Submission {
        address submitter;
        bytes32 commitment;
        string answer;
        bool revealed;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 deadline;
        bool judged;
        bool finalized;
        bytes aiReview;
        uint256 winnerIndex;
        uint256 revealedCount;
        Submission[] submissions;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => uint256)) private submissionIndexPlusOne;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 deadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter,
        bytes32 commitment
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter
    );

    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

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
        uint256 deadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(deadline > block.timestamp, "deadline must be future");

        bountyId = nextBountyId++;

        Bounty storage bounty = bounties[bountyId];

        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.deadline = deadline;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(bountyId, msg.sender, title, msg.value, deadline);
    }

    function computeCommitment(
        string memory answer,
        bytes32 salt,
        address submitter,
        uint256 bountyId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(answer, salt, submitter, bountyId));
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp < bounty.deadline, "commit phase closed");
        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");
        require(commitment != bytes32(0), "empty commitment");
        require(
            submissionIndexPlusOne[bountyId][msg.sender] == 0,
            "already committed"
        );
        require(
            bounty.submissions.length < MAX_SUBMISSIONS,
            "too many submissions"
        );

        bounty.submissions.push(
            Submission({
                submitter: msg.sender,
                commitment: commitment,
                answer: "",
                revealed: false
            })
        );

        uint256 submissionIndex = bounty.submissions.length - 1;
        submissionIndexPlusOne[bountyId][msg.sender] = submissionIndex + 1;

        emit CommitmentSubmitted(
            bountyId,
            submissionIndex,
            msg.sender,
            commitment
        );
    }

    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp >= bounty.deadline, "reveal phase not open");
        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");
        require(bytes(answer).length > 0, "empty answer");
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        uint256 indexPlusOne = submissionIndexPlusOne[bountyId][msg.sender];
        require(indexPlusOne != 0, "no commitment");

        uint256 submissionIndex = indexPlusOne - 1;
        Submission storage submission = bounty.submissions[submissionIndex];

        require(!submission.revealed, "already revealed");
        require(
            computeCommitment(answer, salt, msg.sender, bountyId) ==
                submission.commitment,
            "invalid reveal"
        );

        submission.answer = answer;
        submission.revealed = true;
        bounty.revealedCount += 1;

        emit AnswerRevealed(bountyId, submissionIndex, msg.sender);
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp >= bounty.deadline, "reveal phase not open");
        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");
        require(bounty.revealedCount > 0, "no revealed submissions");

        bytes memory output = _executePrecompile(
            LLM_INFERENCE_PRECOMPILE,
            llmInput
        );

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,

        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        require(!hasError, errorMessage);

        bounty.judged = true;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.judged, "not judged yet");
        require(!bounty.finalized, "already finalized");
        require(winnerIndex < bounty.submissions.length, "invalid winner");
        require(
            bounty.submissions[winnerIndex].revealed,
            "winner not revealed"
        );

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        address winner = bounty.submissions[winnerIndex].submitter;
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    function getBounty(
        uint256 bountyId
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 deadline,
            bool judged,
            bool finalized,
            uint256 submissionCount,
            uint256 revealedCount,
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
            bounty.revealedCount,
            bounty.winnerIndex,
            bounty.aiReview
        );
    }

    function getSubmission(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address submitter,
            bytes32 commitment,
            string memory answer,
            bool revealed
        )
    {
        Bounty storage bounty = bounties[bountyId];

        require(index < bounty.submissions.length, "invalid index");

        Submission storage submission = bounty.submissions[index];

        return (
            submission.submitter,
            submission.commitment,
            submission.answer,
            submission.revealed
        );
    }

    function getRevealedSubmissionCount(
        uint256 bountyId
    ) external view bountyExists(bountyId) returns (uint256) {
        return bounties[bountyId].revealedCount;
    }

    function getSubmissionIndex(
        uint256 bountyId,
        address submitter
    ) external view bountyExists(bountyId) returns (uint256 index, bool exists) {
        uint256 indexPlusOne = submissionIndexPlusOne[bountyId][submitter];
        if (indexPlusOne == 0) {
            return (0, false);
        }
        return (indexPlusOne - 1, true);
    }
}
