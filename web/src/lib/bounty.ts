import type { Address } from "viem";

/** Parsed shape of the `getBounty` tuple return value. */
export type Bounty = {
  owner: Address;
  title: string;
  rubric: string;
  reward: bigint;
  submissionDeadline: bigint;
  revealDeadline: bigint;
  judged: boolean;
  finalized: boolean;
  commitmentCount: bigint;
  revealedCount: bigint;
  winnerIndex: bigint;
  aiReview: `0x${string}`;
};

/** getBounty returns a positional tuple — map it to a named object. */
export function parseBounty(
  raw: Bounty | readonly unknown[],
): Bounty {
  if (!Array.isArray(raw)) return raw as Bounty;
  const [
    owner,
    title,
    rubric,
    reward,
    submissionDeadline,
    revealDeadline,
    judged,
    finalized,
    commitmentCount,
    revealedCount,
    winnerIndex,
    aiReview,
  ] = raw as [
    Address,
    string,
    string,
    bigint,
    bigint,
    bigint,
    boolean,
    boolean,
    bigint,
    bigint,
    bigint,
    `0x${string}`,
  ];
  return {
    owner,
    title,
    rubric,
    reward,
    submissionDeadline,
    revealDeadline,
    judged,
    finalized,
    commitmentCount,
    revealedCount,
    winnerIndex,
    aiReview,
  };
}

export type BountyStatus = "submit" | "reveal" | "ready" | "judged" | "finalized";

function deadlineNow(deadline: bigint, nowSeconds: number): number {
  return deadline > 10_000_000_000n ? nowSeconds * 1000 : nowSeconds;
}

export function getBountyStatus(b: Bounty, nowSeconds = Date.now() / 1000): BountyStatus {
  if (b.finalized) return "finalized";
  if (b.judged) return "judged";
  if (Number(b.submissionDeadline) > deadlineNow(b.submissionDeadline, nowSeconds)) return "submit";
  if (Number(b.revealDeadline) > deadlineNow(b.revealDeadline, nowSeconds)) return "reveal";
  return "ready";
}

export const STATUS_META: Record<
  BountyStatus,
  { label: string; tone: "green" | "amber" | "indigo" | "zinc" }
> = {
  submit: { label: "Submit commitments", tone: "green" },
  reveal: { label: "Reveal answers", tone: "amber" },
  ready: { label: "Ready for judging", tone: "amber" },
  judged: { label: "Judged", tone: "indigo" },
  finalized: { label: "Finalized", tone: "zinc" },
};

export function canSubmitCommitment(b: Bounty, nowSeconds = Date.now() / 1000): boolean {
  return (
    !b.judged &&
    !b.finalized &&
    Number(b.submissionDeadline) > deadlineNow(b.submissionDeadline, nowSeconds)
  );
}

export function canRevealAnswer(b: Bounty, nowSeconds = Date.now() / 1000): boolean {
  const submissionNow = deadlineNow(b.submissionDeadline, nowSeconds);
  const revealNow = deadlineNow(b.revealDeadline, nowSeconds);
  return (
    !b.judged &&
    !b.finalized &&
    Number(b.submissionDeadline) <= submissionNow &&
    Number(b.revealDeadline) > revealNow
  );
}
