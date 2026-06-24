"use client";

import { useState } from "react";
import { useAccount, usePublicClient } from "wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress, executorAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import type { Bounty } from "@/lib/bounty";
import { buildJudgeAllLlmInput, type JudgeSubmission } from "@/lib/ritualLlm";
import { useWriteTx } from "@/hooks/useWriteTx";
import { useRitualWalletStatus } from "@/hooks/useRitualWalletStatus";
import { RitualWalletPanel } from "@/components/RitualWalletPanel";
import { Card, CardHeader, CardBody, Button, TxStatus, Notice, Spinner } from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export function JudgeAll({
  bountyId,
  bounty,
  isOwner,
  onJudged,
}: {
  bountyId: bigint;
  bounty: Bounty;
  isOwner: boolean;
  onJudged: () => void;
}) {
  const { address } = useAccount();
  const publicClient = usePublicClient({ chainId: ritualChain.id });
  const [gathering, setGathering] = useState(false);
  const [gatherError, setGatherError] = useState<string | null>(null);
  const tx = useWriteTx(() => onJudged());

  // Preflight the *connected* wallet's RitualWallet funding (not the bounty
  // contract) — judgeAll spends prepaid+locked RITUAL via the LLM precompile.
  const walletStatus = useRitualWalletStatus(address);

  const count = Number(bounty.submissionCount);
  const revealedCount = Number(bounty.revealedCount);

  // Gate per spec: owner only, has revealed submissions, not yet judged.
  if (!isOwner || bounty.judged || bounty.finalized || revealedCount === 0) {
    return null;
  }

  async function handleJudge() {
    if (!publicClient || !contractAddress || !walletStatus.ready) return;
    setGatherError(null);
    setGathering(true);
    try {
      // 1–2. Load every revealed submission for this bounty.
      const submissions: JudgeSubmission[] = [];
      for (let i = 0; i < count; i++) {
        const [submitter, , answer, revealed] = await publicClient.readContract({
          address: contractAddress,
          abi: aiJudgeAbi,
          functionName: "getSubmission",
          args: [bountyId, BigInt(i)],
        });
        if (revealed) {
          submissions.push({ index: i, submitter, answer });
        }
      }

      if (submissions.length === 0) {
        throw new Error("No revealed submissions to judge.");
      }

      // 3–4. Build the batch judging prompt and encode the Ritual LLM request.
      const llmInput = buildJudgeAllLlmInput({
        executorAddress,
        title: bounty.title,
        rubric: bounty.rubric,
        submissions,
      });

      setGathering(false);

      // 5. Submit it on-chain.
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "judgeAll",
        args: [bountyId, llmInput],
        chainId: ritualChain.id,
      });
    } catch (e) {
      setGathering(false);
      setGatherError(
        (e as { shortMessage?: string; message?: string }).shortMessage ||
          (e as Error).message ||
          "Failed to gather submissions.",
      );
    }
  }

  const busy = gathering || tx.isBusy;
  const fundingReady = walletStatus.ready === true;

  return (
    <Card>
      <CardHeader
        title="Judge all submissions"
        subtitle="Sends one Ritual LLM request ranking every submission."
      />
      <CardBody className="space-y-3">
        <Notice tone="indigo">AI review is advisory. The bounty owner finalizes the winner.</Notice>

        <RitualWalletPanel status={walletStatus} onDeposited={walletStatus.refetch} />

        <Button onClick={handleJudge} disabled={busy || !fundingReady} className="w-full">
          {gathering ? (
            <>
              <Spinner /> Gathering {revealedCount} revealed submissions…
            </>
          ) : tx.isBusy ? (
            "Judging…"
          ) : !fundingReady ? (
            "Fund RitualWallet to judge"
          ) : (
            `Judge all revealed (${revealedCount})`
          )}
        </Button>
        {gatherError && <Notice tone="red">{gatherError}</Notice>}
        <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
      </CardBody>
    </Card>
  );
}
