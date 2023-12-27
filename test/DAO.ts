import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { DAO__factory, DAO } from '../typechain-types';
import { time } from '@nomicfoundation/hardhat-toolbox/network-helpers';

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
});
