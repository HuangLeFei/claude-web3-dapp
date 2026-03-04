// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { VotingSystem } from "../src/VotingSystem.sol";

/// @title VotingSystemTest
/// @notice Comprehensive test suite for VotingSystem contract
contract VotingSystemTest is Test {
    VotingSystem public implementation;
    VotingSystem public proxyAsVotingSystem;

    // Roles and addresses
    address public admin = makeAddr("admin");
    address public emergencyAdmin = makeAddr("emergencyAdmin");
    address public auditor = makeAddr("auditor");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public unauthorized = makeAddr("unauthorized");

    // Constants
    uint64 public constant relativeStartTime = 1 hours; // Relative to warp
    uint256 public constant duration = 7 days;
    uint256 public constant quorum = 5;

    // ============ Setup Functions ============

    function setUp() public {
        // Deploy implementation
        implementation = new VotingSystem();

        // Prepare initialization calldata
        bytes memory initData = abi.encodeCall(
            VotingSystem.initialize,
            (admin, emergencyAdmin, auditor)
        );

        // Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxyAsVotingSystem = VotingSystem(address(proxyContract));
    }

    function _setupWithProposal() internal returns (uint256 proposalId) {
        return _setupWithProposal(VotingSystem.VotingType.SingleChoice);
    }

    function _setupWithProposal(VotingSystem.VotingType votingType) internal returns (uint256 newProposalId) {
        vm.prank(admin);
        newProposalId = proxyAsVotingSystem.createProposal(
            "Test Proposal",
            "This is a test proposal",
            uint64(block.timestamp + relativeStartTime),
            duration,
            votingType,
            quorum
        );
    }

    function _setupVoters(uint256 proposalId) internal {
        address[] memory voters = new address[](3);
        voters[0] = user1;
        voters[1] = user2;
        voters[2] = user3;
        vm.prank(admin);
        proxyAsVotingSystem.batchRegisterVoters(voters);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate1"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate2"), 1);
    }

    function _advanceToVoting() internal {
        vm.warp(block.timestamp + relativeStartTime);
    }

    // ============ Initialization Tests ============

    function test_initialize_success() public {
        VotingSystem impl = new VotingSystem();
        bytes memory initData = abi.encodeCall(
            VotingSystem.initialize,
            (admin, emergencyAdmin, auditor)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        VotingSystem freshProxy = VotingSystem(address(proxyContract));

        assertEq(freshProxy.hasRole(freshProxy.ADMIN_ROLE(), admin), true);
        assertEq(freshProxy.hasRole(freshProxy.EMERGENCY_ROLE(), emergencyAdmin), true);
        assertEq(freshProxy.hasRole(freshProxy.AUDITOR_ROLE(), auditor), true);
        assertEq(freshProxy.votingDelay(), 0);
        assertEq(freshProxy.votingDuration(), 7 days);
        assertEq(freshProxy.minVoters(), 10);
    }

    function test_initialize_zeroAddress_reverts() public {
        VotingSystem impl = new VotingSystem();
        bytes memory initData = abi.encodeCall(
            VotingSystem.initialize,
            (address(0), emergencyAdmin, auditor)
        );
        vm.expectRevert(VotingSystem.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // ============ Voter Management Tests ============

    function test_registerVoter_success() public {
        address newVoter = makeAddr("newVoter");
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.VoterRegistered(newVoter, block.timestamp, 1);
        proxyAsVotingSystem.registerVoter(newVoter);

        (bool isRegistered, bool isEligible,,,) = proxyAsVotingSystem.getVoterInfo(newVoter);
        assertTrue(isRegistered);
        assertTrue(isEligible);
    }

    function test_registerVoter_alreadyRegistered_reverts() public {
        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(user1);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VoterAlreadyRegistered.selector, user1));
        proxyAsVotingSystem.registerVoter(user1);
    }

    function test_registerVoter_zeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(VotingSystem.ZeroAddress.selector);
        proxyAsVotingSystem.registerVoter(address(0));
    }

    function test_registerVoter_notAdmin_reverts() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.Unauthorized.selector, unauthorized, proxyAsVotingSystem.ADMIN_ROLE()));
        proxyAsVotingSystem.registerVoter(user1);
    }

    function test_batchRegisterVoters_success() public {
        address[] memory voters = new address[](3);
        voters[0] = makeAddr("voter1");
        voters[1] = makeAddr("voter2");
        voters[2] = makeAddr("voter3");

        vm.prank(admin);
        proxyAsVotingSystem.batchRegisterVoters(voters);

        assertEq(proxyAsVotingSystem.voterCount(), 3);
        (bool isRegistered, bool isEligible,,,) = proxyAsVotingSystem.getVoterInfo(voters[0]);
        assertTrue(isRegistered);
        assertTrue(isEligible);
    }

    function test_batchRegisterVoters_emptyArray_reverts() public {
        address[] memory voters = new address[](0);
        vm.prank(admin);
        vm.expectRevert(VotingSystem.ArrayLengthMismatch.selector);
        proxyAsVotingSystem.batchRegisterVoters(voters);
    }

    function test_removeVoter_success() public {
        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(user1);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.VoterRemoved(user1, block.timestamp, 0);
        proxyAsVotingSystem.removeVoter(user1);

        (bool isRegistered, bool isEligible,,,) = proxyAsVotingSystem.getVoterInfo(user1);
        assertFalse(isRegistered);
        assertFalse(isEligible);
    }

    function test_removeVoter_notRegistered_reverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VoterNotRegistered.selector, unauthorized));
        proxyAsVotingSystem.removeVoter(unauthorized);
    }

    // ============ Proposal Management Tests ============

    function test_createProposal_success() public {
        uint64 futureStartTime = uint64(block.timestamp + 1 days);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.ProposalCreated(
            0,
            admin,
            "New Proposal",
            futureStartTime,
            futureStartTime + 7 days,
            VotingSystem.VotingType.SingleChoice
        );
        uint256 newProposalId = proxyAsVotingSystem.createProposal(
            "New Proposal",
            "Description",
            futureStartTime,
            7 days,
            VotingSystem.VotingType.SingleChoice,
            10
        );

        assertEq(newProposalId, 0);
        assertEq(proxyAsVotingSystem.proposalCount(), 1);
    }

    function test_createProposal_invalidTime_reverts() public {
        // Start time in the past
        vm.prank(admin);
        vm.expectRevert(VotingSystem.InvalidTimeRange.selector);
        proxyAsVotingSystem.createProposal(
            "Invalid Proposal",
            "Description",
            uint64(block.timestamp - 1 hours),
            7 days,
            VotingSystem.VotingType.SingleChoice,
            10
        );
    }

    function test_createProposal_zeroQuorum_reverts() public {
        vm.prank(admin);
        vm.expectRevert(VotingSystem.InvalidTimeRange.selector);
        proxyAsVotingSystem.createProposal(
            "Invalid Proposal",
            "Description",
            uint64(block.timestamp + 1 days),
            7 days,
            VotingSystem.VotingType.SingleChoice,
            0
        );
    }

    function test_createProposal_notAdmin_reverts() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.Unauthorized.selector, unauthorized, proxyAsVotingSystem.ADMIN_ROLE()));
        proxyAsVotingSystem.createProposal(
            "Unauthorized Proposal",
            "Description",
            uint64(block.timestamp + 1 days),
            7 days,
            VotingSystem.VotingType.SingleChoice,
            10
        );
    }

    function test_addCandidate_success() public {
        uint256 proposalId = _setupWithProposal();
        address candidate = makeAddr("candidate1");

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.CandidateAdded(proposalId, candidate, 1, 0);
        proxyAsVotingSystem.addCandidate(proposalId, candidate, 1);

        VotingSystem.CandidateInfo[] memory candidates = proxyAsVotingSystem.getProposalCandidates(proposalId);
        assertEq(candidates.length, 1);
        assertEq(candidates[0].candidateAddress, candidate);
        assertEq(candidates[0].voteWeight, 1);
    }

    function test_addCandidate_zeroAddress_reverts() public {
        uint256 proposalId = _setupWithProposal();
        vm.prank(admin);
        vm.expectRevert(VotingSystem.ZeroAddress.selector);
        proxyAsVotingSystem.addCandidate(proposalId, address(0), 1);
    }

    function test_addCandidate_nonExistentProposal_reverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.ProposalDoesNotExist.selector, 999));
        proxyAsVotingSystem.addCandidate(999, user1, 1);
    }

    function test_batchAddCandidates_success() public {
        uint256 proposalId = _setupWithProposal();
        address[] memory candidates = new address[](3);
        candidates[0] = makeAddr("candidate1");
        candidates[1] = makeAddr("candidate2");
        candidates[2] = makeAddr("candidate3");
        uint256[] memory weights = new uint256[](3);
        weights[0] = 1;
        weights[1] = 2;
        weights[2] = 3;

        vm.prank(admin);
        proxyAsVotingSystem.batchAddCandidates(proposalId, candidates, weights);

        VotingSystem.CandidateInfo[] memory result = proxyAsVotingSystem.getProposalCandidates(proposalId);
        assertEq(result.length, 3);
        assertEq(result[0].voteWeight, 1);
        assertEq(result[1].voteWeight, 2);
        assertEq(result[2].voteWeight, 3);
    }

    function test_batchAddCandidates_lengthMismatch_reverts() public {
        uint256 proposalId = _setupWithProposal();
        address[] memory candidates = new address[](2);
        candidates[0] = makeAddr("candidate1");
        candidates[1] = makeAddr("candidate2");
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        vm.prank(admin);
        vm.expectRevert(VotingSystem.ArrayLengthMismatch.selector);
        proxyAsVotingSystem.batchAddCandidates(proposalId, candidates, weights);
    }

    // ============ Voting Tests ============

    function test_castSingleVote_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Cast vote
        vm.prank(user1);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        vm.expectEmit(true, true, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.VoteCast(proposalId, user1, indices, block.timestamp);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.totalVotes, 1);
    }

    function test_castSingleVote_notActive_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);

        // Voting hasn't started yet
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VotingNotStarted.selector, proposalId));
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
    }

    function test_castSingleVote_alreadyVoted_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Cast vote first time
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        // Try to vote again
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.AlreadyVoted.selector, user1, proposalId));
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
    }

    function test_castSingleVote_notRegistered_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _advanceToVoting;

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VoterNotRegistered.selector, unauthorized));
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
    }

    function test_castSingleVote_invalidCandidate_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.InvalidCandidateIndex.selector, proposalId, 999));
        proxyAsVotingSystem.castSingleVote(proposalId, 999);
    }

    function test_castMultiVote_success() public {
        uint256 proposalId = _setupWithProposal(VotingSystem.VotingType.MultiChoice);

        // Add multiple candidates
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate1"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate2"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate3"), 1);

        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(user1);

        _advanceToVoting;

        // Cast multi vote
        uint256[] memory candidateIndices = new uint256[](2);
        candidateIndices[0] = 0;
        candidateIndices[1] = 2;
        vm.prank(user1);
        proxyAsVotingSystem.castMultiVote(proposalId, candidateIndices);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.totalVotes, 1);
    }

    function test_castRankedVote_success() public {
        uint256 proposalId = _setupWithProposal(VotingSystem.VotingType.RankedChoice);

        // Add candidates
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate1"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate2"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate3"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(user1);

        _advanceToVoting;

        // Cast ranked vote
        uint256[] memory rankings = new uint256[](3);
        rankings[0] = 2; // First choice: candidate 2
        rankings[1] = 0; // Second choice: candidate 0
        rankings[2] = 1; // Third choice: candidate 1
        vm.prank(user1);
        proxyAsVotingSystem.castRankedVote(proposalId, rankings);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.totalVotes, 1);
    }

    function test_castRankedVote_duplicateRank_reverts() public {
        uint256 proposalId = _setupWithProposal(VotingSystem.VotingType.RankedChoice);

        // Add candidates
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate1"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate2"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(user1);

        _advanceToVoting;

        // Duplicate ranking
        uint256[] memory rankings = new uint256[](2);
        rankings[0] = 0;
        rankings[1] = 0; // Duplicate
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.InvalidCandidateIndex.selector, proposalId, 0));
        proxyAsVotingSystem.castRankedVote(proposalId, rankings);
    }

    // ============ Commit-Reveal Tests ============

    function test_commitVote_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        bytes32 commitment = keccak256(abi.encodePacked(uint256(0), uint256(12345)));

        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.VoteCommitted(proposalId, user1, commitment, block.timestamp);
        proxyAsVotingSystem.commitVote(proposalId, commitment);

        bytes32 storedHash = proxyAsVotingSystem.commitHashes(proposalId, user1);
        assertEq(storedHash, commitment);
    }

    function test_commitVote_zeroHash_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        vm.prank(user1);
        vm.expectRevert(VotingSystem.InvalidCommitment.selector);
        proxyAsVotingSystem.commitVote(proposalId, bytes32(0));
    }

    function test_revealVote_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Commit
        uint256[] memory candidateIndices = new uint256[](1);
        candidateIndices[0] = 0;
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(candidateIndices, nonce));

        vm.prank(user1);
        proxyAsVotingSystem.commitVote(proposalId, commitment);

        // Reveal
        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.VoteRevealed(proposalId, user1, candidateIndices, block.timestamp);
        proxyAsVotingSystem.revealVote(proposalId, candidateIndices, nonce);

        // Check hasVoted
        assertTrue(proxyAsVotingSystem.hasVotedOnProposal(user1, proposalId));
    }

    function test_revealVote_notCommitted_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        uint256[] memory candidateIndices = new uint256[](1);
        candidateIndices[0] = 0;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.NotCommitted.selector, proposalId, user1));
        proxyAsVotingSystem.revealVote(proposalId, candidateIndices, 12345);
    }

    function test_revealVote_invalidCommitment_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Commit with one set of data
        bytes32 commitment = keccak256(abi.encodePacked(uint256(0), uint256(12345)));
        vm.prank(user1);
        proxyAsVotingSystem.commitVote(proposalId, commitment);

        // Reveal with different data
        uint256[] memory candidateIndices = new uint256[](1);
        candidateIndices[0] = 1; // Different from commitment
        vm.prank(user1);
        vm.expectRevert(VotingSystem.InvalidCommitment.selector);
        proxyAsVotingSystem.revealVote(proposalId, candidateIndices, 12345);
    }

    function test_revealVote_expired_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Commit
        uint256[] memory candidateIndices = new uint256[](1);
        candidateIndices[0] = 0;
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(candidateIndices, nonce));

        vm.prank(user1);
        proxyAsVotingSystem.commitVote(proposalId, commitment);

        // Fast forward past reveal period
        vm.warp(block.timestamp + duration + proxyAsVotingSystem.REVEAL_PERIOD() + 1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.CommitmentExpired.selector, proposalId, user1));
        proxyAsVotingSystem.revealVote(proposalId, candidateIndices, nonce);
    }

    // ============ Result Management Tests ============

    function test_endProposal_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Vote
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        // End proposal (after voting period)
        vm.warp(block.timestamp + duration + 1);
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.ProposalEnded(proposalId, 1, quorum, false);
        proxyAsVotingSystem.endProposal(proposalId, false);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(uint8(proposal.status), uint8(VotingSystem.ProposalStatus.Ended));
    }

    function test_endProposal_notEnded_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Try to end before voting period ends
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VotingNotStarted.selector, proposalId));
        proxyAsVotingSystem.endProposal(proposalId, false);
    }

    function test_publishResults_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Multiple votes
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
        vm.prank(user2);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        // End and publish
        vm.warp(block.timestamp + duration + 1);
        vm.prank(admin);
        proxyAsVotingSystem.endProposal(proposalId, true);

        VotingSystem.CandidateResult[] memory results = proxyAsVotingSystem.getProposalResults(proposalId);
        assertEq(results.length, 2);
        assertEq(results[0].voteCount, 2); // Winner should have 2 votes
    }

    // ============ Permission Tests ============

    function test_pause_success() public {
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, false, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.ContractPaused(emergencyAdmin, block.timestamp);
        proxyAsVotingSystem.pause();

        assertTrue(proxyAsVotingSystem.paused());
    }

    function test_pause_notEmergencyAdmin_reverts() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.Unauthorized.selector, unauthorized, proxyAsVotingSystem.EMERGENCY_ROLE()));
        proxyAsVotingSystem.pause();
    }

    function test_unpause_success() public {
        vm.prank(emergencyAdmin);
        proxyAsVotingSystem.pause();

        vm.prank(emergencyAdmin);
        vm.expectEmit(true, false, false, true, address(proxyAsVotingSystem));
        emit VotingSystem.ContractUnpaused(emergencyAdmin, block.timestamp);
        proxyAsVotingSystem.unpause();

        assertFalse(proxyAsVotingSystem.paused());
    }

    function test_paused_registerVoter_reverts() public {
        vm.prank(emergencyAdmin);
        proxyAsVotingSystem.pause();

        vm.prank(admin);
        vm.expectRevert();
        proxyAsVotingSystem.registerVoter(makeAddr("newVoter"));
    }

    function test_paused_createProposal_reverts() public {
        vm.prank(emergencyAdmin);
        proxyAsVotingSystem.pause();

        vm.prank(admin);
        vm.expectRevert();
        proxyAsVotingSystem.createProposal(
            "Test",
            "Test",
            uint64(block.timestamp + 1 days),
            7 days,
            VotingSystem.VotingType.SingleChoice,
            10
        );
    }

    // ============ Query Function Tests ============

    function test_getProposal_success() public {
        uint256 proposalId = _setupWithProposal();

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.id, proposalId);
        assertEq(proposal.title, "Test Proposal");
        assertEq(proposal.creator, admin);
    }

    function test_getProposalCandidates_success() public {
        uint256 proposalId = _setupWithProposal();
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate1"), 1);
        vm.prank(admin);
        proxyAsVotingSystem.addCandidate(proposalId, makeAddr("candidate2"), 2);

        VotingSystem.CandidateInfo[] memory candidates = proxyAsVotingSystem.getProposalCandidates(proposalId);
        assertEq(candidates.length, 2);
    }

    function test_getActiveProposals_success() public {
        _setupWithProposal();
        uint256[] memory active = proxyAsVotingSystem.getActiveProposals();
        assertEq(active.length, 1);
        assertEq(active[0], 0);
    }

    function test_getVoterVotingHistory_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Vote
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        uint256[] memory history = proxyAsVotingSystem.getVoterVotingHistory(user1);
        assertEq(history.length, 1);
        assertEq(history[0], 0);
    }

    // ============ Configuration Tests ============

    function test_setOracle_success() public {
        address oracle = makeAddr("oracle");
        vm.prank(admin);
        proxyAsVotingSystem.setOracle(oracle);
        assertEq(proxyAsVotingSystem.voterOracle(), oracle);
    }

    function test_setVotingDelay_success() public {
        vm.prank(admin);
        proxyAsVotingSystem.setVotingDelay(1 days);
        assertEq(proxyAsVotingSystem.votingDelay(), 1 days);
    }

    function test_setVotingDuration_success() public {
        vm.prank(admin);
        proxyAsVotingSystem.setVotingDuration(14 days);
        assertEq(proxyAsVotingSystem.votingDuration(), 14 days);
    }

    function test_setQuorum_success() public {
        uint256 proposalId = _setupWithProposal();
        vm.prank(admin);
        proxyAsVotingSystem.setQuorum(proposalId, 20);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.quorum, 20);
    }

    function test_setQuorum_afterStart_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _advanceToVoting;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.ProposalNotActive.selector, proposalId));
        proxyAsVotingSystem.setQuorum(proposalId, 20);
    }

    // ============ Audit Function Tests ============

    function test_verifyResults_success() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // Vote
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        // End and publish
        vm.warp(block.timestamp + duration + 1);
        vm.prank(admin);
        proxyAsVotingSystem.endProposal(proposalId, true);

        vm.prank(auditor);
        bool valid = proxyAsVotingSystem.verifyResults(proposalId);
        assertTrue(valid);
    }

    function test_verifyResults_notPublished_reverts() public {
        vm.prank(auditor);
        bool valid = proxyAsVotingSystem.verifyResults(0);
        assertFalse(valid);
    }

    // ============ Fuzz Tests ============

    function testFuzz_registerVoter(uint8 seed) public {
        address voter = makeAddr(string(abi.encodePacked("voter", seed)));
        vm.prank(admin);
        proxyAsVotingSystem.registerVoter(voter);

        (bool isRegistered, bool isEligible,,,) = proxyAsVotingSystem.getVoterInfo(voter);
        assertTrue(isRegistered);
        assertTrue(isEligible);
    }

    function testFuzz_multipleVoters(uint8 numVoters) public {
        // Bound the number of voters to avoid gas issues
        uint256 bounded = bound(numVoters, 1, 10);

        address[] memory voters = new address[](bounded);
        for (uint256 i = 0; i < bounded; i++) {
            voters[i] = makeAddr(string(abi.encodePacked("voter", i)));
            vm.prank(admin);
            proxyAsVotingSystem.registerVoter(voters[i]);
        }

        assertEq(proxyAsVotingSystem.voterCount(), bounded);
    }

    // ============ Edge Case Tests ============

    function test_voteAfterEndTime_reverts() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);

        // Vote during period
        _advanceToVoting;
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        // Try to vote after end
        vm.warp(block.timestamp + duration + 1);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(VotingSystem.VotingEnded.selector, proposalId));
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
    }

    function test_multipleVoters_sameProposal() public {
        uint256 proposalId = _setupWithProposal();
        _setupVoters(proposalId);
        _advanceToVoting;

        // All users vote
        vm.prank(user1);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
        vm.prank(user2);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
        vm.prank(user3);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertEq(proposal.totalVotes, 3);
    }

    function test_quorumReached() public {
        // Register more voters
        address[] memory voters = new address[](7);
        for (uint256 i = 0; i < 7; i++) {
            voters[i] = makeAddr(string(abi.encodePacked("newVoter", i)));
        }
        vm.prank(admin);
        proxyAsVotingSystem.batchRegisterVoters(voters);

        // Create proposal with higher quorum
        uint256 proposalId = _setupWithProposal();
        vm.prank(admin);
        proxyAsVotingSystem.setQuorum(proposalId, 3);

        _advanceToVoting;

        // 3 voters vote (reaches quorum)
        vm.prank(voters[0]);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
        vm.prank(voters[1]);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);
        vm.prank(voters[2]);
        proxyAsVotingSystem.castSingleVote(proposalId, 0);

        VotingSystem.ProposalInfo memory proposal = proxyAsVotingSystem.getProposal(proposalId);
        assertTrue(proposal.totalVotes >= proposal.quorum);
    }
}
