"use client";

import { useReadContract } from "wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import { shortenAddress } from "@/lib/format";
import type { JudgeResult } from "@/lib/aiReview";
import { Card, CardHeader, CardBody, Badge } from "@/components/ui";

export function SubmissionsList({
  bountyId,
  count,
  judge,
  finalWinner,
}: {
  bountyId: bigint;
  count: number;
  judge?: JudgeResult | null;
  finalWinner?: number;
}) {
  const indices = Array.from({ length: count }, (_, i) => i);

  return (
    <Card>
      <CardHeader
        title="Submissions"
        subtitle="Commitments stay hidden until participants reveal after the deadline."
        action={<Badge tone="zinc">{count}</Badge>}
      />
      <CardBody className="space-y-3">
        {count === 0 ? (
          <p className="text-sm text-zinc-500">No submissions yet.</p>
        ) : (
          indices.map((i) => (
            <SubmissionRow
              key={i}
              bountyId={bountyId}
              index={i}
              ranking={judge?.ranking?.find((r) => r.index === i)}
              recommended={judge?.winnerIndex === i}
              isWinner={finalWinner === i}
            />
          ))
        )}
      </CardBody>
    </Card>
  );
}

function SubmissionRow({
  bountyId,
  index,
  ranking,
  recommended,
  isWinner,
}: {
  bountyId: bigint;
  index: number;
  ranking?: { index: number; score: number; reason: string };
  recommended?: boolean;
  isWinner?: boolean;
}) {
  const { data, isLoading } = useReadContract({
    address: contractAddress,
    abi: aiJudgeAbi,
    functionName: "getSubmission",
    args: [bountyId, BigInt(index)],
    chainId: ritualChain.id,
    query: { enabled: !!contractAddress },
  });

  const submitter = data?.[0];
  const commitment = data?.[1];
  const answer = data?.[2];
  const revealed = data?.[3];

  return (
    <div
      className={`rounded-xl border p-3 ${
        isWinner
          ? "border-emerald-500/40 bg-emerald-500/5"
          : recommended
            ? "border-indigo-500/40 bg-indigo-500/5"
            : "border-white/10 bg-black/20"
      }`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="font-mono text-xs text-zinc-500">#{index}</span>
          <span className="font-mono text-sm text-zinc-300">
            {submitter ? shortenAddress(submitter) : isLoading ? "loading…" : "-"}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          {revealed === false ? <Badge tone="amber">Committed</Badge> : null}
          {revealed ? <Badge tone="green">Revealed</Badge> : null}
          {ranking ? <Badge tone="zinc">score {ranking.score}</Badge> : null}
          {isWinner ? (
            <Badge tone="green">Winner</Badge>
          ) : recommended ? (
            <Badge tone="indigo">AI pick</Badge>
          ) : null}
        </div>
      </div>

      <p className="mt-2 whitespace-pre-wrap break-words text-sm text-zinc-200">
        {revealed
          ? answer || "-"
          : commitment
            ? `Hidden commitment: ${commitment}`
            : isLoading
              ? ""
              : "-"}
      </p>

      {ranking?.reason ? (
        <p className="mt-2 border-t border-white/5 pt-2 text-xs text-zinc-400">
          <span className="text-zinc-500">AI: </span>
          {ranking.reason}
        </p>
      ) : null}
    </div>
  );
}
