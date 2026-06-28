# CommitRevealBounty — Privacy-Preserving AI Bounty Judge

## Overview
This contract extends the AIJudge workshop with a commit-reveal flow to prevent answer copying during the submission phase.

## Bounty Lifecycle

1. **Create** — Owner creates a bounty with a reward, submission deadline, and reveal deadline.
2. **Commit** — Participants submit only a `keccak256(answer, salt, msg.sender, bountyId)` hash. No answer is visible on-chain yet.
3. **Reveal** — After the submission deadline, participants reveal their answer and salt. Contract verifies the hash matches.
4. **Judge** — After the reveal deadline, owner calls `judgeAll()`. Ritual LLM precompile evaluates all revealed answers in one batch request.
5. **Finalize** — Owner picks the winner index. Contract pays the reward automatically.

## Key Functions

| Function | Phase | Description |
|---|---|---|
| `createBounty()` | Setup | Create bounty with deadlines and reward |
| `submitCommitment()` | Submission | Submit hash only, answer stays hidden |
| `revealAnswer()` | Reveal | Reveal answer + salt, contract verifies hash |
| `judgeAll()` | Judging | Ritual AI judges all revealed answers in batch |
| `finalizeWinner()` | Finalization | Owner picks winner, reward is paid |

## Commitment Formula
```solidity
bytes32 commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
```
Including `msg.sender` and `bountyId` prevents commitment replay attacks.

## Deployed Contract
- **Network:** Ritual Testnet (Chain ID: 1979)
- **Address:** `0xF66846EE3890Fedf878cAbc483738a4c4D983124`
- **TX Hash:** `0x2a85beb28b1f4c08e9075e859ddbebca98c7dc7a4a0c088b604be2a4346943e9`

## Architecture: Commit-Reveal vs Ritual-Native

### Commit-Reveal (Required Track)
- Answers are hashed and hidden during submission phase
- Answers become **public** after reveal phase, before AI judging
- Works on any EVM chain, no Ritual-specific features needed
- Limitation: anyone can read revealed answers before judging completes

### Ritual-Native Encrypted Submissions (Advanced Track)
- Participants encrypt answers for a Ritual TEE executor
- Only encrypted ciphertext is stored on-chain
- During `judgeAll()`, TEE decrypts answers privately inside secure enclave
- LLM receives all plaintext answers inside TEE — never exposed on-chain
- After judging, revealed answers bundle is published off-chain (IPFS), only its hash stored on-chain
- Stronger privacy: answers stay hidden until judging is fully complete

## Test Plan

### Valid Cases
- ✅ Commitment submitted before deadline → accepted
- ✅ Reveal with correct answer + salt → verified and stored
- ✅ `judgeAll()` called after reveal deadline with revealed answers → AI judges
- ✅ Winner finalized → reward transferred to winner

### Invalid Cases
- ❌ Commitment submitted after submission deadline → reverts "submission phase over"
- ❌ Reveal with wrong salt → reverts "hash mismatch"
- ❌ Reveal with wrong answer → reverts "hash mismatch"
- ❌ Reveal before submission deadline → reverts "reveal phase not started"
- ❌ Reveal after reveal deadline → reverts "reveal phase over"
- ❌ `judgeAll()` before reveal deadline → reverts "reveal phase not over"
- ❌ `finalizeWinner()` before judging → reverts "not judged yet"
- ❌ Unrevealed submission selected as winner → reverts "winner did not reveal"
- ❌ Non-owner calls `judgeAll()` → reverts "not bounty owner"

## Reflection

**What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?**

The bounty title, rubric, reward amount, and deadlines should always be public so participants know what they are competing for and under what rules. Submissions must stay hidden during the submission phase to prevent copying — this is the core fairness problem that commit-reveal solves. After judging is complete, all answers should become public so the community can verify that the AI evaluation was fair. The AI should handle objective evaluation tasks: scoring answers against the rubric, ranking submissions, and explaining its reasoning in a structured output. However, the final payout decision should remain with a human owner, because AI output can be manipulated through prompt injection or unexpected inputs, and financial transactions require human accountability. The AI recommends; the human finalizes. This separation ensures the system is both efficient and trustworthy.
