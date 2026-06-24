# 🏗️ Architecture Note

## Privacy-Preserving AI Bounty Judge

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │   Frontend   │    │   Contract   │    │   Ritual     │     │
│  │   (DApp)     │◄──►│   (On-Chain) │◄──►│   LLM        │     │
│  │              │    │              │    │   (0x0802)   │     │
│  └──────────────┘    └──────────────┘    └──────────────┘     │
│         │                   │                   │              │
│         │                   │                   │              │
│         ▼                   ▼                   ▼              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │  MetaMask    │    │  Ritual      │    │  TEE Node    │     │
│  │  Wallet      │    │  Chain       │    │  Network     │     │
│  │              │    │  Testnet     │    │              │     │
│  └──────────────┘    └──────────────┘    └──────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Phase 1: COMMITMENT
───────────────────
User → Frontend → Contract
  │
  ├─ Input: answer, salt
  ├─ Compute: keccak256(answer, salt, sender, bountyId)
  └─ Store: commitment hash only (answer HIDDEN)

Phase 2: REVEAL
───────────────
User → Frontend → Contract
  │
  ├─ Input: answer, salt
  ├─ Verify: keccak256(answer, salt, sender, bountyId) == commitment
  ├─ Store: revealed answer (plaintext)
  └─ Status: revealed = true

Phase 3: AI JUDGING
───────────────────
Admin → Contract → Ritual LLM Precompile
  │
  ├─ For each revealed answer:
  │   ├─ Build prompt: llmInput + participant + answer
  │   ├─ Call precompile 0x0802
  │   ├─ Parse score (0-100)
  │   └─ Store score on-chain
  └─ Total judged count

Phase 4: FINALIZATION
─────────────────────
Admin → Contract → Winner
  │
  ├─ Find highest score
  ├─ Rank participants
  ├─ Transfer prize pool
  └─ Emit WinnerFinalized event
```

### On-Chain vs Off-Chain

| Data | Location | Visibility |
|------|----------|------------|
| Commitment hash | On-chain | Public (but hides answer) |
| Revealed answer | On-chain | Public (after reveal phase) |
| AI scores | On-chain | Public |
| Prize pool | On-chain | Public |
| Salt | Off-chain | Private (user only) |
| AI prompt | Off-chain | Private (admin only) |

### Security Considerations

1. **Front-Running Prevention**
   - Commitment hash hides answer
   - Cannot copy before reveal phase

2. **Replay Attack Prevention**
   - Salt + sender + bountyId in hash
   - Each commitment is unique

3. **Timing Attack Prevention**
   - Strict phase transitions
   - Cannot reveal before deadline

4. **AI Manipulation Prevention**
   - Batch judging (not per-answer)
   - Admin cannot influence scores

### Ritual Chain Integration

**Precompile 0x0802 (AI Inference):**
```
Input: Prompt (bytes)
Output: Inference result (bytes)

Flow:
1. Contract encodes prompt with answer
2. Calls precompile 0x0802
3. TEE node processes inference
4. Returns score (0-100)
5. Contract stores score on-chain
```

**Benefits:**
- Decentralized AI judging (no single point of failure)
- Verifiable inference (TEE attestation)
- Low cost (~0.0001 RITUAL per call)
- On-chain audit trail

### Scalability

**Current Implementation:**
- Single contract handles multiple bounties
- Sequential judging (one bounty at a time)
- Gas limit: ~30M per transaction

**Future Improvements:**
- Parallel judging across bounties
- Layer 2 integration for cheaper storage
- IPFS for large answer storage
- Multi-model AI judging (consensus)
