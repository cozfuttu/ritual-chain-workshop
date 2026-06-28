import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodePacked, getAddress, keccak256, parseEther, toBytes } from "viem";

describe("AIJudge", async function () {
  const { viem } = await network.create();
  const publicClient = await viem.getPublicClient();

  async function latestTimestamp() {
    const block = await publicClient.getBlock();
    return block.timestamp;
  }

  async function increaseTo(timestamp: bigint) {
    await publicClient.request({
      method: "evm_setNextBlockTimestamp",
      params: [Number(timestamp)],
    });
    await publicClient.request({
      method: "evm_mine",
      params: [],
    });
  }

  function makeCommitment(
    answer: string,
    salt: `0x${string}`,
    submitter: `0x${string}`,
    bountyId: bigint,
  ) {
    return keccak256(
      encodePacked(
        ["string", "bytes32", "address", "uint256"],
        [answer, salt, submitter, bountyId],
      ),
    );
  }

  async function deployBounty() {
    const [owner, participant, otherParticipant] = await viem.getWalletClients();
    const now = await latestTimestamp();
    const submissionDeadline = now + 100n;
    const revealDeadline = now + 200n;

    const aiJudge = await viem.deployContract("AIJudge");
    await aiJudge.write.createBounty(
      ["Test bounty", "Pick the best answer", submissionDeadline, revealDeadline],
      { value: parseEther("1") },
    );

    const participantJudge = await viem.getContractAt(
      "AIJudge",
      aiJudge.address,
      { client: { wallet: participant } },
    );
    const otherParticipantJudge = await viem.getContractAt(
      "AIJudge",
      aiJudge.address,
      { client: { wallet: otherParticipant } },
    );

    return {
      aiJudge,
      participantJudge,
      otherParticipantJudge,
      owner,
      participant,
      otherParticipant,
      submissionDeadline,
      revealDeadline,
    };
  }

  it("stores commitments without plaintext answers and reveals a valid answer", async function () {
    const { aiJudge, participantJudge, participant, submissionDeadline } =
      await deployBounty();
    const answer = "Run inference against each answer and compare to rubric.";
    const salt = keccak256(toBytes("participant salt"));
    const commitment = makeCommitment(
      answer,
      salt,
      participant.account.address,
      1n,
    );

    await participantJudge.write.submitCommitment([1n, commitment]);

    let submission = await aiJudge.read.getSubmission([1n, 0n]);
    assert.equal(submission[0], getAddress(participant.account.address));
    assert.equal(submission[1], commitment);
    assert.equal(submission[2], "");
    assert.equal(submission[3], false);

    await increaseTo(submissionDeadline);
    await participantJudge.write.revealAnswer([1n, answer, salt]);

    submission = await aiJudge.read.getSubmission([1n, 0n]);
    assert.equal(submission[2], answer);
    assert.equal(submission[3], true);

    const bounty = await aiJudge.read.getBounty([1n]);
    assert.equal(bounty.submissionCount, 1n);
    assert.equal(bounty.revealedSubmissionCount, 1n);
    assert.equal(bounty.submissionDeadline, submissionDeadline);
  });

  it("rejects a second commitment from the same participant", async function () {
    const { participantJudge, participant } = await deployBounty();
    const salt = keccak256(toBytes("salt"));
    const commitment = makeCommitment(
      "answer",
      salt,
      participant.account.address,
      1n,
    );

    await participantJudge.write.submitCommitment([1n, commitment]);

    await assert.rejects(
      participantJudge.write.submitCommitment([1n, commitment]),
      /already committed/,
    );
  });

  it("rejects invalid reveals and judgeAll before reveal deadline", async function () {
    const { aiJudge, participantJudge, participant, submissionDeadline } =
      await deployBounty();
    const answer = "correct answer";
    const salt = keccak256(toBytes("salt"));
    const commitment = makeCommitment(
      answer,
      salt,
      participant.account.address,
      1n,
    );

    await participantJudge.write.submitCommitment([1n, commitment]);
    await increaseTo(submissionDeadline);

    await assert.rejects(
      participantJudge.write.revealAnswer([
        1n,
        "wrong answer",
        salt,
      ]),
      /invalid reveal/,
    );

    await assert.rejects(aiJudge.write.judgeAll([1n, "0x"]), /reveal not ended/);
  });

  it("only counts revealed submissions", async function () {
    const {
      aiJudge,
      participantJudge,
      otherParticipantJudge,
      participant,
      otherParticipant,
      submissionDeadline,
    } = await deployBounty();
    const answer = "revealed answer";
    const salt = keccak256(toBytes("salt"));
    const otherSalt = keccak256(toBytes("other salt"));

    await participantJudge.write.submitCommitment([
      1n,
      makeCommitment(answer, salt, participant.account.address, 1n),
    ]);
    await otherParticipantJudge.write.submitCommitment([
      1n,
      makeCommitment(
        "unrevealed answer",
        otherSalt,
        otherParticipant.account.address,
        1n,
      ),
    ]);

    await increaseTo(submissionDeadline);
    await participantJudge.write.revealAnswer([1n, answer, salt]);

    const bounty = await aiJudge.read.getBounty([1n]);
    assert.equal(bounty.submissionCount, 2n);
    assert.equal(bounty.revealedSubmissionCount, 1n);

    const unrevealedSubmission = await aiJudge.read.getSubmission([1n, 1n]);
    assert.equal(unrevealedSubmission[3], false);
  });
});
