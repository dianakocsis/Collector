// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./NftMarketplace.sol";

contract DAO {

    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");
    string public constant NAME = "CollectorDao";

    struct Proposal {
        uint256 start;
        uint256 end;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 voteCount;
        uint256 membersTotal;
        mapping(address => bool) hasVoted;
        address creator;
        bool executed;
    }

    struct Receipt {
        bool hasVoted;
    }

    enum ProposalState {
        Nonexistent,
        Active,
        Succeeded,
        Executed,
        Failed
    }

    struct Member {
        uint256 votingPower;
        uint256 timeJoined;
    }

    uint constant public VOTING_PERIOD = 3 days;
    mapping (uint => Proposal) public proposals;
    mapping (uint => mapping(address => Receipt)) receipts;
    mapping(address=>bool) isMember;
    mapping (address => address) delegatedVote;
    mapping (address => uint256) votingPower;
    mapping (address => uint256) lostVotingPower;
    bool executing;
    bool internal locked;
    uint256 public immutable chainId;
    uint256 public constant PRICE = 1 ether;
    uint256 public totalMembers;
    mapping(address => Member) public members;
    uint256 public constant DURATION = 7 days;



    event MembershipBought(address indexed member);
    event ProposalCreated(uint256 indexed proposalId);
    event VoteCasted(uint256 indexed id, address indexed member, bool indexed support);

    error WrongAmount(uint256 amount, uint256 price);
    error AlreadyMember();
    error OnlyMembers();
    error FunctionLengthMismatch(
        uint256 targetsLength,
        uint256 valuesLength,
        uint256 calldatasLength);
    error RequireDifferentDescription();
    error AlreadyVoted();
    error MemberJoinedTooLate();
    error ProposalNotActive(ProposalState currentStatus);
    error InvalidSignature();
    error SignatureLengthMismatch(uint256 proposalLength, uint256 supportLength,
        uint256 vLength, uint256 rLength, uint256 sLength);

    /// @notice Sets the chainId
    constructor() {
        chainId = block.chainid;
    }

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    /// @notice Checks if the address is a member
    /// @param _addr The address to check
    modifier onlyMember(address _addr) {
        Member memory m = members[_addr];
        if (m.votingPower == 0) {
            revert OnlyMembers();
        }
        _;
    }

    /// @notice Buys a membership for 1 eth to join the dao and get voting power
    function buyMembership() external payable {
        if (msg.value != PRICE) {
            revert WrongAmount(msg.value, PRICE);
        }
        Member storage member = members[msg.sender];
        if (member.votingPower != 0) {
            revert AlreadyMember();
        }

        member.timeJoined = block.timestamp;
        member.votingPower++;
        totalMembers++;
        emit MembershipBought(msg.sender);
    }

    function delegate(address to) external {
        require(votingPower[msg.sender] > 0, "INSUFFICIENT_VOTING_POWER");
        require(isMember[to], "NOT_A_MEMBER");
        while (delegatedVote[to] != address(0)) {
            to = delegatedVote[to];

            require(to != msg.sender, "LOOP_FOUND");
        }
        delegatedVote[msg.sender] = to;
        votingPower[to] += votingPower[msg.sender];
        lostVotingPower[msg.sender] = votingPower[msg.sender];
        votingPower[msg.sender] = 0;
    }

    function undoDelegate() external {
        address to = delegatedVote[msg.sender];
        while (delegatedVote[to] != address(0)) {
            to = delegatedVote[to];
        }
        votingPower[to] -= lostVotingPower[msg.sender];
        votingPower[msg.sender] += lostVotingPower[msg.sender];
        lostVotingPower[msg.sender] = 0;
        delegatedVote[msg.sender] = address(0);
    }

    /// @notice Gets the status of a proposal
    /// @param _proposalId The id of the proposal
    /// @return The status of the proposal
    function getProposalStatus(uint256 _proposalId) public view returns (ProposalState) {
        Proposal storage p = proposals[_proposalId];
        if (p.start == 0) {
            return ProposalState.Nonexistent;
        } else if (block.timestamp < p.end) {
            return ProposalState.Active;
        } else if (p.executed) {
            return ProposalState.Executed;
        } else if (p.forVotes > p.againstVotes && (p.voteCount * 4 > p.membersTotal)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Failed;
        }
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    /// @notice Creates a proposal
    /// @param _targets The addresses of the contracts to call
    /// @param _values The values to send to the contracts
    /// @param _calldatas The calldatas to send to the contracts
    /// @param _description The description of the proposal
    /// @dev The length of the arrays must be the same
    function propose(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _calldatas,
        bytes32 _description
    )
        external
        onlyMember(msg.sender)
    {
        if (_targets.length != _values.length ||
            _targets.length != _calldatas.length) {
            revert FunctionLengthMismatch(_targets.length, _values.length, _calldatas.length);
        }

        uint256 proposalId = hashProposal(_targets, _values, _calldatas, _description);
        Proposal storage p = proposals[proposalId];
        if (p.start != 0) {
            revert RequireDifferentDescription();
        }
        p.start = block.timestamp;
        p.end = block.timestamp + DURATION;
        p.creator = msg.sender;
        p.membersTotal = totalMembers;

        emit ProposalCreated(proposalId);
    }

    /// @notice Casts a vote on a proposal using a signature
    /// @param _proposalId The id of the proposal
    /// @param _support Whether to support the proposal or not
    /// @param _v The v part of the signature
    /// @param _r The r part of the signature
    /// @param _s The s part of the signature
    function castVoteBySig(uint256 _proposalId, bool _support, uint8 _v, bytes32 _r, bytes32 _s) external {
        _castVoteBySig(_proposalId, _support, _v, _r, _s);
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint) {

        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        
        proposals[proposalId].executed = true;

        executing = true;

        _execute(targets, values, calldatas);

        executing = false;

        return proposalId;

    }

    function _execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal virtual {

        string memory errorMessage = "CALL_REVERTED";
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                }
                else {
                    revert(errorMessage);
                }
            }
        }
        
    }

    /// @notice Casts a vote on a proposal
    /// @param _proposalId The id of the proposal
    /// @param _support Whether to support the proposal or not
    function castVote(uint256 _proposalId, bool _support) external {
        _castVote(_proposalId, _support, msg.sender);
    }

    /// @notice Casts votes on proposals using signatures
    /// @param _proposalIds The ids of the proposals
    /// @param _supports Whether to support the proposals or not
    /// @param _vs The v parts of the signatures
    /// @param _rs The r parts of the signatures
    /// @param _ss The s parts of the signatures
    /// @dev The length of the arrays must be the same
    function castVoteBySigBulk(
        uint256[] calldata _proposalIds,
        bool[] calldata _supports,
        uint8[] calldata _vs,
        bytes32[] calldata _rs,
        bytes32[] calldata _ss
    )
        external
    {
        if (_proposalIds.length != _supports.length || _proposalIds.length != _vs.length ||
            _proposalIds.length != _rs.length || _proposalIds.length != _ss.length) {
            revert SignatureLengthMismatch(_proposalIds.length, _supports.length, _vs.length, _rs.length, _ss.length);
        }
        for (uint i = 0; i < _proposalIds.length; i++) {
            _castVoteBySig(_proposalIds[i], _supports[i], _vs[i], _rs[i], _ss[i]);
        }
    }

    /// @notice Casts a vote on a proposal
    /// @param _proposalId The id of the proposal
    /// @param support Whether to support the proposal or not
    /// @param _voter The address of the voter
    function _castVote(uint256 _proposalId, bool support, address _voter) internal onlyMember(_voter) {
        Proposal storage p = proposals[_proposalId];
        Member memory m = members[_voter];

        if (getProposalStatus(_proposalId) != ProposalState.Active) {
            revert ProposalNotActive(getProposalStatus(_proposalId));
        }
        if (p.hasVoted[_voter]) {
            revert AlreadyVoted();
        }
        if (m.timeJoined > p.start) {
            revert MemberJoinedTooLate();
        }
        if (support) {
            p.forVotes += m.votingPower;
        } else {
            p.againstVotes += m.votingPower;
        }
        p.voteCount++;
        p.hasVoted[_voter] = true;
        emit VoteCasted(_proposalId, _voter, support);
    }

    function buyFromNftMarketplace(NftMarketplace marketplace, address nftContract, uint nftId, uint maxPrice) noReentrant external {
        require(executing, "NOT_EXECUTING");
        uint price = marketplace.getPrice(nftContract, nftId);
        require(price <= maxPrice, "INSUFFICIENT_AMOUNT");
        marketplace.buy{ value: price }(nftContract, nftId);
    }

    function getDelegatee(address _addr) external view returns (address) {
       return delegatedVote[_addr];
    }

    function getVotingPower(address _addr) external view returns (uint) {
       return votingPower[_addr];
    }

    function getReceipt(address addr, uint x) external view returns (Receipt memory) {
        return receipts[x][addr];
    }

    /// @notice Casts a vote on a proposal using a signature
    /// @param _proposalId The id of the proposal
    /// @param _support Whether to support the proposal or not
    /// @param _v The v part of the signature
    /// @param _r The r part of the signature
    /// @param _s The s part of the signature
    function _castVoteBySig(uint256 _proposalId, bool _support, uint8 _v, bytes32 _r, bytes32 _s) internal {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                chainId,
                address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, _proposalId, _support));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, _v, _r, _s);
        if (signatory == address(0)) {
            revert InvalidSignature();
        }
        _castVote(_proposalId, _support, signatory);
    }

}