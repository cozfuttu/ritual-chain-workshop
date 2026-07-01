// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RandomAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool finalized;
        address[] winners;
        uint256[] prizeShares;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        bool randomGenerated;
        bytes32 randomSeed;
        uint8 numberOfWinners;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool finalized;
        uint256 participantCount;
        uint256 answerCount;
        bool randomGenerated;
        uint8 numberOfWinners;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event RandomnessGenerated(uint256 indexed id, bytes32 seed);
    event WinnersSelected(uint256 indexed id, address[] winners, uint256[] shares);

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

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        uint8 numberOfWinners
    ) external payable {
        require(msg.value > 0, "Reward must be > 0");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(numberOfWinners > 0 && numberOfWinners <= 5, "Winners must be 1-5");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.numberOfWinners = numberOfWinners;

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

    function generateRandomness(uint256 id, bytes32 salt) external 
        challengeExists(id)
        onlyChallengeOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(!c.randomGenerated, "Randomness already generated");
        require(c.answers.length > 0, "No revealed answers");

        bytes32 seed = keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                block.timestamp,
                block.difficulty,
                c.participants,
                salt,
                id
            )
        );

        c.randomSeed = seed;
        c.randomGenerated = true;

        emit RandomnessGenerated(id, seed);
    }

    function selectWinners(uint256 id) external 
        challengeExists(id)
        onlyChallengeOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.randomGenerated, "Randomness not generated yet");
        require(c.answers.length > 0, "No revealed answers");

        bytes32 seed = c.randomSeed;
        uint256 participantCount = c.participants.length;
        uint8 winnersCount = c.numberOfWinners;

        address[] memory available = new address[](participantCount);
        for (uint i = 0; i < participantCount; i++) {
            available[i] = c.participants[i];
        }

        uint256 remaining = participantCount;
        uint256 totalPrize = c.reward;

        uint256[] memory shares = new uint256[](winnersCount);
        uint256 totalShares = 0;

        for (uint i = 0; i < winnersCount; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(seed, i))) % remaining;
            
            address winner = available[randomIndex];
            c.winners.push(winner);
            
            // Distribute all prize money (100%) among winners
            if (i == 0) {
                shares[i] = (totalPrize * 50) / 100;      // 50%
            } else if (i == 1) {
                shares[i] = (totalPrize * 30) / 100;      // 30%
            } else if (i == 2) {
                shares[i] = (totalPrize * 20) / 100;      // 20%
            } else {
                // For 4th and 5th winners, distribute remaining evenly
                uint256 remainingPrize = totalPrize - totalShares;
                uint256 remainingWinners = winnersCount - i;
                shares[i] = remainingPrize / remainingWinners;
            }
            
            totalShares += shares[i];
            c.prizeShares.push(shares[i]);
            
            for (uint j = randomIndex; j < remaining - 1; j++) {
                available[j] = available[j + 1];
            }
            remaining--;
        }

        // If any prize remains (due to rounding), send to first winner
        if (totalShares < totalPrize) {
            uint256 remainder = totalPrize - totalShares;
            c.winners[0] = c.winners[0];
            c.prizeShares[0] += remainder;
            totalShares += remainder;
        }

        // Distribute prizes
        for (uint i = 0; i < c.winners.length; i++) {
            payable(c.winners[i]).transfer(c.prizeShares[i]);
        }

        c.finalized = true;
        emit WinnersSelected(id, c.winners, c.prizeShares);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            finalized: c.finalized,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            randomGenerated: c.randomGenerated,
            numberOfWinners: c.numberOfWinners
        });
    }

    function getWinners(uint256 id) external view returns (address[] memory) {
        return challenges[id].winners;
    }

    function getPrizeShares(uint256 id) external view returns (uint256[] memory) {
        return challenges[id].prizeShares;
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
