// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DisputableAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 prize;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        mapping(address => bool) isParticipant;
        bool disputed;
        uint256 disputeDeadline;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 prize;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        bool disputed;
        uint256 disputeDeadline;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 prize);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event Judged(uint256 indexed id, uint256 answerCount);
    event WinnerFinalized(uint256 indexed id, address indexed winner);
    event DisputeInitiated(uint256 indexed id, address indexed disputer);
    event DisputeResolved(uint256 indexed id, address indexed newWinner);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyAfterReveal(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Reveal phase not over");
        _;
    }

    modifier onlyChallengeOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier notJudged(uint256 id) {
        require(!challenges[id].judged, "Already judged");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration
    ) external payable {
        require(msg.value > 0, "Prize must be > 0");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.prize = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function commitSolution(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);
        c.isParticipant[msg.sender] = true;

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealSolution(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function judgeAll(uint256 id, bytes calldata _llmInput) external 
        challengeExists(id)
        onlyChallengeOwner(id)
        onlyAfterReveal(id)
        notJudged(id)
    {
        Challenge storage c = challenges[id];
        require(c.answers.length > 0, "No revealed answers");

        c.judged = true;
        emit Judged(id, c.answers.length);
    }

    function finalizeWinner(uint256 id, uint256 winnerIndex) external 
        challengeExists(id)
        onlyChallengeOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.judged, "Must judge first");
        require(winnerIndex < c.answers.length, "Invalid winner index");

        c.finalized = true;
        c.winner = c.participants[winnerIndex];
        c.disputeDeadline = block.timestamp + 1 days;

        payable(c.winner).transfer(c.prize);

        emit WinnerFinalized(id, c.winner);
    }

    function initiateDispute(uint256 id) external 
        challengeExists(id)
        onlyAfterReveal(id)
    {
        Challenge storage c = challenges[id];
        require(c.finalized, "Not finalized yet");
        require(!c.disputed, "Already disputed");
        require(block.timestamp <= c.disputeDeadline, "Dispute period ended");
        require(c.isParticipant[msg.sender], "Not a participant");

        c.disputed = true;
        emit DisputeInitiated(id, msg.sender);
    }

    function resolveDispute(uint256 id, uint256 newWinnerIndex) external 
        challengeExists(id)
        onlyChallengeOwner(id)
    {
        Challenge storage c = challenges[id];
        require(c.disputed, "No active dispute");
        require(block.timestamp > c.disputeDeadline, "Dispute period still active");

        c.winner = c.participants[newWinnerIndex];
        emit DisputeResolved(id, c.winner);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            prize: c.prize,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            judged: c.judged,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            disputed: c.disputed,
            disputeDeadline: c.disputeDeadline
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }
}
