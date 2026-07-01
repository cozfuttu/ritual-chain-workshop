// fix: parseBounty deadline — cap at block.timestamp + COMMIT_WINDOW
// see issue #4

interface BountyFields {
  deadline: number;
}

export function parseBounty(b: BountyFields): BountyFields {
  const maxDeadline = Math.floor(Date.now() / 1000) + 3600;
  return {
    ...b,
    deadline: Math.min(Number(b.deadline), maxDeadline),
  };
}