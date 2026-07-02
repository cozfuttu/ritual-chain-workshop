# Privacy-Preserving AI Bounty Judge

This repository extends the Ritual AI Bounty Judge workshop with a
commit-reveal bounty flow. Participants no longer publish plaintext answers
during the submission phase, so later participants cannot copy earlier work
before the deadline.

The required Solidity track is implemented in `hardhat/contracts/AIJudge.sol`.
It works on any EVM chain for the commit-reveal lifecycle, and uses Ritual's
LLM inference precompile for the optional on-chain AI judging step when
deployed on Ritual Chain.

## Why this matters

The original workshop contract accepted public plaintext answers immediately.
That is simple, but unfair: the first honest participant reveals their solution
to everyone, and later participants can copy, lightly edit, or strategically
wait for better answers. Commit-reveal fixes the submission-phase leak by
storing only a hash until submissions close.

## Bounty lifecycle

1. The owner creates a bounty with a reward, a submission deadline, and a
   reveal deadline.
2. During the submission phase, participants submit only a commitment hash with
   `submitCommitment(bountyId, commitment)`.
3. During the reveal phase, participants reveal the original `answer` and
   `salt` with `revealAnswer(bountyId, answer, salt)`.
4. The contract recomputes the commitment as:

   ```solidity
   bytes32 commitment = keccak256(
       abi.encodePacked(answer, salt, msg.sender, bountyId)
   );
   ```

5. Only valid revealed answers are stored in the judged submissions array.
   Unrevealed commitments are ignored.
6. After the reveal deadline, the owner calls
   `judgeAll(bountyId, llmInput)`.
7. `judgeAll` sends one batched Ritual LLM request for all revealed answers.
   It does not call the LLM once per submission.
8. The owner reviews the AI output and finalizes exactly one winner with
   `finalizeWinner(bountyId, winnerIndex)`.
9. The contract pays the full reward once, using checks-effects-interactions.

AI output is advisory. The contract never pays directly from raw model output;
the owner must choose a valid revealed-submission index.

## Generating a commitment

Use the exact Solidity packing order and include the participant address and
`bountyId` so another wallet cannot reuse the same answer and salt.

```ts
import { encodePacked, keccak256 } from "viem";

const commitment = keccak256(
  encodePacked(
    ["string", "bytes32", "address", "uint256"],
    [answer, salt, participantAddress, bountyId],
  ),
);
```

The `salt` should be a random `bytes32` value kept private until reveal.

## Participant flow

Submit phase:

```solidity
submitCommitment(bountyId, commitment);
```

Reveal phase:

```solidity
revealAnswer(bountyId, answer, salt);
```

If the answer or salt differs from the committed values, or if a different
wallet reveals, the contract rejects the reveal.

## AI judging

`judgeAll(uint256 bountyId, bytes calldata llmInput)` is owner-only and can run
only after the reveal deadline. The frontend or caller builds one prompt that
contains the bounty title, rubric, and every valid revealed answer, then
ABI-encodes the Ritual LLM request as `llmInput`.

Ritual documentation describes LLM inference as precompile `0x0802`; contracts
forward pre-encoded request bytes, and the response format decodes to
`(bool hasError, bytes completionData, bytes modelMetadata, string errorMessage, ConvoHistory updatedConvoHistory)`.
Ritual's docs also describe this as TEE-backed delegated execution, with short
precompile results available to the calling transaction and one SPC call per
transaction.

## Finalization and payout

After `judgeAll` succeeds, the owner calls:

```solidity
finalizeWinner(bountyId, winnerIndex);
```

`winnerIndex` must refer to a valid revealed submission. The contract marks the
bounty finalized, zeroes the reward, and then transfers the reward to that one
winner. A second finalization or payout reverts.

## Tests

The Hardhat test suite covers:

- valid commitment submission
- rejection after the submission deadline
- duplicate commitment rejection
- valid reveal with correct answer and salt
- reveal rejection before submission close
- reveal rejection after reveal close
- reveal rejection with wrong answer or salt
- unrevealed commitments excluded from judging
- `judgeAll()` only after reveal deadline
- `judgeAll()` rejection when there are no revealed submissions
- `finalizeWinner()` only after judging
- invalid winner index rejection
- reward paid only once

Run:

```bash
cd hardhat
npm install
npx hardhat test
```

The local tests deploy `contracts/test/MockAIJudge.sol`, which overrides the
Ritual precompile call and returns a mock LLM response. The production contract
still calls Ritual's LLM precompile through `PrecompileConsumer`.

## Deploy

Deploy with Hardhat Ignition:

```bash
cd hardhat
npm install
npx hardhat ignition deploy ignition/modules/AIJudge.ts --network ritual
```

The `ritual` network is configured with chain ID `1979` and RPC
`https://rpc.ritualfoundation.org`. Set `DEPLOYER_PRIVATE_KEY` before deploying
to Ritual Chain. For other EVM chains, the commit-reveal functions still work,
but `judgeAll()` requires either Ritual Chain's LLM precompile or a chain-local
replacement.

## Assumptions and limitations

- Answers are hidden only until reveal in the required EVM commit-reveal track.
- Revealed plaintext answers are stored on-chain and are public.
- The contract caps commitments at `MAX_SUBMISSIONS` to keep batched judging and
  on-chain storage bounded.
- `llmInput` is built off-chain so the contract does not construct large prompts
  or loop over LLM calls.
- The owner is trusted to validate the AI review and choose a valid winner.

## Architecture note

### A. Required commit-reveal design

Commitments are public on-chain hashes. Plaintext answers stay hidden during the
submission phase because only the hash is submitted. Answers become public
during the reveal phase, and only valid reveals are eligible for judging. This
works on any EVM chain because it depends only on `keccak256`, deadlines, and
ordinary Solidity storage.

Plaintext exists in the participant's local environment before reveal, then
exists publicly on-chain after reveal. The on-chain state contains bounty
metadata, commitments, revealed answers, judging status, AI review bytes, and
the final winner.

### B. Advanced Ritual-native encrypted submissions

Participants would encrypt answers for a Ritual TEE/private execution flow
instead of revealing plaintext directly on-chain. The contract would store
encrypted submissions or references to encrypted submissions during the
submission phase. During `judgeAll()`, a TEE-backed workflow would decrypt all
eligible answers privately and send them to the LLM in one batch.

In that design, plaintext exists on the participant's machine and inside the
attested TEE during judging, but not in public mempool calldata or normal
contract storage before judging. On-chain state should store encrypted
submission references, judging status, the final winner, plus
`revealedAnswersRef` and `revealedAnswersHash` instead of large plaintext answer
arrays. The final revealed-answer bundle can live off-chain; users verify it by
hashing the bundle and comparing it with `revealedAnswersHash`. The system can
either reveal all answers together after judging or publish only a verified
off-chain bundle, depending on the bounty rules.

## Reflection

Bounty metadata, deadlines, reward amount, commitments, judging status, and the
final winner should be public so participants can verify the process. Plaintext
answers should stay hidden during submission because early disclosure creates an
unfair copying advantage. In the advanced Ritual-native design, plaintext should
also stay hidden until private judging is complete. AI should score and rank
submissions against the rubric because it can apply the same evaluation prompt
to the full batch. A human bounty owner should finalize the payout because model
output can be malformed, manipulated, or wrong. The contract should enforce
objective rules like deadlines, reveal validity, winner index validity, and
single payout. The overall design should make the process auditable without
exposing private answers too early.
