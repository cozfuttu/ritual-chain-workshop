# Hardhat: Privacy-Preserving AI Bounty Judge

This package contains the Solidity implementation and tests for the
commit-reveal AI bounty judge.

## Contract

- `contracts/AIJudge.sol` is the production contract.
- `contracts/utils/PrecompileConsumer.sol` contains the Ritual precompile helper.
- `contracts/test/MockAIJudge.sol` is test-only and mocks the Ritual LLM result.

Required public entrypoints:

```solidity
function submitCommitment(uint256 bountyId, bytes32 commitment) external;

function revealAnswer(
    uint256 bountyId,
    string calldata answer,
    bytes32 salt
) external;

function judgeAll(uint256 bountyId, bytes calldata llmInput) external;

function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external;
```

## Run tests

```bash
npm install
npx hardhat test
```

## Compile

```bash
npx hardhat compile
```

## Deploy

Local simulated deployment:

```bash
npx hardhat ignition deploy ignition/modules/AIJudge.ts
```

Ritual Chain deployment:

```bash
npx hardhat ignition deploy ignition/modules/AIJudge.ts --network ritual
```

Put the deployer key in a local, ignored `hardhat/.env` file before running the
command.

The Ritual network configuration uses:

- Chain ID: `1979`
- RPC: `https://rpc.ritualfoundation.org`
- Currency: `RITUAL`

`judgeAll()` depends on Ritual's LLM precompile when using the production
contract. The commit-reveal lifecycle itself uses ordinary EVM features and can
be deployed to any EVM chain.
