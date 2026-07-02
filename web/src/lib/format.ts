import { formatEther } from "viem";

/** 0x1234…abcd */
export function shortenAddress(address?: string, chars = 4): string {
  if (!address) return "";
  if (address.length < 2 + chars * 2) return address;
  return `${address.slice(0, 2 + chars)}…${address.slice(-chars)}`;
}

/** Format a wei value as a human native-token amount, e.g. "1.5 RITUAL". */
export function formatReward(wei?: bigint, symbol = "RITUAL"): string {
  if (wei === undefined) return "-";
  return `${formatEther(wei)} ${symbol}`;
}

function timestampToMs(timestamp: bigint | number): number {
  const n = Number(timestamp);
  return n > 10_000_000_000 ? n : n * 1000;
}

/** Unix seconds, or Ritual millisecond timestamp -> local date string. */
export function formatTimestamp(timestamp?: bigint | number): string {
  if (timestamp === undefined) return "-";
  const ms = timestampToMs(timestamp);
  if (!Number.isFinite(ms) || ms <= 0) return "-";
  return new Date(ms).toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

/** Compact "in 2h 5m" / "3m ago" style relative label. */
export function formatRelative(unixSeconds?: bigint | number): string {
  if (unixSeconds === undefined) return "";
  const target = timestampToMs(unixSeconds);
  const diffMs = target - Date.now();
  const past = diffMs < 0;
  let s = Math.abs(Math.floor(diffMs / 1000));
  const d = Math.floor(s / 86400);
  s -= d * 86400;
  const h = Math.floor(s / 3600);
  s -= h * 3600;
  const m = Math.floor(s / 60);
  const parts: string[] = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m && parts.length < 2) parts.push(`${m}m`);
  if (parts.length === 0) parts.push("<1m");
  const body = parts.join(" ");
  return past ? `${body} ago` : `in ${body}`;
}

export function isAddressEqual(a?: string, b?: string): boolean {
  if (!a || !b) return false;
  return a.toLowerCase() === b.toLowerCase();
}
