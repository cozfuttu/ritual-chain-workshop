# 🤔 Reflection Question

> "What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"

---

## My Answer

In a bounty system, **transparency and privacy must coexist** to ensure fairness. The **commitment hashes** should be public so participants can verify that others have submitted without seeing their answers, preventing front-running while maintaining accountability. The **actual answers** should stay hidden until the reveal phase ends, ensuring no one can copy or improve upon another's work before the deadline. Once revealed, answers become public for auditability, but the **salt values** must remain private to each participant forever, as they are the cryptographic key that protects the commitment's integrity. The **prize pool and winner** should always be public to maintain trust in the system.

**AI should handle the initial scoring** of answers because it can process hundreds of submissions consistently without bias or fatigue, applying the same criteria to every participant equally. However, **humans should make the final decision** in edge cases—such as when scores are tied, when an answer challenges the AI's judgment criteria, or when the bounty involves subjective creative work that requires human nuance. The ideal model is a **human-AI hybrid**: AI provides the first pass of evaluation at scale, while humans retain veto power and handle appeals. This ensures the system is both **efficient** (AI handles volume) and **fair** (humans handle judgment calls).

---

## Summary

| Element | Visibility | Decision Maker |
|---------|------------|----------------|
| Commitment hashes | Public | N/A |
| Revealed answers | Public (after reveal) | N/A |
| Salts | Private (user only) | N/A |
| Prize pool | Public | Admin |
| Initial scoring | Public | AI (Ritual LLM) |
| Final winner | Public | Human (Admin) |
| Edge cases | Public | Human + AI |

---

*Written for Ritual Chain Workshop — Privacy-Preserving AI Bounty Judge Assignment*
