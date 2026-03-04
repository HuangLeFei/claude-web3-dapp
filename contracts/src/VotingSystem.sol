// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title VotingSystem
/// @author D-Vote
/// @notice Decentralized Voting System for transparent and immutable on-chain voting
/// @dev UUPS upgradeable contract supporting multiple voting mechanisms
contract VotingSystem is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // ============ Type Definitions ============

    /// @notice Voting mechanism types
    enum VotingType {
        SingleChoice,      // Select one candidate
        MultiChoice,       // Select multiple candidates
        RankedChoice,      // Rank candidates by preference
        WeightedChoice     // Weighted voting based on token holdings
    }

    /// @notice Proposal lifecycle states
    enum ProposalStatus {
        Pending,       // Not yet started
        Active,        // Currently accepting votes
        Ended,         // Voting completed
        Cancelled      // Cancelled by admin
    }

    /// @notice Voter information structure
    struct VoterInfo {
        bool isRegistered;
        bool isEligible;
        uint256 registrationTime;
        uint256 votesCast;
        mapping(uint256 => bool) hasVoted;
        uint256 reputationScore;
    }

    /// @notice Candidate information structure
    struct CandidateInfo {
        address candidateAddress;
        uint256 voteWeight;
        uint256 voteCount;
        string metadata;
    }

    /// @notice Proposal information structure
    struct ProposalInfo {
        uint256 id;
        address creator;
        string title;
        string description;
        uint64 startTime;
        uint64 endTime;
        uint16 candidateCount;
        bool isRanked;
        bool isMultiChoice;
        bool isActive;
        VotingType votingType;
        ProposalStatus status;
        bool resultsPublished;
        uint256 totalVotes;
        uint256 quorum;
    }

    /// @notice Vote data structure
    struct VoteData {
        uint256[] candidateIndices;
        uint256[] rankings;
        uint256 timestamp;
        bool isRevealed;
    }

    /// @notice Candidate result structure
    struct CandidateResult {
        uint256 candidateIndex;
        uint256 voteCount;
        uint256 weightedVotes;
        uint256 ranking;
    }

    // ============ Errors ============

    error VoterAlreadyRegistered(address voter);
    error VoterNotRegistered(address voter);
    error ProposalDoesNotExist(uint256 proposalId);
    error ProposalNotActive(uint256 proposalId);
    error VotingNotStarted(uint256 proposalId);
    error VotingEnded(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InvalidCandidateIndex(uint256 proposalId, uint256 index);
    error InsufficientVotes(uint256 proposalId, uint256 required, uint256 actual);
    error ContractIsPaused();
    error ContractNotPaused();
    error Unauthorized(address caller, bytes32 requiredRole);
    error InvalidCommitment();
    error ArrayLengthMismatch();
    error InvalidTimeRange();
    error ZeroAddress();
    error TooManyCandidates();
    error NotCommitted(uint256 proposalId, address voter);
    error CommitmentExpired(uint256 proposalId, address voter);

    // ============ Role Definitions ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // ============ State Variables ============

    /// @notice Voter information mapping
    mapping(address => VoterInfo) public voters;

    /// @notice List of registered voter addresses
    address[] public voterList;

    /// @notice Total number of registered voters
    uint256 public voterCount;

    /// @notice Proposal information mapping
    mapping(uint256 => ProposalInfo) public proposals;

    /// @notice Candidates for each proposal
    mapping(uint256 => CandidateInfo[]) public proposalCandidates;

    /// @notice Total number of proposals
    uint256 public proposalCount;

    /// @notice List of active proposal IDs
    uint256[] public activeProposals;

    /// @notice Vote data for each proposal and voter
    mapping(uint256 => mapping(address => VoteData)) public votes;

    /// @notice Results for each proposal
    mapping(uint256 => CandidateResult[]) public proposalResults;

    /// @notice Commit hashes for reveal phase
    mapping(uint256 => mapping(address => bytes32)) public commitHashes;

    /// @notice Commit timestamps for reveal phase
    mapping(uint256 => mapping(address => uint256)) public commitTimestamps;

    /// @notice Oracle address for voter verification
    address public voterOracle;

    /// @notice Default voting delay in seconds
    uint256 public votingDelay;

    /// @notice Default voting duration in seconds
    uint256 public votingDuration;

    /// @notice Minimum number of voters required
    uint256 public minVoters;

    /// @notice Maximum reveal period after voting ends (7 days)
    uint256 public constant REVEAL_PERIOD = 7 days;

    /// @notice Maximum candidates per proposal
    uint16 public constant MAX_CANDIDATES = 256;

    // ============ Events ============

    /// @notice Emitted when a voter is registered
    event VoterRegistered(
        address indexed voter,
        uint256 indexed timestamp,
        uint256 totalVoters
    );

    /// @notice Emitted when a voter is removed
    event VoterRemoved(
        address indexed voter,
        uint256 indexed timestamp,
        uint256 remainingVoters
    );

    /// @notice Emitted when a proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        string title,
        uint256 startTime,
        uint256 endTime,
        VotingType votingType
    );

    /// @notice Emitted when a candidate is added
    event CandidateAdded(
        uint256 indexed proposalId,
        address indexed candidate,
        uint256 weight,
        uint256 candidateIndex
    );

    /// @notice Emitted when a vote is cast
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256[] candidateIndices,
        uint256 timestamp
    );

    /// @notice Emitted when a vote commitment is made
    event VoteCommitted(
        uint256 indexed proposalId,
        address indexed voter,
        bytes32 commitmentHash,
        uint256 timestamp
    );

    /// @notice Emitted when a vote is revealed
    event VoteRevealed(
        uint256 indexed proposalId,
        address indexed voter,
        uint256[] candidateIndices,
        uint256 timestamp
    );

    /// @notice Emitted when a proposal ends
    event ProposalEnded(
        uint256 indexed proposalId,
        uint256 totalVotes,
        uint256 quorum,
        bool quorumReached
    );

    /// @notice Emitted when results are published
    event ResultsPublished(
        uint256 indexed proposalId,
        uint256 winningCandidate,
        uint256 winningVotes,
        CandidateResult[] results
    );

    /// @notice Emitted when contract is paused
    event ContractPaused(address indexed admin, uint256 timestamp);

    /// @notice Emitted when contract is unpaused
    event ContractUnpaused(address indexed admin, uint256 timestamp);

    /// @notice Emitted when contract upgrade is scheduled
    event UpgradeScheduled(
        address indexed currentImpl,
        address indexed newImpl,
        uint256 timestamp
    );

    // ============ Modifiers ============

    /// @notice Restrict to admin role
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender, ADMIN_ROLE);
        }
        _;
    }

    /// @notice Restrict to emergency admin role
    modifier onlyEmergencyAdmin() {
        if (!hasRole(EMERGENCY_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender, EMERGENCY_ROLE);
        }
        _;
    }

    /// @notice Restrict to auditor role
    modifier onlyAuditor() {
        if (!hasRole(AUDITOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender, AUDITOR_ROLE);
        }
        _;
    }

    /// @notice Check if proposal exists
    modifier proposalExists(uint256 proposalId) {
        if (proposalId >= proposalCount) {
            revert ProposalDoesNotExist(proposalId);
        }
        _;
    }

    /// @notice Check if proposal is active
    modifier proposalActive(uint256 proposalId) {
        ProposalInfo storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Active) {
            revert ProposalNotActive(proposalId);
        }
        if (block.timestamp < proposal.startTime) {
            revert VotingNotStarted(proposalId);
        }
        if (block.timestamp >= proposal.endTime) {
            revert VotingEnded(proposalId);
        }
        _;
    }

    /// @notice Check if caller is a registered voter
    modifier onlyRegisteredVoter() {
        if (!voters[msg.sender].isRegistered) {
            revert VoterNotRegistered(msg.sender);
        }
        _;
    }

    /// @notice Check if caller has not voted on proposal
    modifier hasNotVoted(uint256 proposalId) {
        if (voters[msg.sender].hasVoted[proposalId]) {
            revert AlreadyVoted(msg.sender, proposalId);
        }
        _;
    }

    // ============ Constructor ============

    /// @notice Disable direct initialization of implementation contract
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /// @notice Initialize the voting system
    /// @param _admin Admin address
    /// @param _emergencyAdmin Emergency admin address
    /// @param _auditor Auditor address
    function initialize(
        address _admin,
        address _emergencyAdmin,
        address _auditor
    ) external initializer {
        if (_admin == address(0)) revert ZeroAddress();
        if (_emergencyAdmin == address(0)) revert ZeroAddress();
        if (_auditor == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        // Grant roles
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _emergencyAdmin);
        _grantRole(AUDITOR_ROLE, _auditor);

        // Set role admin to admin
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(AUDITOR_ROLE, ADMIN_ROLE);

        // Set default values
        votingDelay = 0;
        votingDuration = 7 days;
        minVoters = 10;
    }

    // ============ Voter Management ============

    /// @notice Register a single voter
    /// @param voter Voter address to register
    function registerVoter(address voter)
        external
        onlyAdmin
        whenNotPaused
    {
        if (voter == address(0)) revert ZeroAddress();
        if (voters[voter].isRegistered) revert VoterAlreadyRegistered(voter);

        _registerVoter(voter);
    }

    /// @notice Register multiple voters in batch
    /// @param voterAddresses Array of voter addresses
    function batchRegisterVoters(address[] calldata voterAddresses)
        external
        onlyAdmin
        whenNotPaused
    {
        uint256 length = voterAddresses.length;
        if (length == 0) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < length; i++) {
            address voter = voterAddresses[i];
            if (voter == address(0)) revert ZeroAddress();
            if (!voters[voter].isRegistered) {
                _registerVoter(voter);
            }
        }
    }

    /// @notice Internal function to register a voter
    /// @param voter Voter address
    function _registerVoter(address voter) internal {
        voters[voter].isRegistered = true;
        voters[voter].isEligible = true;
        voters[voter].registrationTime = block.timestamp;
        voters[voter].votesCast = 0;
        voters[voter].reputationScore = 100; // Default reputation

        voterList.push(voter);
        voterCount++;

        emit VoterRegistered(voter, block.timestamp, voterCount);
    }

    /// @notice Remove a voter
    /// @param voter Voter address to remove
    function removeVoter(address voter)
        external
        onlyAdmin
        whenNotPaused
    {
        if (!voters[voter].isRegistered) revert VoterNotRegistered(voter);

        voters[voter].isRegistered = false;
        voters[voter].isEligible = false;
        voterCount--;

        emit VoterRemoved(voter, block.timestamp, voterCount);
    }

    // ============ Proposal Management ============

    /// @notice Create a new proposal
    /// @param title Proposal title
    /// @param description Proposal description
    /// @param startTime Voting start time
    /// @param duration Voting duration in seconds
    /// @param votingType Type of voting
    /// @param quorum Minimum votes required
    /// @return proposalId ID of created proposal
    function createProposal(
        string memory title,
        string memory description,
        uint64 startTime,
        uint256 duration,
        VotingType votingType,
        uint256 quorum
    )
        external
        onlyAdmin
        whenNotPaused
        returns (uint256 proposalId)
    {
        if (startTime == 0) revert InvalidTimeRange();
        if (duration == 0) revert InvalidTimeRange();
        if (startTime <= uint64(block.timestamp)) revert InvalidTimeRange();
        if (quorum == 0) revert InvalidTimeRange();
        if (quorum > minVoters) revert InsufficientVotes(0, quorum, minVoters);

        proposalId = proposalCount;
        uint64 endTime = startTime + uint64(duration);

        proposals[proposalId] = ProposalInfo({
            id: proposalId,
            creator: msg.sender,
            title: title,
            description: description,
            startTime: startTime,
            endTime: endTime,
            candidateCount: 0,
            isRanked: votingType == VotingType.RankedChoice,
            isMultiChoice: votingType == VotingType.MultiChoice,
            isActive: true,
            votingType: votingType,
            status: ProposalStatus.Pending,
            resultsPublished: false,
            totalVotes: 0,
            quorum: quorum
        });

        activeProposals.push(proposalId);
        proposalCount++;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            title,
            startTime,
            endTime,
            votingType
        );
    }

    /// @notice Add a candidate to a proposal
    /// @param proposalId Proposal ID
    /// @param candidate Candidate address
    /// @param weight Candidate weight
    function addCandidate(
        uint256 proposalId,
        address candidate,
        uint256 weight
    )
        external
        onlyAdmin
        proposalExists(proposalId)
        whenNotPaused
    {
        if (candidate == address(0)) revert ZeroAddress();
        if (weight == 0) revert InvalidCandidateIndex(proposalId, weight);

        ProposalInfo storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) {
            revert ProposalNotActive(proposalId);
        }

        if (proposal.candidateCount >= MAX_CANDIDATES) {
            revert TooManyCandidates();
        }

        proposalCandidates[proposalId].push(CandidateInfo({
            candidateAddress: candidate,
            voteWeight: weight,
            voteCount: 0,
            metadata: ""
        }));

        uint256 candidateIndex = proposal.candidateCount;
        proposal.candidateCount++;

        emit CandidateAdded(proposalId, candidate, weight, candidateIndex);
    }

    /// @notice Add multiple candidates to a proposal
    /// @param proposalId Proposal ID
    /// @param candidates Array of candidate addresses
    /// @param weights Array of candidate weights
    function batchAddCandidates(
        uint256 proposalId,
        address[] calldata candidates,
        uint256[] calldata weights
    )
        external
        onlyAdmin
        proposalExists(proposalId)
        whenNotPaused
    {
        uint256 length = candidates.length;
        if (length == 0) revert ArrayLengthMismatch();
        if (length != weights.length) revert ArrayLengthMismatch();

        ProposalInfo storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) {
            revert ProposalNotActive(proposalId);
        }

        for (uint256 i = 0; i < length; i++) {
            address candidate = candidates[i];
            uint256 weight = weights[i];

            if (candidate == address(0)) revert ZeroAddress();
            if (weight == 0) revert InvalidCandidateIndex(proposalId, weight);

            if (proposal.candidateCount >= MAX_CANDIDATES) {
                revert TooManyCandidates();
            }

            proposalCandidates[proposalId].push(CandidateInfo({
                candidateAddress: candidate,
                voteWeight: weight,
                voteCount: 0,
                metadata: ""
            }));

            uint256 candidateIndex = proposal.candidateCount;
            proposal.candidateCount++;

            emit CandidateAdded(proposalId, candidate, weight, candidateIndex);
        }
    }

    // ============ Voting Functions ============

    /// @notice Cast a single vote for a candidate
    /// @param proposalId Proposal ID
    /// @param candidateIndex Index of candidate
    function castSingleVote(
        uint256 proposalId,
        uint256 candidateIndex
    )
        external
        nonReentrant
        onlyRegisteredVoter
        proposalExists(proposalId)
        proposalActive(proposalId)
        hasNotVoted(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        if (proposal.votingType != VotingType.SingleChoice) {
            revert ProposalNotActive(proposalId);
        }

        if (candidateIndex >= proposal.candidateCount) {
            revert InvalidCandidateIndex(proposalId, candidateIndex);
        }

        // Record vote
        uint256[] memory indices = new uint256[](1);
        indices[0] = candidateIndex;
        votes[proposalId][msg.sender] = VoteData({
            candidateIndices: indices,
            rankings: new uint256[](0),
            timestamp: block.timestamp,
            isRevealed: true
        });

        voters[msg.sender].hasVoted[proposalId] = true;
        voters[msg.sender].votesCast++;
        proposal.totalVotes++;

        // Update candidate vote count
        proposalCandidates[proposalId][candidateIndex].voteCount++;

        emit VoteCast(proposalId, msg.sender, indices, block.timestamp);
    }

    /// @notice Cast multiple votes
    /// @param proposalId Proposal ID
    /// @param candidateIndices Array of candidate indices
    function castMultiVote(
        uint256 proposalId,
        uint256[] calldata candidateIndices
    )
        external
        nonReentrant
        onlyRegisteredVoter
        proposalExists(proposalId)
        proposalActive(proposalId)
        hasNotVoted(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        if (proposal.votingType != VotingType.MultiChoice) {
            revert ProposalNotActive(proposalId);
        }

        uint256 length = candidateIndices.length;
        if (length == 0 || length > proposal.candidateCount) {
            revert ArrayLengthMismatch();
        }

        // Validate all candidate indices
        for (uint256 i = 0; i < length; i++) {
            if (candidateIndices[i] >= proposal.candidateCount) {
                revert InvalidCandidateIndex(proposalId, candidateIndices[i]);
            }
        }

        // Record vote
        votes[proposalId][msg.sender] = VoteData({
            candidateIndices: candidateIndices,
            rankings: new uint256[](0),
            timestamp: block.timestamp,
            isRevealed: true
        });

        voters[msg.sender].hasVoted[proposalId] = true;
        voters[msg.sender].votesCast++;
        proposal.totalVotes++;

        // Update candidate vote counts
        for (uint256 i = 0; i < length; i++) {
            proposalCandidates[proposalId][candidateIndices[i]].voteCount++;
        }

        emit VoteCast(proposalId, msg.sender, candidateIndices, block.timestamp);
    }

    /// @notice Cast a ranked vote
    /// @param proposalId Proposal ID
    /// @param rankings Array where index is rank and value is candidate index
    function castRankedVote(
        uint256 proposalId,
        uint256[] calldata rankings
    )
        external
        nonReentrant
        onlyRegisteredVoter
        proposalExists(proposalId)
        proposalActive(proposalId)
        hasNotVoted(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        if (proposal.votingType != VotingType.RankedChoice) {
            revert ProposalNotActive(proposalId);
        }

        uint256 length = rankings.length;
        if (length == 0 || length > proposal.candidateCount) {
            revert ArrayLengthMismatch();
        }

        // Validate all rankings are unique and within bounds
        bool[] memory seen = new bool[](proposal.candidateCount);
        for (uint256 i = 0; i < length; i++) {
            if (rankings[i] >= proposal.candidateCount) {
                revert InvalidCandidateIndex(proposalId, rankings[i]);
            }
            if (seen[rankings[i]]) revert InvalidCandidateIndex(proposalId, rankings[i]);
            seen[rankings[i]] = true;
        }

        // Record vote
        votes[proposalId][msg.sender] = VoteData({
            candidateIndices: rankings,
            rankings: rankings,
            timestamp: block.timestamp,
            isRevealed: true
        });

        voters[msg.sender].hasVoted[proposalId] = true;
        voters[msg.sender].votesCast++;
        proposal.totalVotes++;

        // Update candidate vote counts (first choice gets full vote)
        proposalCandidates[proposalId][rankings[0]].voteCount++;

        emit VoteCast(proposalId, msg.sender, rankings, block.timestamp);
    }

    // ============ Commit-Reveal ============

    /// @notice Commit a vote hash (first phase of commit-reveal)
    /// @param proposalId Proposal ID
    /// @param commitmentHash Hash of vote data and nonce
    function commitVote(
        uint256 proposalId,
        bytes32 commitmentHash
    )
        external
        nonReentrant
        onlyRegisteredVoter
        proposalExists(proposalId)
        proposalActive(proposalId)
        whenNotPaused
    {
        if (commitmentHash == bytes32(0)) revert InvalidCommitment();

        // Store commitment
        commitHashes[proposalId][msg.sender] = commitmentHash;
        commitTimestamps[proposalId][msg.sender] = block.timestamp;

        emit VoteCommitted(proposalId, msg.sender, commitmentHash, block.timestamp);
    }

    /// @notice Reveal a committed vote (second phase)
    /// @param proposalId Proposal ID
    /// @param candidateIndices Array of candidate indices
    /// @param nonce Random nonce used in commitment
    function revealVote(
        uint256 proposalId,
        uint256[] calldata candidateIndices,
        uint256 nonce
    )
        external
        nonReentrant
        onlyRegisteredVoter
        proposalExists(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        // Check if committed
        bytes32 storedHash = commitHashes[proposalId][msg.sender];
        if (storedHash == bytes32(0)) {
            revert NotCommitted(proposalId, msg.sender);
        }

        // Check if reveal period expired
        uint256 commitTime = commitTimestamps[proposalId][msg.sender];
        if (block.timestamp > proposal.endTime + REVEAL_PERIOD) {
            revert CommitmentExpired(proposalId, msg.sender);
        }

        // Verify commitment
        bytes32 computedHash = keccak256(abi.encodePacked(candidateIndices, nonce));
        if (computedHash != storedHash) {
            revert InvalidCommitment();
        }

        // Check if already revealed
        if (votes[proposalId][msg.sender].timestamp != 0) {
            revert AlreadyVoted(msg.sender, proposalId);
        }

        // Record vote
        votes[proposalId][msg.sender] = VoteData({
            candidateIndices: candidateIndices,
            rankings: new uint256[](0),
            timestamp: commitTime, // Use commit timestamp
            isRevealed: true
        });

        voters[msg.sender].hasVoted[proposalId] = true;
        voters[msg.sender].votesCast++;
        proposal.totalVotes++;

        // Update candidate vote counts
        for (uint256 i = 0; i < candidateIndices.length; i++) {
            uint256 candidateIndex = candidateIndices[i];
            if (candidateIndex < proposal.candidateCount) {
                proposalCandidates[proposalId][candidateIndex].voteCount++;
            }
        }

        // Clear commitment
        delete commitHashes[proposalId][msg.sender];
        delete commitTimestamps[proposalId][msg.sender];

        emit VoteRevealed(proposalId, msg.sender, candidateIndices, block.timestamp);
    }

    // ============ Result Management ============

    /// @notice End a proposal and calculate results
    /// @param proposalId Proposal ID
    /// @param shouldPublishResults Whether to publish results immediately
    function endProposal(
        uint256 proposalId,
        bool shouldPublishResults
    )
        external
        onlyAdmin
        proposalExists(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        // Check if voting has ended
        if (proposal.status != ProposalStatus.Active) {
            revert ProposalNotActive(proposalId);
        }

        if (block.timestamp < proposal.endTime) {
            revert VotingNotStarted(proposalId);
        }

        // Update proposal status
        proposal.status = ProposalStatus.Ended;

        // Check quorum
        bool quorumReached = proposal.totalVotes >= proposal.quorum;

        emit ProposalEnded(
            proposalId,
            proposal.totalVotes,
            proposal.quorum,
            quorumReached
        );

        // Publish results if requested
        if (shouldPublishResults) {
            _publishResults(proposalId);
        }
    }

    /// @notice Publish results for a proposal
    /// @param proposalId Proposal ID
    function publishResults(uint256 proposalId)
        external
        onlyAdmin
        proposalExists(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];

        if (proposal.status != ProposalStatus.Ended) {
            revert ProposalNotActive(proposalId);
        }

        if (proposal.resultsPublished) {
            return; // Already published
        }

        _publishResults(proposalId);
    }

    /// @notice Internal function to publish results
    /// @param proposalId Proposal ID
    function _publishResults(uint256 proposalId) internal {
        ProposalInfo storage proposal = proposals[proposalId];
        CandidateInfo[] storage candidates = proposalCandidates[proposalId];

        // Calculate results
        CandidateResult[] memory results = new CandidateResult[](proposal.candidateCount);

        uint256 maxVotes = 0;
        uint256 winningCandidate = 0;

        for (uint256 i = 0; i < proposal.candidateCount; i++) {
            CandidateInfo storage candidate = candidates[i];

            results[i] = CandidateResult({
                candidateIndex: i,
                voteCount: candidate.voteCount,
                weightedVotes: candidate.voteCount * candidate.voteWeight,
                ranking: 0
            });

            // Track winner
            if (candidate.voteCount > maxVotes) {
                maxVotes = candidate.voteCount;
                winningCandidate = i;
            }
        }

        // Sort by weighted votes and assign rankings
        _sortResults(results);

        // Store results one by one
        for (uint256 i = 0; i < results.length; i++) {
            proposalResults[proposalId].push(results[i]);
        }
        proposal.resultsPublished = true;

        emit ResultsPublished(proposalId, winningCandidate, maxVotes, results);
    }

    /// @notice Internal function to sort results by weighted votes
    /// @param results Results array to sort
    function _sortResults(CandidateResult[] memory results) internal pure {
        uint256 n = results.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (results[j].weightedVotes < results[j + 1].weightedVotes) {
                    // Swap
                    CandidateResult memory temp = results[j];
                    results[j] = results[j + 1];
                    results[j + 1] = temp;
                }
            }
            results[i].ranking = i + 1;
        }
        results[n - 1].ranking = n;
    }

    // ============ Query Functions ============

    /// @notice Get proposal results
    /// @param proposalId Proposal ID
    /// @return results Array of candidate results
    function getProposalResults(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (CandidateResult[] memory results)
    {
        return proposalResults[proposalId];
    }

    /// @notice Get proposal details
    /// @param proposalId Proposal ID
    /// @return proposal Proposal information
    function getProposal(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (ProposalInfo memory proposal)
    {
        return proposals[proposalId];
    }

    /// @notice Get candidates for a proposal
    /// @param proposalId Proposal ID
    /// @return candidates Array of candidate information
    function getProposalCandidates(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (CandidateInfo[] memory candidates)
    {
        return proposalCandidates[proposalId];
    }

    /// @notice Get voting history for a voter
    /// @param voter Voter address
    /// @return votedProposalIds Array of proposal IDs the voter has voted on
    function getVoterVotingHistory(address voter)
        external
        view
        returns (uint256[] memory votedProposalIds)
    {
        uint256 count = 0;

        // Count voted proposals
        for (uint256 i = 0; i < proposalCount; i++) {
            if (voters[voter].hasVoted[i]) {
                count++;
            }
        }

        // Build array
        votedProposalIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposalCount; i++) {
            if (voters[voter].hasVoted[i]) {
                votedProposalIds[index] = i;
                index++;
            }
        }
    }

    /// @notice Get list of active proposals
    /// @return activeProposalIds Array of active proposal IDs
    function getActiveProposals()
        external
        view
        returns (uint256[] memory activeProposalIds)
    {
        return activeProposals;
    }

    /// @notice Get all proposal IDs
    /// @return allProposalIds Array of all proposal IDs
    function getAllProposals()
        external
        view
        returns (uint256[] memory allProposalIds)
    {
        allProposalIds = new uint256[](proposalCount);
        for (uint256 i = 0; i < proposalCount; i++) {
            allProposalIds[i] = i;
        }
    }

    // ============ Emergency Controls ============

    /// @notice Pause the contract
    function pause() external onlyEmergencyAdmin whenNotPaused {
        _pause();
        emit ContractPaused(msg.sender, block.timestamp);
    }

    /// @notice Unpause the contract
    function unpause() external onlyEmergencyAdmin whenPaused {
        _unpause();
        emit ContractUnpaused(msg.sender, block.timestamp);
    }

    // ============ Configuration ============

    /// @notice Set the voter oracle address
    /// @param _oracle Oracle address
    function setOracle(address _oracle)
        external
        onlyAdmin
        whenNotPaused
    {
        voterOracle = _oracle;
    }

    /// @notice Set the voting delay
    /// @param delay Delay in seconds
    function setVotingDelay(uint256 delay)
        external
        onlyAdmin
        whenNotPaused
    {
        votingDelay = delay;
    }

    /// @notice Set the voting duration
    /// @param duration Duration in seconds
    function setVotingDuration(uint256 duration)
        external
        onlyAdmin
        whenNotPaused
    {
        votingDuration = duration;
    }

    /// @notice Set the quorum for a proposal
    /// @param proposalId Proposal ID
    /// @param quorum Minimum votes required
    function setQuorum(uint256 proposalId, uint256 quorum)
        external
        onlyAdmin
        proposalExists(proposalId)
        whenNotPaused
    {
        ProposalInfo storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) {
            revert ProposalNotActive(proposalId);
        }
        proposal.quorum = quorum;
    }

    // ============ Audit Functions ============

    /// @notice Verify results for a proposal (auditor only)
    /// @param proposalId Proposal ID
    /// @return valid Whether results are valid
    function verifyResults(uint256 proposalId)
        external
        onlyAuditor
        proposalExists(proposalId)
        returns (bool valid)
    {
        ProposalInfo storage proposal = proposals[proposalId];

        // Check if proposal ended and results published
        if (proposal.status != ProposalStatus.Ended) {
            return false;
        }

        if (!proposal.resultsPublished) {
            return false;
        }

        // Check quorum
        if (proposal.totalVotes < proposal.quorum) {
            return false;
        }

        // Check vote counts match
        CandidateResult[] memory results = proposalResults[proposalId];
        CandidateInfo[] storage candidates = proposalCandidates[proposalId];

        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].voteCount != candidates[results[i].candidateIndex].voteCount) {
                return false;
            }
        }

        return true;
    }

    // ============ Upgrade Functions ============

    /// @notice Authorize contract upgrade
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyAdmin
    {
        if (paused()) {
            revert ContractIsPaused();
        }

        emit UpgradeScheduled(address(this), newImplementation, block.timestamp);
    }

    /// @notice Get voter info by address
    /// @param voter Voter address
    /// @return isRegistered Whether registered
    /// @return isEligible Whether eligible
    /// @return registrationTime Registration timestamp
    /// @return votesCast Number of votes cast
    /// @return reputationScore Reputation score
    function getVoterInfo(address voter)
        external
        view
        returns (
            bool isRegistered,
            bool isEligible,
            uint256 registrationTime,
            uint256 votesCast,
            uint256 reputationScore
        )
    {
        VoterInfo storage info = voters[voter];
        return (
            info.isRegistered,
            info.isEligible,
            info.registrationTime,
            info.votesCast,
            info.reputationScore
        );
    }

    /// @notice Check if voter has voted on proposal
    /// @param voter Voter address
    /// @param proposalId Proposal ID
    /// @return hasVoted Whether voter has voted
    function hasVotedOnProposal(address voter, uint256 proposalId)
        external
        view
        returns (bool hasVoted)
    {
        return voters[voter].hasVoted[proposalId];
    }

    // ============ Storage Gap ============

    /// @notice Reserved storage slots for future upgrades
    uint256[50] private __gap;
}
