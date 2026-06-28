import hre from "hardhat";

async function main() {
  const contract = await hre.viem.deployContract("CommitRevealBounty", []);
  console.log("CommitRevealBounty deployed to:", contract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
