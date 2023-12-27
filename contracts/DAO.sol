// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./INftMarketplace.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title CollectorDao
/// @notice A DAO for collectors to pool their funds and buy NFTs
contract DAO is IERC721Receiver  {

    uint256 public constant PRICE = 1 ether;
    uint256 public constant DURATION = 7 days;
    uint256 public constant REWARD = 0.01 ether;
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");
    string public constant NAME = "CollectorDao";

    uint256 public immutable chainId;

    uint256 public totalMembers;

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

    struct Member {
        uint256 votingPower;
        uint256 timeJoined;
    }

    enum ProposalState {
        Nonexistent,
        Active,
        Succeeded,
        Executed,
        Failed
    }

    mapping (uint => Proposal) public proposals;
    mapping(address => Member) public members;

    event MembershipBought(address indexed member);
    event ProposalCreated(uint256 indexed proposalId);
    event VoteCasted(uint256 indexed id, address indexed member, bool indexed support);
    event ProposalExecuted(uint256 indexed proposalId);
    event NftPurchased(address indexed nftContract, uint256 indexed nftId, uint256 indexed nftPrice);

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
    error ProposalStillActive(uint256 deadline);
    error AlreadyExecuted();
    error ProposalDidNotSucceed();
    error CallRevertedWithoutMessage();
    error MustBeCalledByCollector();
    error TooExpensive(uint256 price, uint256 maxPrice);
    error ErrorBuying();

    /// @notice Sets the chainId
    constructor() {
        chainId = block.chainid;
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

    /// @notice Casts a vote on a proposal using a signature
    /// @param _proposalId The id of the proposal
    /// @param _support Whether to support the proposal or not
    /// @param _v The v part of the signature
    /// @param _r The r part of the signature
    /// @param _s The s part of the signature
    function castVoteBySig(uint256 _proposalId, bool _support, uint8 _v, bytes32 _r, bytes32 _s) external {
        _castVoteBySig(_proposalId, _support, _v, _r, _s);
    }

    /// @notice Executes a proposal and caller gets a reward
    /// @param _targets The addresses of the contracts to call
    /// @param _values The values to send to the contracts
    /// @param _calldatas The calldatas to send to the contracts
    /// @param _description The description of the proposal
    /// @dev The execution does not revert if the eth transfer fails
    function executeProposal(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _calldatas,
        bytes32 _description
    )
        external
    {
        uint256 proposalId = hashProposal(_targets, _values, _calldatas, _description);
        Proposal storage p = proposals[proposalId];
        if (getProposalStatus(proposalId) == ProposalState.Active) {
            revert ProposalStillActive(p.end);
        }
        if (getProposalStatus(proposalId) == ProposalState.Executed) {
            revert AlreadyExecuted();
        }
        if (getProposalStatus(proposalId) != ProposalState.Succeeded) {
            revert ProposalDidNotSucceed();
        }


        p.executed = true;
        Member storage m = members[p.creator];
        m.votingPower++;
        emit ProposalExecuted(proposalId);

        for (uint i = 0; i < _targets.length; i++) {
            (bool success, bytes memory returndata ) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                }
                else {
                    revert CallRevertedWithoutMessage();
                }
            }
        }

        msg.sender.call{value: REWARD}("");
    }

    /// @notice Purchases an NFT for the DAO
    /// @param _marketplace The address of the INftMarketplace
    /// @param _nftContract The address of the NFT contract to purchase
    /// @param _nftId The token ID on the nftContract to purchase
    /// @param _maxPrice The price above which the NFT is deemed too expensive and this function call should fail
    function buyNFTFromMarketplace(
        INftMarketplace _marketplace,
        address _nftContract,
        uint256 _nftId,
        uint256 _maxPrice
    )
        external
    {
        if (msg.sender != address(this)) {
            revert MustBeCalledByCollector();
        }
        uint256 price = _marketplace.getPrice(_nftContract, _nftId);
        if (price > _maxPrice) {
            revert TooExpensive(price, _maxPrice);
        }

        if (!_marketplace.buy{value: price}(_nftContract, _nftId)) {
            revert ErrorBuying();
        }
        emit NftPurchased(_nftContract, _nftId, price);

    }

    /// @notice Receives an NFT
    /// @dev This function is needed to receive NFTs from the marketplace
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
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

    /// @notice Hashes a proposal
    /// @param _targets The addresses of the contracts to call
    /// @param _values The values to send to the contracts
    /// @param _calldatas The calldatas to send to the contracts
    /// @param _description The description of the proposal
    /// @return The hash of the proposal
    function hashProposal(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _calldatas,
        bytes32 _description
    )
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(_targets, _values, _calldatas, _description)));
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
}
