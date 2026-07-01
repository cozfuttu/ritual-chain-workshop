# Test Plan – RandomAIBounty

- Happy path: 3 participants commit → reveal → generate randomness → select winners
- Cannot reveal before deadline (reverts)
- Cannot select winners without randomness (reverts)
- Multiple winners (2-5) with correct prize distribution
- Verifiable randomness using block data
