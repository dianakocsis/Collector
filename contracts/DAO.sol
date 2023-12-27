// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./NftMarketplace.sol";

contract DAO {

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

    error WrongAmount(uint256 amount, uint256 price);
    error AlreadyMember();
    error OnlyMembers();
    error FunctionLengthMismatch(
        uint256 targetsLength,
        uint256 valuesLength,
        uint256 calldatasLength);
    error RequireDifferentDescription();

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

    function castVote(uint proposalId, bool support) external {
        require(votingPower[msg.sender] > 0, "NO_VOTING_POWER");
        return _castVote(msg.sender, proposalId, support);
    }

    function _castVote(address voter, uint proposalId, bool support) internal {
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = receipts[proposalId][voter];
        require(receipt.hasVoted == false, "ALREADY_VOTED");
        uint votes = votingPower[voter];

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }

        receipt.hasVoted = true;

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

}