# Privacy-Preserving AI Bounty Judge

This Hardhat package contains the updated `AIJudge` contract for the Ritual Academy assignment.

The original workshop contract stored answers directly on-chain during the submission period. That made every answer public immediately, so later participants could copy existing answers and improve them. This version fixes that required-track flaw with a standard EVM-compatible **commit-reveal** flow.

## Lifecycle

### 1. Create bounty

The bounty owner creates a bounty with a title, rubric, deadline, and reward:

```solidity
createBounty(string title, string rubric, uint256 deadline) payable
```

The reward is held by the `AIJudge` contract until the owner finalizes a winner.

### 2. Commit phase — hidden answers

Before the deadline, each participant computes a commitment off-chain:

```solidity
keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

Then they submit only the hash:

```solidity
submitCommitment(uint256 bountyId, bytes32 commitment)
```

During this phase, the contract stores only:

- submitter address
- commitment hash
- empty answer string
- `revealed = false`

The plaintext answer and salt stay with the participant.

### 3. Reveal phase — prove the hidden answer

After the deadline, participants reveal their answer and salt:

```solidity
revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt)
```

The contract recomputes:

```solidity
keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

If the recomputed hash matches the stored commitment, the answer is marked as revealed and becomes eligible for judging. Wrong salt, wrong answer, or a different wallet cannot reveal the commitment.

### 4. AI judging — batch judging only

The bounty owner calls:

```solidity
judgeAll(uint256 bountyId, bytes calldata llmInput)
```

Only revealed answers should be included in the `llmInput` prompt. The contract calls Ritual's LLM precompile at:

```txt
0x0000000000000000000000000000000000000802
```

This should be one batch LLM request containing the bounty rubric and all valid revealed answers, not one LLM call per answer.

### 5. Human finalization

The owner finalizes the winner:

```solidity
finalizeWinner(uint256 bountyId, uint256 winnerIndex)
```

The AI review helps the owner evaluate submissions, but the contract keeps the final reward decision human-controlled. The winner index must point to a revealed submission.

## Required functions implemented

- `submitCommitment(uint256 bountyId, bytes32 commitment)`
- `revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt)`
- `judgeAll(uint256 bountyId, bytes calldata llmInput)`
- `finalizeWinner(uint256 bountyId, uint256 winnerIndex)`

Additional helpers:

- `computeCommitment(string answer, bytes32 salt, address submitter, uint256 bountyId)`
- `getSubmission(uint256 bountyId, uint256 index)`
- `getRevealedSubmissionCount(uint256 bountyId)`
- `getSubmissionIndex(uint256 bountyId, address submitter)`

## Test plan

The Solidity test file is:

```txt
contracts/AIJudgeCommitReveal.t.sol
```

Run:

```shell
npx hardhat test solidity
```

Test cases cover:

1. A commitment stores only a hash and no public answer.
2. A correct reveal after the deadline stores the plaintext answer and marks it eligible.
3. Reveal with the wrong salt reverts.
4. Reveal from a different wallet reverts.
5. Commitments after the deadline revert.
6. Reveals before the deadline revert.
7. Judging with no revealed answers reverts.
8. Finalizing before judging reverts.

## Architecture note: Required Track

### What is public

- bounty title
- bounty rubric
- deadline
- reward amount
- submitter addresses
- commitment hashes
- revealed answers after the deadline
- AI review result after judging
- final winner and payment event

### What stays hidden before reveal

- plaintext answer
- salt

The salt must be random and saved by the participant. If the participant loses the salt, they cannot reveal their answer.

### Why the hash includes `msg.sender` and `bountyId`

The commitment binds the answer to one wallet and one bounty:

```solidity
keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

This prevents someone else from taking a revealed answer/salt pair and reusing it under a different address or bounty.

## Architecture note: Advanced Ritual-native hidden submissions

A stronger Ritual-native version could keep submissions encrypted even through judging. In that design:

### Stored on-chain

- bounty metadata
- ciphertext hash or encrypted submission reference
- submitter address
- eligibility/commitment metadata
- final AI review or encrypted AI result

### Stored off-chain

- encrypted full answers, for example in a storage provider such as GCS, HuggingFace, Pinata, IPFS, or a frontend-managed storage service

### Where plaintext exists

Plaintext should exist only in these places:

1. In the participant's browser before encryption.
2. Inside the Ritual TEE executor during batch judging.
3. In the final output only if the app intentionally publishes the judging summary or revealed answers.

### How the LLM receives submissions

The frontend or contract would pass encrypted answer references/secrets to a Ritual TEE-backed execution flow. The executor decrypts all valid submissions inside the TEE, builds one batch prompt containing the bounty rubric and all answers, and sends one LLM request for judging. This satisfies the Ritual focus: use encrypted secrets/private inputs and batch judging, not one LLM call per answer.

## Reflection question

**What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?**

Bounty metadata such as the title, reward, deadline, rules, and final winner should be public so participants can verify that the process is fair. Submissions should stay hidden during the active submission phase because public answers allow copying, plagiarism, and last-minute improvement based on other people’s work. In the commit-reveal version, only the commitment hash is public before the deadline, while the actual answer and salt stay private with the participant until reveal. After the reveal phase, valid answers can become public so the community can audit what was judged. AI should help evaluate submissions against the rubric, summarize strengths and weaknesses, and recommend a winner. However, the final decision and reward transfer should stay under human control because AI can make mistakes, misunderstand context, or be manipulated by prompt wording. Ritual’s TEE-backed execution can improve this further by letting encrypted submissions stay hidden even during judging, with plaintext only appearing inside secure execution. The best design is transparent about rules and outcomes, private during competition, AI-assisted during review, and human-finalized for accountability.

## Ritual deployment notes

Ritual network configuration is already present in `hardhat.config.ts`:

```txt
RPC: https://rpc.ritualfoundation.org
Chain ID: 1979
LLM precompile: 0x0000000000000000000000000000000000000802
RitualWallet: 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948
```

The LLM precompile requires RitualWallet funding for async execution fees. The bounty reward stays in the `AIJudge` contract; LLM execution fees are separate.
