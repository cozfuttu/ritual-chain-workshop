// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/RandomAIBounty.sol";

contract RandomAIBountyTest is Test {
    RandomAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 charlieCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    bytes32 charlieSalt = keccak256("charlie_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";
    string charlieAnswer = "Charlie's solution";
    uint256 reward = 1 ether;
    bytes32 randomSalt = keccak256("random_salt");

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
        bounty = new RandomAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, 2);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
        charlieCommitment = keccak256(abi.encodePacked(charlieAnswer, charlieSalt, charlie, challengeId));
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.commitSolution(challengeId, aliceCommitment);
        vm.stopPrank();
        vm.startPrank(bob);
        bounty.commitSolution(challengeId, bobCommitment);
        vm.stopPrank();
        vm.startPrank(charlie);
        bounty.commitSolution(challengeId, charlieCommitment);
        vm.stopPrank();

        // Reveal
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealSolution(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
        vm.startPrank(bob);
        bounty.revealSolution(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();
        vm.startPrank(charlie);
        bounty.revealSolution(challengeId, charlieAnswer, charlieSalt);
        vm.stopPrank();

        // Generate randomness and select winners
        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(owner);
        bounty.generateRandomness(challengeId, randomSalt);
        bounty.selectWinners(challengeId);
        vm.stopPrank();

        // Verify winners selected
        RandomAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        
        address[] memory winners = bounty.getWinners(challengeId);
        assertEq(winners.length, 2);
        
        uint256[] memory shares = bounty.getPrizeShares(challengeId);
        assertEq(shares.length, 2);
        
        // Total shares should equal reward
        uint256 totalShares = 0;
        for (uint i = 0; i < shares.length; i++) {
            totalShares += shares[i];
        }
        assertEq(totalShares, reward);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.commitSolution(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealSolution(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }

    function testCannotSelectWithoutRandomness() public {
        vm.startPrank(alice);
        bounty.commitSolution(challengeId, aliceCommitment);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealSolution(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(owner);
        vm.expectRevert("Randomness not generated yet");
        bounty.selectWinners(challengeId);
        vm.stopPrank();
    }
}
