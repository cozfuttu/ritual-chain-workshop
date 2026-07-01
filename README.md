# RandomAIBounty – Commit-Reveal with Random Winner Selection

This contract uses **verifiable randomness** to select winners, eliminating owner bias and voting collusion. Winners are chosen randomly from all participants who revealed their answers.

## How it works
1. Commit phase: participants submit hashed answers.
2. Reveal phase: participants reveal their answers.
3. Randomness generation: owner generates verifiable randomness using block data + salt.
4. Winner selection: top N winners are randomly selected with prize distribution (50%, 30%, 20%).

## Why randomness?
Fair, unbiased, and verifiable winner selection – perfect for raffle-style bounties.

## Contract Address (Ritual Testnet)
0x5F3542Cb00947C92484878e4D557f78e72679448

## Network
Ritual Chain Testnet (ID: 1979)
