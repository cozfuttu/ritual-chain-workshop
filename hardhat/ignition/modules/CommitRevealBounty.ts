import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("CommitRevealBountyModule", (m) => {
  const commitRevealBounty = m.contract("CommitRevealBounty");
  return { commitRevealBounty };
});
