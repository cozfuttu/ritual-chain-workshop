"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { encodePacked, isHex, keccak256, type Hex } from "viem";
import { useNow } from "@/hooks/useNow";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import { canRevealAnswer, canSubmitCommitment, type Bounty } from "@/lib/bounty";
import { useWriteTx } from "@/hooks/useWriteTx";
import {
  Card,
  CardHeader,
  CardBody,
  Field,
  Input,
  Textarea,
  Button,
  TxStatus,
  Notice,
} from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

function randomSalt(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

function isBytes32(value: string): value is Hex {
  return isHex(value) && value.length === 66;
}

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
  const [salt, setSalt] = useState<Hex>(randomSalt());
  const now = useNow();
  const nowSeconds = now / 1000;
  const tx = useWriteTx(() => onSubmitted());

  const canCommit = canSubmitCommitment(bounty, nowSeconds);
  const canReveal = canRevealAnswer(bounty, nowSeconds);

  if (!canCommit && !canReveal) return null;

  const saltValid = isBytes32(salt);
  const answerReady = !!answer.trim() && saltValid && !!address && !!contractAddress;

  async function handleSubmitCommitment(e: React.FormEvent) {
    e.preventDefault();
    if (!answerReady || !address || !contractAddress) return;

    const commitment = keccak256(
      encodePacked(
        ["string", "bytes32", "address", "uint256"],
        [answer.trim(), salt, address, bountyId],
      ),
    );

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

  async function handleReveal(e: React.FormEvent) {
    e.preventDefault();
    if (!answerReady || !contractAddress) return;
    try {
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "revealAnswer",
        args: [bountyId, answer.trim(), salt],
        chainId: ritualChain.id,
      });
    } catch {
      /* surfaced via tx.state */
    }
  }

  return (
    <Card>
      <CardHeader
        title={canCommit ? "Submit commitment" : "Reveal answer"}
        subtitle={
          canCommit
            ? "Only a hash is sent on-chain during submission."
            : "Reveal the answer and salt that match your commitment."
        }
      />
      <CardBody>
        <form onSubmit={canCommit ? handleSubmitCommitment : handleReveal} className="space-y-3">
          <Field label="Your answer">
            <Textarea
              value={answer}
              onChange={(e) => setAnswer(e.target.value)}
              rows={5}
              placeholder="Write your submission…"
            />
          </Field>

          <Field label="Salt" hint="Keep this exact bytes32 value for reveal.">
            <div className="flex gap-2">
              <Input
                value={salt}
                onChange={(e) => setSalt(e.target.value as Hex)}
                className="font-mono"
              />
              {canCommit && (
                <Button type="button" onClick={() => setSalt(randomSalt())}>
                  New
                </Button>
              )}
            </div>
          </Field>

          {!saltValid && <Notice tone="amber">Salt must be a 32-byte hex value.</Notice>}

          <Button
            type="submit"
            disabled={!isConnected || !answerReady || tx.isBusy}
            className="w-full"
          >
            {tx.isBusy
              ? canCommit
                ? "Submitting…"
                : "Revealing…"
              : canCommit
                ? "Submit commitment"
                : "Reveal answer"}
          </Button>
          {!isConnected && (
            <p className="text-xs text-zinc-500">
              Connect your wallet to participate.
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
