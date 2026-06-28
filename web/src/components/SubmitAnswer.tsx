"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { keccak256, encodePacked, toHex } from "viem";
import { useNow } from "@/hooks/useNow";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import { canSubmit, type Bounty } from "@/lib/bounty";
import { useWriteTx } from "@/hooks/useWriteTx";
import {
  Card,
  CardHeader,
  CardBody,
  Field,
  Textarea,
  Button,
  TxStatus,
} from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export function SubmitAnswer({
  bountyId,
  bounty,
  onSubmitted,
}: {
  bountyId: bigint;
  bounty: Bounty;
  onSubmitted: () => void;
}) {
  const { address, isConnected } = useAccount();
  const [answer, setAnswer] = useState("");
  const now = useNow();
  const tx = useWriteTx(() => {
    setAnswer("");
    onSubmitted();
  });

  if (!canSubmit(bounty, now / 1000)) return null;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!answer.trim() || !contractAddress || !address) return;

    // Generate a random salt
    const saltBytes = crypto.getRandomValues(new Uint8Array(32));
    const salt = toHex(saltBytes) as `0x${string}`;

    // Compute commitment hash: keccak256(answer, salt, msg.sender, bountyId)
    const commitment = keccak256(
      encodePacked(
        ["string", "bytes32", "address", "uint256"],
        [answer.trim(), salt, address, bountyId],
      ),
    );

    // Store answer and salt locally so user can reveal later
    const key = `commit:${bountyId}:${address}`;
    localStorage.setItem(key, JSON.stringify({ answer: answer.trim(), salt }));

    try {
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "submitCommitment",
        args: [bountyId, commitment],
        chainId: ritualChain.id,
      });
    } catch {
      /* surfaced via tx.state */
    }
  }

  return (
    <Card>
      <CardHeader
        title="Submit an answer"
        subtitle="Only a commitment hash is sent on-chain. Your answer stays hidden until the reveal phase."
      />
      <CardBody>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Field label="Your answer">
            <Textarea
              value={answer}
              onChange={(e) => setAnswer(e.target.value)}
              rows={5}
              placeholder="Write your submission…"
            />
          </Field>
          <p className="text-xs text-zinc-500">
            Your answer and salt will be saved locally. You will need them to reveal after the submission deadline.
          </p>
          <Button
            type="submit"
            disabled={!isConnected || !answer.trim() || tx.isBusy}
            className="w-full"
          >
            {tx.isBusy ? "Submitting commitment…" : "Submit commitment"}
          </Button>
          {!isConnected && (
            <p className="text-xs text-zinc-500">
              Connect your wallet to submit.
            </p>
          )}
          <TxStatus
            state={tx.state}
            error={tx.error}
            hash={tx.hash}
            explorerBase={explorerBase}
          />
        </form>
      </CardBody>
    </Card>
  );
}
