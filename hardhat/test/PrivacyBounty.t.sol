// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PrivacyBounty.sol";

contract PrivacyBountyTest is Test {
    PrivacyBounty public bounty;
    address public admin = address(0xAD);
    address public alice = address(0xA1);
    address public bob = address(0xB0B);
    address public charlie = address(0xC0C);

    uint256 public constant PRIZE = 1 ether;

    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.prank(admin);
        bounty = new PrivacyBounty();
    }

    // ==================== CREATE BOUNTY TESTS ====================

    function test_CreateBounty() public {
        uint256 submissionDeadline = block.timestamp + 1 days;
        uint256 revealDeadline = block.timestamp + 2 days;

        vm.prank(admin);
        uint256 bountyId = bounty.createBounty{value: PRIZE}(
            "Best AI Prompt",
            "Create the best prompt for code generation",
            submissionDeadline,
            revealDeadline
        );

        assertEq(bountyId, 0);
        assertEq(bounty.bountyCount(), 1);

        (, , uint256 prizePool, address creator, , , , ) = bounty.getBounty(0);
        assertEq(prizePool, PRIZE);
        assertEq(creator, admin);
    }

    function test_CreateBounty_RevertNoAdmin() public {
        uint256 submissionDeadline = block.timestamp + 1 days;
        uint256 revealDeadline = block.timestamp + 2 days;

        vm.prank(alice);
        vm.expectRevert();
        bounty.createBounty{value: PRIZE}(
            "Test",
            "Test",
            submissionDeadline,
            revealDeadline
        );
    }

    // ==================== COMMITMENT TESTS ====================

    function test_SubmitCommitment() public {
        _createBounty();

        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));
        bytes32 commitment = keccak256(
            abi.encodePacked("My answer", salt, alice, uint256(0))
        );

        vm.prank(alice);
        bounty.submitCommitment(0, commitment);

        (bool committed, , , ) = bounty.getSubmission(0, alice);
        assertTrue(committed);
        assertEq(bounty.getParticipantCount(0), 1);
    }

    function test_SubmitCommitment_RevertAfterDeadline() public {
        _createBounty();

        // Warp past submission deadline
        vm.warp(block.timestamp + 1 days + 1);

        bytes32 salt = keccak256(abi.encodePacked("salt"));
        bytes32 commitment = keccak256(
            abi.encodePacked("answer", salt, alice, uint256(0))
        );

        vm.prank(alice);
        vm.expectRevert("Submission phase ended");
        bounty.submitCommitment(0, commitment);
    }

    function test_SubmitCommitment_RevertDuplicate() public {
        _createBounty();

        bytes32 salt = keccak256(abi.encodePacked("salt"));
        bytes32 commitment = keccak256(
            abi.encodePacked("answer", salt, alice, uint256(0))
        );

        vm.prank(alice);
        bounty.submitCommitment(0, commitment);

        vm.prank(alice);
        vm.expectRevert("Already committed");
        bounty.submitCommitment(0, commitment);
    }

    // ==================== REVEAL TESTS ====================

    function test_RevealAnswer() public {
        _createBounty();
        _commitAs(alice, "My answer");

        // Warp to reveal phase
        vm.warp(block.timestamp + 1 days + 1);

        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));

        vm.prank(alice);
        bounty.revealAnswer(0, "My answer", salt);

        (, bool revealed, , ) = bounty.getSubmission(0, alice);
        assertTrue(revealed);
    }

    function test_RevealAnswer_InvalidReveal() public {
        _createBounty();
        _commitAs(alice, "My answer");

        vm.warp(block.timestamp + 1 days + 1);

        bytes32 wrongSalt = keccak256(abi.encodePacked("wrongSalt"));

        vm.prank(alice);
        vm.expectRevert("Invalid reveal");
        bounty.revealAnswer(0, "My answer", wrongSalt);
    }

    function test_RevealAnswer_RevertBeforeDeadline() public {
        _createBounty();
        _commitAs(alice, "My answer");

        // Still in submission phase
        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));

        vm.prank(alice);
        vm.expectRevert("Reveal phase not started");
        bounty.revealAnswer(0, "My answer", salt);
    }

    // ==================== VERIFICATION TESTS ====================

    function test_VerifyCommitment() public {
        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));
        bytes32 commitment = keccak256(
            abi.encodePacked("My answer", salt, alice, uint256(0))
        );

        assertTrue(
            bounty.verifyCommitment(commitment, "My answer", salt, alice, 0)
        );
    }

    function test_VerifyCommitment_Invalid() public {
        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));
        bytes32 commitment = keccak256(
            abi.encodePacked("My answer", salt, alice, uint256(0))
        );

        assertFalse(
            bounty.verifyCommitment(commitment, "Wrong answer", salt, alice, 0)
        );
    }

    // ==================== HELPER FUNCTIONS ====================

    function _createBounty() internal returns (uint256) {
        uint256 submissionDeadline = block.timestamp + 1 days;
        uint256 revealDeadline = block.timestamp + 2 days;

        vm.prank(admin);
        return bounty.createBounty{value: PRIZE}(
            "Best AI Prompt",
            "Create the best prompt",
            submissionDeadline,
            revealDeadline
        );
    }

    function _commitAs(address participant, string memory answer) internal {
        bytes32 salt = keccak256(abi.encodePacked("mySecretSalt"));
        bytes32 commitment = keccak256(
            abi.encodePacked(answer, salt, participant, uint256(0))
        );

        vm.prank(participant);
        bounty.submitCommitment(0, commitment);
    }
}
