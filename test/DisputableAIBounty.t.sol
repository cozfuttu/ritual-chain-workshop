// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/DisputableAIBounty.sol";

contract DisputableAIBountyTest is Test {
    DisputableAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        bounty = new DisputableAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: 1 ether}("Test", commitDeadline, 2 days);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
    }

    function testFullFlow() public {
        vm.startPrank(alice);
        bounty.commitSolution(challengeId, aliceCommitment);
        vm.stopPrank();
        vm.startPrank(bob);
        bounty.commitSolution(challengeId, bobCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealSolution(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
        vm.startPrank(bob);
        bounty.revealSolution(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(owner);
        bounty.judgeAll(challengeId, bytes(""));
        bounty.finalizeWinner(challengeId, 1);
        vm.stopPrank();

        DisputableAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + 1 ether);
    }

    function testDisputeFlow() public {
        testFullFlow();
        vm.warp(block.timestamp + 12 hours);
        vm.startPrank(alice);
        bounty.initiateDispute(challengeId);
        vm.stopPrank();
        DisputableAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.disputed);
        vm.warp(block.timestamp + 13 hours);
        vm.startPrank(owner);
        bounty.resolveDispute(challengeId, 0);
        vm.stopPrank();
        info = bounty.getChallengeInfo(challengeId);
        assertEq(info.winner, alice);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.commitSolution(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealSolution(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }
}
