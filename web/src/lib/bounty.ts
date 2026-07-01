// parseBounty fix: cap deadline at block.timestamp + COMMIT_WINDOW
// see issue #4
export const COMMIT_WINDOW = 3600; // 1h

export function parseBounty(
  raw: readonly [
    Address, string, string, bigint, bigint,
    boolean, boolean, bigint, bigint, `0x${string}`,
  ],
): Bounty {
  const [owner, title, rubric, reward, deadline, judged, finalized, submissionCount, winnerIndex, aiReview] = raw;
  const cappedDeadline = BigInt(Math.min(Number(deadline), Math.floor(Date.now() / 1000) + COMMIT_WINDOW));
  return { owner, title, rubric, reward, deadline: cappedDeadline, judged, finalized, submissionCount, winnerIndex, aiReview };
}