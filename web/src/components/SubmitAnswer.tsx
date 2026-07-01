// fix #3: use commit-reveal instead of plaintext submit
// generate secret on client, submit hash, reveal after deadline

import { useCallback, useState } from "react";
import { useWriteContract } from "wagmi";
import { AIJUDGE_ADDRESS, abi } from "@/abi";

interface CommitProps {
  bountyId: bigint;
}

export function SubmitAnswer({bountyId}: CommitProps) {
  const [secret, setSecret] = useState<string>("");
  const [answer, setAnswer] = useState<string>("");
  const { writeContract } = useWriteContract();

  const commit = useCallback(async () => {
    const s = crypto.randomUUID();
    setSecret(s);
    const commitment = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s + answer));
    const hex = Array.from(new Uint8Array(commitment)).map(b => b.toString(16).padStart(2,"0")).join("");
    await writeContract({
      address: AIJUDGE_ADDRESS,
      abi,
      functionName: "commitAnswer",
      args: [bountyId, "0x" + hex],
    });
  }, [bountyId, answer]);

  const reveal = useCallback(async () => {
    if (!secret) return;
    await writeContract({
      address: AIJUDGE_ADDRESS,
      abi,
      functionName: "revealAnswer",
      args: [bountyId, 0n, answer, "0x" + secret],
    });
  }, [bountyId, answer, secret]);

  return (
    <div>
      <textarea value={answer} onChange={e => setAnswer(e.target.value)} />
      <button onClick={commit}>Commit</button>
      <button onClick={reveal}>Reveal</button>
    </div>
  );
}