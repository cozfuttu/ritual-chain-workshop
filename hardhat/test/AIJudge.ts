import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import {
  encodePacked,
  formatEther,
  keccak256,
  parseEther,
  stringToHex,
  type Address,
  type Hex,
} from "viem";

describe("AIJudge commit-reveal bounty flow", async function () {
  const { viem, networkHelpers } = await network.create();
  const publicClient = await viem.getPublicClient();
  const [owner, alice, bob, carol] = await viem.getWalletClients();

  const reward = parseEther("1");

  function commitment(
    answer: string,
    salt: Hex,
    submitter: Address,
    bountyId = 1n,
  ): Hex {
    return keccak256(
      encodePacked(
        ["string", "bytes32", "address", "uint256"],
        [answer, salt, submitter, bountyId],
      ),
    );
  }

  async function deployBounty(offsets = { submit: 1000n, reveal: 2000n }) {
    const contract = await viem.deployContract("MockAIJudge");
    const now = BigInt(await networkHelpers.time.latest());
    const submissionDeadline = now + offsets.submit;
    const revealDeadline = now + offsets.reveal;

    await contract.write.createBounty(
      ["Private AI Judge", "Pick the clearest correct answer", submissionDeadline, revealDeadline],
      { account: owner.account, value: reward },
    );

    return { contract, submissionDeadline, revealDeadline };
  }

  async function assertRejectsWith(promise: Promise<unknown>, reason: string) {
    await assert.rejects(promise, (error: unknown) => {
      const message =
        (error as { shortMessage?: string; message?: string }).shortMessage ??
        (error as Error).message;
      assert.match(message, new RegExp(reason));
      return true;
    });
  }

  it("accepts a valid commitment before the submission deadline", async function () {
    const { contract } = await deployBounty();
    const salt = stringToHex("salt-1", { size: 32 });
    const hash = commitment("answer", salt, alice.account.address);

    await contract.write.submitCommitment([1n, hash], { account: alice.account });

    const record = await contract.read.getCommitment([1n, alice.account.address]);
    const bounty = await contract.read.getBounty([1n]);

    assert.equal(record[0], hash);
    assert.equal(record[1], true);
    assert.equal(record[2], false);
    assert.equal(bounty.commitmentCount, 1n);
    assert.equal(bounty.revealedCount, 0n);
  });

  it("rejects commitment submission after the submission deadline", async function () {
    const { contract, submissionDeadline } = await deployBounty();
    await networkHelpers.time.increaseTo(submissionDeadline);

    const salt = stringToHex("late", { size: 32 });
    await assertRejectsWith(
      contract.write.submitCommitment(
        [1n, commitment("late answer", salt, alice.account.address)],
        { account: alice.account },
      ),
      "submissions closed",
    );
  });

  it("rejects duplicate commitments from the same participant", async function () {
    const { contract } = await deployBounty();
    const salt = stringToHex("dup", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment("first", salt, alice.account.address)],
      { account: alice.account },
    );

    await assertRejectsWith(
      contract.write.submitCommitment(
        [1n, commitment("second", salt, alice.account.address)],
        { account: alice.account },
      ),
      "commitment exists",
    );
  });

  it("accepts a valid reveal with the original answer and salt", async function () {
    const { contract, submissionDeadline } = await deployBounty();
    const answer = "ship a commit-reveal judge";
    const salt = stringToHex("reveal", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);

    await contract.write.revealAnswer([1n, answer, salt], { account: alice.account });

    const submission = await contract.read.getSubmission([1n, 0n]);
    const record = await contract.read.getCommitment([1n, alice.account.address]);

    assert.equal(submission[0].toLowerCase(), alice.account.address.toLowerCase());
    assert.equal(submission[1], answer);
    assert.equal(record[2], true);
  });

  it("rejects reveal before the submission deadline", async function () {
    const { contract } = await deployBounty();
    const answer = "too early";
    const salt = stringToHex("early", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );

    await assertRejectsWith(
      contract.write.revealAnswer([1n, answer, salt], { account: alice.account }),
      "reveal not open",
    );
  });

  it("rejects reveal after the reveal deadline", async function () {
    const { contract, revealDeadline } = await deployBounty();
    const answer = "too late";
    const salt = stringToHex("late-reveal", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(revealDeadline);

    await assertRejectsWith(
      contract.write.revealAnswer([1n, answer, salt], { account: alice.account }),
      "reveal closed",
    );
  });

  it("rejects reveal with a wrong answer or salt", async function () {
    const { contract, submissionDeadline } = await deployBounty();
    const answer = "correct answer";
    const salt = stringToHex("right-salt", { size: 32 });
    const wrongSalt = stringToHex("wrong-salt", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);

    await assertRejectsWith(
      contract.write.revealAnswer([1n, "wrong answer", salt], {
        account: alice.account,
      }),
      "invalid reveal",
    );
    await assertRejectsWith(
      contract.write.revealAnswer([1n, answer, wrongSalt], {
        account: alice.account,
      }),
      "invalid reveal",
    );
  });

  it("excludes unrevealed commitments from judging", async function () {
    const { contract, submissionDeadline, revealDeadline } = await deployBounty();
    const aliceAnswer = "revealed answer";
    const bobAnswer = "unrevealed answer";
    const aliceSalt = stringToHex("alice", { size: 32 });
    const bobSalt = stringToHex("bob", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(aliceAnswer, aliceSalt, alice.account.address)],
      { account: alice.account },
    );
    await contract.write.submitCommitment(
      [1n, commitment(bobAnswer, bobSalt, bob.account.address)],
      { account: bob.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);
    await contract.write.revealAnswer([1n, aliceAnswer, aliceSalt], {
      account: alice.account,
    });
    await networkHelpers.time.increaseTo(revealDeadline);

    const bountyBeforeJudge = await contract.read.getBounty([1n]);
    assert.equal(bountyBeforeJudge.commitmentCount, 2n);
    assert.equal(bountyBeforeJudge.revealedCount, 1n);

    await contract.write.judgeAll([1n, "0x"], { account: owner.account });

    const submission = await contract.read.getSubmission([1n, 0n]);
    await assertRejectsWith(contract.read.getSubmission([1n, 1n]), "invalid index");
    assert.equal(submission[0].toLowerCase(), alice.account.address.toLowerCase());
  });

  it("allows judgeAll only after the reveal deadline and requires at least one reveal", async function () {
    const { contract, submissionDeadline, revealDeadline } = await deployBounty();
    const answer = "judge me";
    const salt = stringToHex("judge", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);
    await contract.write.revealAnswer([1n, answer, salt], { account: alice.account });

    await assertRejectsWith(
      contract.write.judgeAll([1n, "0x"], { account: owner.account }),
      "reveal not closed",
    );

    await networkHelpers.time.increaseTo(revealDeadline);
    await contract.write.judgeAll([1n, "0x"], { account: owner.account });

    const judged = await contract.read.getBounty([1n]);
    assert.equal(judged.judged, true);
    assert.equal(judged.aiReview, stringToHex('{"winnerIndex":0,"summary":"mock"}'));
  });

  it("rejects judgeAll when there are no valid revealed submissions", async function () {
    const { contract, revealDeadline } = await deployBounty();
    await networkHelpers.time.increaseTo(revealDeadline);

    await assertRejectsWith(
      contract.write.judgeAll([1n, "0x"], { account: owner.account }),
      "no revealed submissions",
    );
  });

  it("allows finalizeWinner only after judging is complete", async function () {
    const { contract, submissionDeadline } = await deployBounty();
    const answer = "finalist";
    const salt = stringToHex("finalist", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);
    await contract.write.revealAnswer([1n, answer, salt], { account: alice.account });

    await assertRejectsWith(
      contract.write.finalizeWinner([1n, 0n], { account: owner.account }),
      "not judged yet",
    );
  });

  it("rejects invalid winner indexes", async function () {
    const { contract, submissionDeadline, revealDeadline } = await deployBounty();
    const answer = "only revealed answer";
    const salt = stringToHex("only", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(answer, salt, alice.account.address)],
      { account: alice.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);
    await contract.write.revealAnswer([1n, answer, salt], { account: alice.account });
    await networkHelpers.time.increaseTo(revealDeadline);
    await contract.write.judgeAll([1n, "0x"], { account: owner.account });

    await assertRejectsWith(
      contract.write.finalizeWinner([1n, 1n], { account: owner.account }),
      "invalid winner",
    );
  });

  it("pays the reward only once to the finalized winner", async function () {
    const { contract, submissionDeadline, revealDeadline } = await deployBounty();
    const aliceAnswer = "alice answer";
    const carolAnswer = "carol answer";
    const aliceSalt = stringToHex("alice-pay", { size: 32 });
    const carolSalt = stringToHex("carol-pay", { size: 32 });

    await contract.write.submitCommitment(
      [1n, commitment(aliceAnswer, aliceSalt, alice.account.address)],
      { account: alice.account },
    );
    await contract.write.submitCommitment(
      [1n, commitment(carolAnswer, carolSalt, carol.account.address)],
      { account: carol.account },
    );
    await networkHelpers.time.increaseTo(submissionDeadline);
    await contract.write.revealAnswer([1n, aliceAnswer, aliceSalt], {
      account: alice.account,
    });
    await contract.write.revealAnswer([1n, carolAnswer, carolSalt], {
      account: carol.account,
    });
    await networkHelpers.time.increaseTo(revealDeadline);
    await contract.write.judgeAll([1n, "0x"], { account: owner.account });

    const before = await publicClient.getBalance({ address: carol.account.address });
    await contract.write.finalizeWinner([1n, 1n], { account: owner.account });
    const after = await publicClient.getBalance({ address: carol.account.address });

    assert.equal(after - before, reward, `paid ${formatEther(after - before)} ETH`);

    const bounty = await contract.read.getBounty([1n]);
    assert.equal(bounty.finalized, true);
    assert.equal(bounty.reward, 0n);
    assert.equal(bounty.winnerIndex, 1n);

    await assertRejectsWith(
      contract.write.finalizeWinner([1n, 0n], { account: owner.account }),
      "already finalized",
    );
  });
});
