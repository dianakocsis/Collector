import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { DAO__factory, DAO } from '../typechain-types';
import { time } from '@nomicfoundation/hardhat-toolbox/network-helpers';
import { BigNumberish, AddressLike, BytesLike } from 'ethers';

type ProposeArgs = [
  targets: AddressLike[],
  values: BigNumberish[],
  calldatas: BytesLike[],
  descriptionHash: BytesLike
];

describe('DAO', function () {
  let CollectorDao: DAO__factory;
  let collectorDao: DAO;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addr3: SignerWithAddress;

  const tokens = (count: string) => ethers.parseUnits(count, 18);

  this.beforeEach(async function () {
    [addr1, addr2, addr3] = await ethers.getSigners();
    CollectorDao = (await ethers.getContractFactory('DAO')) as DAO__factory;
    collectorDao = (await CollectorDao.deploy()) as DAO;
    await collectorDao.waitForDeployment();
  });

  describe('Membership', function () {
    it('1 ether to buy membership', async function () {
      await expect(collectorDao.buyMembership({ value: tokens('1.1') }))
        .to.be.revertedWithCustomError(collectorDao, 'WrongAmount')
        .withArgs(tokens('1.1'), await collectorDao.PRICE());
    });

    it('Cannot buy membership twice', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      await expect(
        collectorDao.buyMembership({ value: tokens('1') })
      ).to.be.revertedWithCustomError(collectorDao, 'AlreadyMember');
    });

    it('Member gets updated properly', async function () {
      let member = await collectorDao.members(addr1.address);
      expect(member.votingPower).to.equal(0);
      expect(member.timeJoined).to.equal(0);
      await collectorDao.buyMembership({ value: tokens('1') });
      member = await collectorDao.members(addr1.address);
      expect(member.votingPower).to.equal(1);
      expect(member.timeJoined).to.equal(await time.latest());
    });

    it('Total members increases', async function () {
      expect(await collectorDao.totalMembers()).to.equal(0);
      await collectorDao.buyMembership({ value: tokens('1') });
      expect(await collectorDao.totalMembers()).to.equal(1);
    });

    it('Event is emitted', async function () {
      const txResponse = await collectorDao.buyMembership({
        value: tokens('1'),
      });
      const tx = await txResponse.wait();
      await expect(tx)
        .to.emit(collectorDao, 'MembershipBought')
        .withArgs(addr1.address);
    });
  });

  describe('Propose', function () {
    it('Only member can create proposal', async function () {
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await expect(
        collectorDao.propose(...proposalArgs)
      ).to.be.revertedWithCustomError(collectorDao, 'OnlyMembers');
    });

    it('Need to pass the same lengths - targets != values', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0'), tokens('1')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await expect(collectorDao.propose(...proposalArgs))
        .to.be.revertedWithCustomError(collectorDao, 'FunctionLengthMismatch')
        .withArgs(1, 2, 1);
    });

    it('Need to pass the same lengths - targets != calldatas', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target, collectorDao.target],
        [tokens('0'), tokens('1')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await expect(collectorDao.propose(...proposalArgs))
        .to.be.revertedWithCustomError(collectorDao, 'FunctionLengthMismatch')
        .withArgs(2, 2, 1);
    });

    it('Updates proposal', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      const proposalId = await collectorDao.hashProposal(...proposalArgs);
      const proposal = await collectorDao.proposals(proposalId);
      expect(proposal.creator).to.equal(addr1.address);
      expect(proposal.start).to.equal(await time.latest());
      let sevenDays = 60 * 60 * 24 * 7;
      expect(proposal.end).to.equal((await time.latest()) + sevenDays);
      expect(proposal.membersTotal).to.equal(1);
      expect(proposal.forVotes).to.equal(0);
      expect(proposal.againstVotes).to.equal(0);
      expect(proposal.voteCount).to.equal(0);
      expect(proposal.executed).to.equal(false);
    });

    it("Can't reset the proposal", async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      await expect(
        collectorDao.propose(...proposalArgs)
      ).to.be.revertedWithCustomError(
        collectorDao,
        'RequireDifferentDescription'
      );
    });

    it('Proposal event is emitted', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      const txResponse = await collectorDao.propose(...proposalArgs);
      const proposalId = await collectorDao.hashProposal(...proposalArgs);
      const tx = await txResponse.wait();
      await expect(tx)
        .to.emit(collectorDao, 'ProposalCreated')
        .withArgs(proposalId);
    });
  });

  describe('Proposal Status', function () {
    it('Nonexistent status', async function () {
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      let status = await collectorDao.getProposalStatus(proposalId);
      expect(status).to.equal(0);
    });

    it('Active Status', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      let status = await collectorDao.getProposalStatus(proposalId);
      expect(status).to.equal(1);
    });
  });

  describe('Cast vote without sig', function () {
    it('Only member can cast vote', async function () {
      await expect(
        collectorDao.castVote(1, true)
      ).to.be.revertedWithCustomError(collectorDao, 'OnlyMembers');
    });

    it('Cannot vote for nonexistent proposal', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      await expect(
        collectorDao.castVote(1, true)
      ).to.be.revertedWithCustomError(collectorDao, 'ProposalNotActive');
    });

    it('Updates proposal after a members votes in support', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      await collectorDao.castVote(proposalId, true);
      let proposal = await collectorDao.proposals(proposalId);
      expect(proposal.forVotes).to.equal(1);
      expect(proposal.voteCount).to.equal(1);
    });

    it('Cannot vote for same proposal more than once', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      await collectorDao.castVote(proposalId, true);
      await expect(
        collectorDao.castVote(proposalId, true)
      ).to.be.revertedWithCustomError(collectorDao, 'AlreadyVoted');
    });

    it('Cannot vote if memebr joined after the proposal was created', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);

      await collectorDao.connect(addr2).buyMembership({ value: tokens('1') });
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      await expect(
        collectorDao.connect(addr2).castVote(proposalId, true)
      ).to.be.revertedWithCustomError(collectorDao, 'MemberJoinedTooLate');
    });

    it('Vote casted event emitted', async function () {
      await collectorDao.buyMembership({ value: tokens('1') });
      let proposalArgs: ProposeArgs = [
        [collectorDao.target],
        [tokens('0')],
        [collectorDao.interface.encodeFunctionData('getProposalStatus', [1])],
        ethers.keccak256(ethers.toUtf8Bytes('Buying something cool')),
      ];
      await collectorDao.propose(...proposalArgs);
      let proposalId = await collectorDao.hashProposal(...proposalArgs);
      const txResponse = await collectorDao.castVote(proposalId, true);
      const tx = await txResponse.wait();
      await expect(tx)
        .to.emit(collectorDao, 'VoteCasted')
        .withArgs(proposalId, addr1.address, true);
    });
  });
});
