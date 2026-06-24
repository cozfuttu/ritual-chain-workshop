# 🔐 Privacy-Preserving AI Bounty Judge

> Ritual Chain Workshop Assignment — Commit-Reveal + AI Judging via Ritual Precompile

## 📋 Overview

A bounty system where submissions remain **hidden** until judging is complete, preventing participants from copying others' ideas. Uses **commit-reveal** mechanism + **Ritual Chain's LLM precompile (0x0802)** for AI-powered judging.

## 🔄 Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOUNTY LIFECYCLE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. CREATE BOUNTY                                               │
│     └─ Admin creates bounty with prize pool + deadlines        │
│                                                                 │
│  2. SUBMISSION PHASE (Commit)                                   │
│     └─ Participants submit keccak256(answer, salt, sender, id) │
│     └─ Answer is HIDDEN — only hash is stored on-chain         │
│                                                                 │
│  3. REVEAL PHASE                                                │
│     └─ Participants reveal answer + salt                        │
│     └─ Contract verifies hash matches commitment                │
│     └─ Invalid reveals are rejected                             │
│                                                                 │
│  4. AI JUDGING                                                  │
│     └─ Admin triggers judging via Ritual LLM precompile 0x0802 │
│     └─ AI scores each revealed answer (0-100)                  │
│     └─ Scores are stored on-chain                               │
│                                                                 │
│  5. FINALIZATION                                                │
│     └─ Admin finalizes winner (highest score)                   │
│     └─ Prize pool transferred to winner                         │
│     └─ Participants ranked by score                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🛠️ Functions

### Admin Functions
```solidity
// Create a new bounty with prize pool
createBounty(title, description, submissionDeadline, revealDeadline) payable

// Trigger AI judging on all revealed answers
judgeAll(bountyId, llmInput)

// Finalize winner and distribute prize
finalizeWinner(bountyId)
```

### Participant Functions
```solidity
// Submit commitment hash (answer is hidden)
submitCommitment(bountyId, commitment)

// Reveal answer after submission deadline
revealAnswer(bountyId, answer, salt)
```

### View Functions
```solidity
getBounty(bountyId)           // Get bounty details
getSubmission(bountyId, addr) // Get submission status
getParticipantCount(bountyId) // Get participant count
verifyCommitment(...)         // Verify a commitment hash
```

## 🔒 Security Features

1. **Commit-Reveal** — Answers hidden until reveal phase
2. **Hash Verification** — `keccak256(answer, salt, sender, bountyId)` must match
3. **Time-Locked Phases** — Submission → Reveal → Judging → Finalize
4. **Duplicate Prevention** — One commitment per participant per bounty
5. **Admin Controls** — Only admin can create bounties and finalize winners

## 🧪 Test Coverage

```bash
forge test -vv
```

| Test | Status |
|------|--------|
| Create Bounty | ✅ |
| Create Bounty (Non-Admin Revert) | ✅ |
| Submit Commitment | ✅ |
| Submit Commitment (After Deadline) | ✅ |
| Submit Commitment (Duplicate) | ✅ |
| Reveal Answer | ✅ |
| Reveal Answer (Invalid) | ✅ |
| Reveal Answer (Before Deadline) | ✅ |
| Verify Commitment | ✅ |
| Verify Commitment (Invalid) | ✅ |

## 🚀 Deploy to Ritual Chain

```bash
# Set private key in .env
export PRIVATE_KEY=your_private_key

# Deploy
forge create src/PrivacyBounty.sol:PrivacyBounty \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $PRIVATE_KEY
```

## 🔗 Ritual Chain Integration

**LLM Precompile:** `0x0000000000000000000000000000000000000802`

The contract calls Ritual's LLM precompile for AI judging:
- Encodes prompt with participant answer
- Calls precompile 0x0802 for inference
- Parses score from response
- Fallback: deterministic score if precompile unavailable

## 📁 Project Structure

```
privacy-bounty-judge/
├── src/
│   └── PrivacyBounty.sol    # Main contract
├── test/
│   └── PrivacyBounty.t.sol  # Tests
├── script/
│   └── Deploy.s.sol         # Deploy script (optional)
├── foundry.toml             # Foundry config
└── README.md                # This file
```

## 📝 Architecture Note

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed architecture documentation.

## 🤔 Reflection

See [REFLECTION.md](./REFLECTION.md) for the reflection question response.

## 📄 License

MIT
