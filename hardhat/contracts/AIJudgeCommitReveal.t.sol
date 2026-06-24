// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AIJudge} from "./AIJudge.sol";

contract AIJudgeCommitRevealTest is Test {
    AIJudge judge;

    address owner = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xC0FFEE);

    uint256 bountyId;
    uint256 deadline;

    function setUp() public {
        judge = new AIJudge();
        deadline = block.timestamp + 1 days;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        bountyId = judge.createBounty{value: 1 ether}(
            "Best explanation of Ritual Chain",
            "Choose the most correct and beginner-friendly answer.",
            deadline
        );
    }

    function test_submitCommitmentStoresHashWithoutPublicAnswer() public {
        bytes32 salt = keccak256("alice secret salt");
        bytes32 commitment = judge.computeCommitment(
            "Ritual brings AI precompiles to EVM apps.",
            salt,
            alice,
            bountyId
        );

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        (address submitter, bytes32 storedCommitment, string memory answer, bool revealed) = judge.getSubmission(bountyId, 0);
        assertEq(submitter, alice);
        assertEq(storedCommitment, commitment);
        assertEq(bytes(answer).length, 0);
        assertFalse(revealed);
    }

    function test_revealAfterDeadlineWithCorrectSaltMakesAnswerEligible() public {
        string memory answer = "Ritual enables smart contracts to use TEE-backed LLM inference.";
        bytes32 salt = keccak256("alice salt");
        bytes32 commitment = judge.computeCommitment(answer, salt, alice, bountyId);

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        vm.warp(deadline + 1);
        vm.prank(alice);
        judge.revealAnswer(bountyId, answer, salt);

        (address submitter, bytes32 storedCommitment, string memory revealedAnswer, bool revealed) = judge.getSubmission(bountyId, 0);
        assertEq(submitter, alice);
        assertEq(storedCommitment, commitment);
        assertEq(revealedAnswer, answer);
        assertTrue(revealed);
        assertEq(judge.getRevealedSubmissionCount(bountyId), 1);
    }

    function test_revealWithWrongSaltReverts() public {
        string memory answer = "Correct answer";
        bytes32 salt = keccak256("right salt");
        bytes32 commitment = judge.computeCommitment(answer, salt, alice, bountyId);

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert("invalid reveal");
        judge.revealAnswer(bountyId, answer, keccak256("wrong salt"));
    }

    function test_revealFromDifferentAddressReverts() public {
        string memory answer = "Correct answer";
        bytes32 salt = keccak256("salt");
        bytes32 commitment = judge.computeCommitment(answer, salt, alice, bountyId);

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        vm.warp(deadline + 1);
        vm.prank(bob);
        vm.expectRevert("no commitment");
        judge.revealAnswer(bountyId, answer, salt);
    }

    function test_cannotSubmitCommitmentAfterDeadline() public {
        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert("commit phase closed");
        judge.submitCommitment(bountyId, keccak256("late"));
    }

    function test_cannotRevealBeforeDeadline() public {
        string memory answer = "Correct answer";
        bytes32 salt = keccak256("salt");
        bytes32 commitment = judge.computeCommitment(answer, salt, alice, bountyId);

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        vm.prank(alice);
        vm.expectRevert("reveal phase not open");
        judge.revealAnswer(bountyId, answer, salt);
    }

    function test_cannotJudgeWithoutRevealedAnswers() public {
        vm.warp(deadline + 1);
        vm.prank(owner);
        vm.expectRevert("no revealed submissions");
        judge.judgeAll(bountyId, hex"");
    }

    function test_finalizeWinnerRequiresRevealedSubmission() public {
        string memory answer = "Valid answer";
        bytes32 salt = keccak256("salt");
        bytes32 commitment = judge.computeCommitment(answer, salt, alice, bountyId);

        vm.prank(alice);
        judge.submitCommitment(bountyId, commitment);

        vm.warp(deadline + 1);
        vm.prank(owner);
        vm.expectRevert("not judged yet");
        judge.finalizeWinner(bountyId, 0);
    }
}
