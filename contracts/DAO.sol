// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./NftMarketplace.sol";

contract DAO {

    struct Proposal {
        uint id;
        uint startTime;
        uint endTime;
        uint forVotes;
        uint againstVotes;
        address proposer;
        bool executed;
    }

    struct Receipt {
        bool hasVoted;
    }

    enum ProposalState {
        Active,
        NotReady,
        Succeeded,
        Executed
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

    event MembershipBought(address indexed member);

    error WrongAmount(uint256 amount, uint256 price);
    error AlreadyMember();

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

    modifier onlyMember {
        require(isMember[msg.sender], "NOT_A_MEMBER");
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
    

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external onlyMember returns (uint) {

        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(targets.length == values.length, "INVALID_PROPOSAL_LENGTH");
        require(targets.length == values.length, "INVALID_PROPOSAL_LENGTH");
        require(targets.length == calldatas.length, "INVALID_PROPOSAL_LENGTH");

        uint startTime = block.timestamp;
        uint endTime = startTime + VOTING_PERIOD;
        Proposal storage newProposal = proposals[proposalId];
        
        newProposal.id = proposalId;
        newProposal.startTime = startTime;
        newProposal.endTime = endTime;
        newProposal.proposer = msg.sender;
    
        return newProposal.id;
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public onlyMember returns (uint) {

        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        ProposalState status = state(proposalId);
        
        require(status == ProposalState.Succeeded, "PROPOSAL_HAS_NOT_SUCCEEDED");
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

    function state(uint proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.NotReady;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else 
            return ProposalState.Succeeded;
    }

    function castVote(uint proposalId, bool support) onlyMember external {
        require(votingPower[msg.sender] > 0, "NO_VOTING_POWER");
        return _castVote(msg.sender, proposalId, support);
    }

    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "VOTING_CLOSED");
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

    function getProposal(uint x) external view returns (Proposal memory) {
        return proposals[x];
    }

    function getReceipt(address addr, uint x) external view returns (Receipt memory) {
        return receipts[x][addr];
    }

}