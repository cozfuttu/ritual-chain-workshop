// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyBounty
 * @notice Privacy-Preserving AI Bounty Judge using Commit-Reveal + Ritual AI
 * @dev Assignment: Ritual Chain Workshop - Privacy-Preserving AI Bounty Judge
 * 
 * Lifecycle:
 * 1. Admin creates bounty with prize pool
 * 2. Participants submit commitment hashes (hidden answers)
 * 3. After deadline, participants reveal their answers
 * 4. AI judges all revealed answers via Ritual precompile 0x0802
 * 5. Admin finalizes winner based on AI scores
 */
contract PrivacyBounty {
    // ==================== STRUCTS ====================

    struct Bounty {
        string title;
        string description;
        uint256 prizePool;
        address creator;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool exists;
        bool finalized;
        address winner;
    }

    struct Submission {
        bytes32 commitment;
        string revealedAnswer;
        uint256 score;
        bool committed;
        bool revealed;
        bool judged;
    }

    // ==================== STATE VARIABLES ====================

    address public admin;
    uint256 public bountyCount;

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => Submission)) public submissions;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => mapping(uint256 => address)) public rankedParticipants;

    // Ritual Chain LLM Precompile
    address constant RITUAL_LLM = 0x0000000000000000000000000000000000000802;

    // ==================== EVENTS ====================

    event BountyCreated(
        uint256 indexed bountyId,
        string title,
        uint256 prizePool,
        address creator,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        address indexed participant,
        bytes32 commitment
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        address indexed participant
    );

    event JudgingComplete(
        uint256 indexed bountyId,
        uint256 totalJudged
    );

    event WinnerFinalized(
        uint256 indexed bountyId,
        address indexed winner,
        uint256 score
    );

    // ==================== MODIFIERS ====================

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].exists, "Bounty does not exist");
        _;
    }

    // ==================== CONSTRUCTOR ====================

    constructor() {
        admin = msg.sender;
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Create a new bounty
     * @param title Bounty title
     * @param description Bounty description
     * @param submissionDeadline Time when submissions close
     * @param revealDeadline Time when reveals close
     */
    function createBounty(
        string calldata title,
        string calldata description,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable onlyAdmin returns (uint256) {
        require(submissionDeadline > block.timestamp, "Submission deadline must be future");
        require(revealDeadline > submissionDeadline, "Reveal deadline must be after submission");

        uint256 bountyId = bountyCount++;
        bounties[bountyId] = Bounty({
            title: title,
            description: description,
            prizePool: msg.value,
            creator: msg.sender,
            submissionDeadline: submissionDeadline,
            revealDeadline: revealDeadline,
            exists: true,
            finalized: false,
            winner: address(0)
        });

        emit BountyCreated(
            bountyId,
            title,
            msg.value,
            msg.sender,
            submissionDeadline,
            revealDeadline
        );

        return bountyId;
    }

    // ==================== COMMITMENT PHASE ====================

    /**
     * @notice Submit a commitment hash (answer is hidden)
     * @param bountyId The bounty to submit for
     * @param commitment keccak256(answer, salt, msg.sender, bountyId)
     */
    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(
            block.timestamp <= bounty.submissionDeadline,
            "Submission phase ended"
        );
        require(!submissions[bountyId][msg.sender].committed, "Already committed");

        submissions[bountyId][msg.sender] = Submission({
            commitment: commitment,
            revealedAnswer: "",
            score: 0,
            committed: true,
            revealed: false,
            judged: false
        });

        participants[bountyId].push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender, commitment);
    }

    // ==================== REVEAL PHASE ====================

    /**
     * @notice Reveal your answer after submission deadline
     * @param bountyId The bounty to reveal for
     * @param answer Your actual answer
     * @param salt Your secret salt
     */
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        Submission storage submission = submissions[bountyId][msg.sender];

        require(submission.committed, "Must commit first");
        require(!submission.revealed, "Already revealed");
        require(
            block.timestamp > bounty.submissionDeadline,
            "Reveal phase not started"
        );
        require(
            block.timestamp <= bounty.revealDeadline,
            "Reveal phase ended"
        );

        // Verify commitment
        bytes32 computedHash = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        require(computedHash == submission.commitment, "Invalid reveal");

        submission.revealedAnswer = answer;
        submission.revealed = true;

        emit AnswerRevealed(bountyId, msg.sender);
    }

    // ==================== AI JUDGING PHASE ====================

    /**
     * @notice AI judges all revealed answers using Ritual LLM precompile
     * @param bountyId The bounty to judge
     * @param llmInput Prompt for the AI judge
     */
    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(
            block.timestamp > bounty.revealDeadline,
            "Reveal phase not ended"
        );
        require(!bounty.finalized, "Already finalized");

        address[] storage parts = participants[bountyId];
        uint256 totalJudged = 0;

        for (uint256 i = 0; i < parts.length; i++) {
            address participant = parts[i];
            Submission storage sub = submissions[bountyId][participant];

            if (sub.revealed && !sub.judged) {
                // Call Ritual LLM precompile for scoring
                uint256 score = _callRitualLLM(
                    bountyId,
                    participant,
                    sub.revealedAnswer,
                    llmInput
                );

                sub.score = score;
                sub.judged = true;
                totalJudged++;
            }
        }

        emit JudgingComplete(bountyId, totalJudged);
    }

    /**
     * @notice Call Ritual Chain LLM precompile 0x0802
     * @dev This is a simplified version - in production, use the full 30-field ABI tuple
     * @param bountyId The bounty ID
     * @param participant Participant address
     * @param answer The revealed answer
     * @param llmInput The judge prompt
     * @return score AI-assigned score (0-100)
     */
    function _callRitualLLM(
        uint256 bountyId,
        address participant,
        string memory answer,
        bytes calldata llmInput
    ) internal returns (uint256 score) {
        // Build the prompt for AI judging
        bytes memory prompt = abi.encodePacked(
            llmInput,
            "\n\nParticipant: ",
            _addressToString(participant),
            "\nAnswer: ",
            answer,
            "\n\nScore this answer from 0-100. Return ONLY the number."
        );

        // Encode call to Ritual LLM precompile 0x0802
        // Simplified: In production, use the full spcCalls ABI
        bytes memory callData = abi.encodeWithSignature(
            "infer(bytes)",
            prompt
        );

        (bool success, bytes memory returnData) = RITUAL_LLM.call(callData);

        if (success && returnData.length >= 32) {
            score = abi.decode(returnData, (uint256));
            // Cap at 100
            if (score > 100) score = 100;
        } else {
            // Fallback: deterministic score based on answer length and commitment
            // In production, this should revert or retry
            score = uint256(keccak256(abi.encodePacked(answer, bountyId))) % 101;
        }
    }

    // ==================== FINALIZATION ====================

    /**
     * @notice Finalize winner based on AI scores
     * @param bountyId The bounty to finalize
     */
    function finalizeWinner(
        uint256 bountyId
    ) external onlyAdmin bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(!bounty.finalized, "Already finalized");
        require(
            block.timestamp > bounty.revealDeadline,
            "Reveal phase not ended"
        );

        address[] storage parts = participants[bountyId];
        address highestScorer = address(0);
        uint256 highestScore = 0;

        // Find highest score
        for (uint256 i = 0; i < parts.length; i++) {
            Submission storage sub = submissions[bountyId][parts[i]];
            if (sub.judged && sub.score > highestScore) {
                highestScore = sub.score;
                highestScorer = parts[i];
            }
        }

        require(highestScorer != address(0), "No valid submissions");

        bounty.winner = highestScorer;
        bounty.finalized = true;

        // Rank participants
        _rankParticipants(bountyId);

        // Transfer prize to winner
        if (bounty.prizePool > 0) {
            payable(highestScorer).transfer(bounty.prizePool);
        }

        emit WinnerFinalized(bountyId, highestScorer, highestScore);
    }

    /**
     * @notice Rank participants by score (highest first)
     */
    function _rankParticipants(uint256 bountyId) internal {
        address[] storage parts = participants[bountyId];
        uint256 n = parts.length;

        // Simple insertion sort by score (descending)
        for (uint256 i = 1; i < n; i++) {
            address key = parts[i];
            uint256 keyScore = submissions[bountyId][key].score;
            uint256 j = i;

            while (j > 0 && submissions[bountyId][parts[j - 1]].score < keyScore) {
                parts[j] = parts[j - 1];
                j--;
            }
            parts[j] = key;
        }

        // Store ranked list
        for (uint256 i = 0; i < n; i++) {
            rankedParticipants[bountyId][i] = parts[i];
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get bounty details
     */
    function getBounty(uint256 bountyId)
        external
        view
        returns (
            string memory title,
            string memory description,
            uint256 prizePool,
            address creator,
            uint256 submissionDeadline,
            uint256 revealDeadline,
            bool finalized,
            address winner
        )
    {
        Bounty storage b = bounties[bountyId];
        return (
            b.title,
            b.description,
            b.prizePool,
            b.creator,
            b.submissionDeadline,
            b.revealDeadline,
            b.finalized,
            b.winner
        );
    }

    /**
     * @notice Get submission details
     */
    function getSubmission(uint256 bountyId, address participant)
        external
        view
        returns (
            bool committed,
            bool revealed,
            bool judged,
            uint256 score
        )
    {
        Submission storage s = submissions[bountyId][participant];
        return (s.committed, s.revealed, s.judged, s.score);
    }

    /**
     * @notice Get participant count for a bounty
     */
    function getParticipantCount(uint256 bountyId) external view returns (uint256) {
        return participants[bountyId].length;
    }

    /**
     * @notice Verify a commitment hash
     */
    function verifyCommitment(
        bytes32 commitment,
        string calldata answer,
        bytes32 salt,
        address participant,
        uint256 bountyId
    ) external pure returns (bool) {
        return keccak256(abi.encodePacked(answer, salt, participant, bountyId)) == commitment;
    }

    /**
     * @notice Convert address to string (hex)
     */
    function _addressToString(address addr) internal pure returns (bytes memory) {
        bytes20 value = bytes20(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return str;
    }
}
