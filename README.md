# AI Bounty Judge: Commit-Reveal Version

## Overview

This project implements a commit-reveal version of the AI Bounty Judge to prevent participants from copying each other's submissions before the competition ends.

Instead of submitting plaintext answers immediately, participants first submit a cryptographic commitment. The actual answer is revealed only during the reveal phase and verified against the commitment. After the reveal deadline, Ritual AI evaluates all valid submissions together in a single batch, and the bounty owner finalizes the winner.

---

# Problem

In the original workshop implementation, answers were stored publicly as soon as they were submitted. This allowed later participants to read previous answers, improve upon them, and gain an unfair advantage.

This implementation solves that problem using a commit-reveal workflow.

---

# Bounty Lifecycle

## 1. Create Bounty

The bounty owner creates a bounty by specifying:

- reward
- submission deadline
- reveal deadline

---

## 2. Commit Phase

Before the submission deadline, each participant submits only a commitment hash.

Example:

```solidity
bytes32 commitment =
    keccak256(
        abi.encodePacked(
            answer,
            salt,
            msg.sender,
            bountyId
        )
    );
```

Only the commitment is stored on-chain.

The answer remains secret.

---

## 3. Reveal Phase

After the submission deadline and before the reveal deadline, participants reveal:

- answer
- salt

The contract recomputes the hash and verifies that it matches the stored commitment.

Only valid reveals become eligible for judging.

Unrevealed submissions are ignored.

---

## 4. AI Batch Judging

After the reveal deadline, the bounty owner calls:

```solidity
judgeAll()
```

Ritual AI receives all valid revealed submissions together in one batch.

The AI ranks and scores all eligible answers.

No individual LLM calls are made per submission.

---

## 5. Finalize Winner

After judging is complete, the owner calls:

```solidity
finalizeWinner()
```

The selected winner receives the bounty reward.

Only one winner can be finalized.

---

# Smart Contract Rules

The contract enforces the following:

- Commitments are accepted only before the submission deadline.
- Answers can only be revealed after the submission deadline and before the reveal deadline.
- One commitment per participant per bounty.
- Reveals must match the stored commitment.
- Unrevealed submissions are not judged.
- Judging begins only after the reveal deadline.
- Finalization occurs only after judging completes.
- Only one winner receives payment.

---

# Security Considerations

This implementation improves fairness by:

- hiding answers during submission
- preventing copied commitments using:
  - msg.sender
  - bountyId
- verifying reveals cryptographically
- preventing duplicate submissions
- preventing premature judging
- separating AI recommendation from payout

The AI recommends rankings, while the bounty owner remains responsible for finalizing the winner.

---

# Test Plan

The following scenarios should be tested.

## Valid Cases

- Create bounty successfully.
- Submit a valid commitment.
- Reveal correct answer and salt.
- Judge all revealed submissions.
- Finalize one winner.
- Reward transfers correctly.

## Invalid Cases

- Submit after submission deadline.
- Reveal before submission deadline.
- Reveal after reveal deadline.
- Reveal with incorrect salt.
- Reveal incorrect answer.
- Submit two commitments for one bounty.
- Judge before reveal deadline.
- Finalize before judging.
- Attempt multiple finalizations.
- Attempt reward transfer twice.

---

# Commit-Reveal vs Ritual-Native Private Submission

## Commit-Reveal

### On-chain

- commitment hashes
- revealed answers
- scores
- winner

### Advantages

- Simple
- Works on any EVM chain
- Strong fairness during submission

### Limitation

Answers become public during the reveal phase before AI judging.

---

## Ritual-Native Private Submission

Participants encrypt their answers for a Ritual Trusted Execution Environment [TEE].

### On-chain

- encrypted submission reference
- encrypted submission hash

### Off-chain

- encrypted answers
- decryption keys
- AI evaluation

During `judgeAll()`, the TEE decrypts every submission privately and sends all answers to the LLM in one batch.

After judging completes, the system publishes:

- winner
- ranking
- revealedAnswersRef
- revealedAnswersHash

This approach prevents participants from seeing any plaintext submissions before AI evaluation while preserving verifiable integrity.

---

# Reflection

In a bounty system, submissions should remain hidden during the competition phase to preserve fairness and prevent copying. Public information should include commitments, deadlines, and final results, while the actual answers remain hidden until the appropriate stage. AI should evaluate and rank submissions according to the rubric, but it should not automatically transfer rewards. A human should review the AI recommendation and finalize the payout to reduce the impact of incorrect or unexpected AI outputs. Combining cryptographic commitments with Ritual's private execution provides both fairness and transparency. This design protects participants while maintaining trust in the judging process.

---

# Conclusion

This implementation introduces a secure commit-reveal workflow that prevents answer copying while preserving compatibility with EVM chains. The optional Ritual-native design further enhances privacy by allowing encrypted submissions to remain confidential until AI evaluation is complete.
