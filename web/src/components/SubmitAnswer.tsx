"use client";

import { useEffect, useState } from "react";
import { bytesToHex } from "viem";
import type { Hex } from "viem";
import { useAccount, usePublicClient } from "wagmi";
import { useNow } from "@/hooks/useNow";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import { canCommit, canReveal, type Bounty } from "@/lib/bounty";
import { useWriteTx } from "@/hooks/useWriteTx";
import {
  Card,
  CardHeader,
  CardBody,
  Field,
  Textarea,
  Button,
  TxStatus,
  Notice,
} from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

type SavedReveal = {
  answer: string;
  salt: Hex;
  commitment: Hex;
};

function storageKey(bountyId: bigint, address?: string) {
  return `ai-judge-reveal:${contractAddress}:${bountyId.toString()}:${address?.toLowerCase() ?? "unknown"}`;
}

function randomSalt(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
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
  const publicClient = usePublicClient({ chainId: ritualChain.id });
  const [answer, setAnswer] = useState("");
  const [manualSalt, setManualSalt] = useState<Hex | "">("");
  const [savedReveal, setSavedReveal] = useState<SavedReveal | null>(null);
  const now = useNow();
  const commitTx = useWriteTx(() => onSubmitted());
  const revealTx = useWriteTx(() => onSubmitted());

  const key = storageKey(bountyId, address);

  useEffect(() => {
    if (!address) {
      setSavedReveal(null);
      return;
    }
    try {
      const raw = localStorage.getItem(key);
      setSavedReveal(raw ? (JSON.parse(raw) as SavedReveal) : null);
    } catch {
      setSavedReveal(null);
    }
  }, [address, key]);

  const commitOpen = canCommit(bounty, now / 1000);
  const revealOpen = canReveal(bounty, now / 1000);

  if (!commitOpen && !revealOpen) return null;

  async function handleCommit(e: React.FormEvent) {
    e.preventDefault();
    if (!answer.trim() || !contractAddress || !publicClient || !address) return;

    const trimmed = answer.trim();
    const salt = randomSalt();
    const commitment = await publicClient.readContract({
      address: contractAddress,
      abi: aiJudgeAbi,
      functionName: "computeCommitment",
      args: [trimmed, salt, address, bountyId],
    });

    try {
      await commitTx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "submitCommitment",
        args: [bountyId, commitment],
        chainId: ritualChain.id,
      });
      const reveal = { answer: trimmed, salt, commitment } satisfies SavedReveal;
      localStorage.setItem(key, JSON.stringify(reveal));
      setSavedReveal(reveal);
      setAnswer("");
    } catch {
      /* surfaced via tx.state */
    }
  }

  async function handleReveal(e: React.FormEvent) {
    e.preventDefault();
    if (!contractAddress) return;

    const revealAnswer = savedReveal?.answer || answer.trim();
    const revealSalt = savedReveal?.salt || manualSalt;
    if (!revealAnswer || !revealSalt) return;

    try {
      await revealTx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "revealAnswer",
        args: [bountyId, revealAnswer, revealSalt],
        chainId: ritualChain.id,
      });
      localStorage.removeItem(key);
      setSavedReveal(null);
      setAnswer("");
      setManualSalt("");
    } catch {
      /* surfaced via tx.state */
    }
  }

  if (commitOpen) {
    return (
      <Card>
        <CardHeader
          title="Commit hidden answer"
          subtitle="Your answer is hashed now and revealed only after the deadline. Save your browser data or copy the salt."
        />
        <CardBody>
          <form onSubmit={handleCommit} className="space-y-3">
            <Field label="Your answer">
              <Textarea
                value={answer}
                onChange={(e) => setAnswer(e.target.value)}
                rows={5}
                placeholder="Write your submission…"
              />
            </Field>
            <Button
              type="submit"
              disabled={!isConnected || !answer.trim() || commitTx.isBusy}
              className="w-full"
            >
              {commitTx.isBusy ? "Submitting commitment…" : "Submit commitment"}
            </Button>
            {!isConnected && (
              <p className="text-xs text-zinc-500">Connect your wallet to submit.</p>
            )}
            {savedReveal ? (
              <Notice tone="amber">
                Commitment saved locally. After the deadline, return with this browser/wallet to reveal.
              </Notice>
            ) : null}
            <TxStatus
              state={commitTx.state}
              error={commitTx.error}
              hash={commitTx.hash}
              explorerBase={explorerBase}
            />
          </form>
        </CardBody>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader
        title="Reveal committed answer"
        subtitle="Reveal your answer and salt after the deadline so it becomes eligible for AI judging."
      />
      <CardBody>
        <form onSubmit={handleReveal} className="space-y-3">
          {savedReveal ? (
            <Notice tone="green">
              Found your saved answer and salt in this browser. You can reveal now.
            </Notice>
          ) : (
            <>
              <Field label="Your original answer">
                <Textarea
                  value={answer}
                  onChange={(e) => setAnswer(e.target.value)}
                  rows={5}
                  placeholder="Paste the exact answer you committed…"
                />
              </Field>
              <Field label="Salt">
                <input
                  value={manualSalt}
                  onChange={(e) => setManualSalt(e.target.value as Hex)}
                  className="w-full rounded-xl border border-white/10 bg-black/30 px-3 py-2 font-mono text-sm text-zinc-100 outline-none focus:border-indigo-500"
                  placeholder="0x…"
                />
              </Field>
            </>
          )}
          <Button
            type="submit"
            disabled={
              !isConnected ||
              revealTx.isBusy ||
              !(savedReveal || (answer.trim() && manualSalt))
            }
            className="w-full"
          >
            {revealTx.isBusy ? "Revealing…" : "Reveal answer"}
          </Button>
          <TxStatus
            state={revealTx.state}
            error={revealTx.error}
            hash={revealTx.hash}
            explorerBase={explorerBase}
          />
        </form>
      </CardBody>
    </Card>
  );
}
