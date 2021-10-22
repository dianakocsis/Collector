const { expect } = require("chai");
const { ethers } = require('hardhat');

describe("DAO.sol", function() {

    let DAO;
    let dao;
    let Marketplace;
    let marketplace;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addr4
    let nft;
    let addrs;

    beforeEach(async function () {

        [owner, addr1, addr2, addr3, addr4, nft, ...addrs] = await ethers.getSigners();
        DAO = await ethers.getContractFactory("DAO");
        dao = await DAO.deploy();

        Marketplace = await ethers.getContractFactory("NFTContract");
        marketplace = await Marketplace.deploy();

    })

    describe("Becoming a member", function () {

        it('Cannot contribute less than 1 ether to become a member', async function () {
            await expect(dao.becomeMember({
                value: ethers.utils.parseEther("0.5")
            })).to.be.revertedWith("ONE_ETHER");
        })

        it('Cannot contribute more than 1 ether to become a member', async function () {
            await expect(dao.becomeMember({
                value: ethers.utils.parseEther("1.5")
            })).to.be.revertedWith("ONE_ETHER");
        })

        it('Cannot become a member more than once', async function () {

            dao.becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await expect(dao.becomeMember({
                value: ethers.utils.parseEther("1")
            })).to.be.revertedWith("ALREADY_MEMBER");
        })

    });

    

    describe("Proposals", function () {

        it("Only a member can propose an NFT to buy.", async function () {
            
            await expect(dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                )).to.be.revertedWith("NOT_A_MEMBER");
        });
    

        it("First proposal", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            const p = await dao.getProposal(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                ));

            expect( await p.id).to.equal(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                ));

            expect( await p.proposer).to.equal(owner.address);
            expect( await p.forVotes).to.equal(0);
            expect( await p.againstVotes).to.equal(0);
            expect( await p.executed).to.equal(false);

        })
   
    });
    

    describe("Delegation", function () {

        it("Changes Balance", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).delegate(addr1.address);
            expect(await dao.getDelegatee(owner.address)).to.be.equal(addr1.address);
            expect(await dao.getVotingPower(owner.address)).to.equal(0);
            expect(await dao.getVotingPower(addr1.address)).to.equal(2);
        })

        it("Cannot delegate to a non-member", async function () {

            dao.connect(owner).becomeMember( {
                value: ethers.utils.parseEther("1")
            });

            await expect(dao.connect(owner).delegate(addr1.address)).to.be.revertedWith("NOT_A_MEMBER");
        })

        it("Cannot delegate if no voting power", async function () {

            dao.connect(owner).becomeMember( {
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr2).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).delegate(addr1.address);
            await expect(dao.connect(owner).delegate(addr2.address)).to.be.revertedWith("INSUFFICIENT_VOTING_POWER");
            
        })

        it("Multiple Delegations", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr2).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(addr1).delegate(addr2.address);
            await dao.connect(owner).delegate(addr1.address);

            expect(await dao.getDelegatee(owner.address)).to.be.equal(addr2.address);
            expect(await dao.getDelegatee(addr1.address)).to.be.equal(addr2.address);
            
            expect(await dao.getVotingPower(owner.address)).to.equal(0);
            expect(await dao.getVotingPower(addr1.address)).to.equal(0);
            expect(await dao.getVotingPower(addr2.address)).to.equal(3);
            
        })

        it("Loop", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr2).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(addr2).delegate(owner.address);
            await dao.connect(addr1).delegate(addr2.address);
            await expect(dao.connect(owner).delegate(addr1.address)).to.be.revertedWith("LOOP_FOUND");
            
        })

    });

    describe("Undo Delegation", function () {


        it("Undo Once", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            dao.connect(owner).delegate(addr1.address);
            dao.connect(owner).undoDelegate();
            expect(await dao.getVotingPower(owner.address)).to.equal(1);
            expect(await dao.getVotingPower(addr1.address)).to.equal(1);
        })


        it("Undo Multiple Delegating", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr2).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr3).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(addr1).delegate(addr2.address);
            await dao.connect(owner).delegate(addr1.address);
            await dao.connect(addr2).delegate(addr3.address);

            dao.connect(owner).undoDelegate();
            expect(await dao.getVotingPower(owner.address)).to.equal(1);
            expect(await dao.getVotingPower(addr2.address)).to.equal(0);
        })


    })
    

    describe("Voting", function () {

        it("Updates", async function () {

            dao.connect(owner).becomeMember( {
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            dao.connect(owner).castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                ), true);

            const r = await dao.getReceipt(owner.address, await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
            ));
            expect( await r.hasVoted).to.equal(true);

        })

        it("Cannot vote if not a member", async function () {

            await expect(dao.connect(owner).castVote(1, false)).to.be.revertedWith("NOT_A_MEMBER");

        })
    

        it("Cannot vote more than once", async function () {

            dao.connect(owner).becomeMember( {
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            dao.connect(owner).castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                ), true);

            await expect(dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), false)).to.be.revertedWith("ALREADY_VOTED");

        })
   

        it("Cannot vote after deadline", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            const fourDays = 4 * 24 * 60 * 60;
            
            await network.provider.send('evm_increaseTime', [fourDays]);
            await network.provider.send('evm_mine');


            await expect(dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), false)).to.be.revertedWith("VOTING_CLOSED");

        })


        it("Cannot vote if delegated voting power", async function () {

            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            dao.connect(owner).delegate(addr1.address);

            await expect(dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), false)).to.be.revertedWith("NO_VOTING_POWER");

        })
        
    })

    describe("Not successful", function () {

        it("More no votes than yes votes", async function () {
            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            await dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                    [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), false);

            const fourDays = 4 * 24 * 60 * 60;
            
            await network.provider.send('evm_increaseTime', [fourDays]);
            await network.provider.send('evm_mine');


            await expect(dao.connect(owner).execute([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1")))).to.be.revertedWith("PROPOSAL_HAS_NOT_SUCCEEDED");
              

        })

        it("Quota not reached", async function () {
            dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr1).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr2).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr3).becomeMember({
                value: ethers.utils.parseEther("1")
            });
            dao.connect(addr4).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            await dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                    [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), false);

            const fourDays = 4 * 24 * 60 * 60;
            
            await network.provider.send('evm_increaseTime', [fourDays]);
            await network.provider.send('evm_mine');


            await expect(dao.connect(owner).execute([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1")))).to.be.revertedWith("PROPOSAL_HAS_NOT_SUCCEEDED");
              

        })
    })

    describe("Executing", function () {

        it("Test transfer", async function () {

            await dao.connect(owner).becomeMember({
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(addr1).becomeMember( {
                value: ethers.utils.parseEther("1")
            });

            await dao.connect(owner).propose([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            await dao.castVote(await dao.connect(owner).hashProposal([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))), true);

            const fourDays = 4 * 24 * 60 * 60;
            
            await network.provider.send('evm_increaseTime', [fourDays]);
            await network.provider.send('evm_mine');

            await dao.connect(owner).execute([dao.address], 
                [0], [dao.interface.encodeFunctionData("buyFromNftMarketplace", [marketplace.address, nft.address, 1, ethers.utils.parseEther("1000")])], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Buying NFT 1"))
                );

            expect( await marketplace.getOwner(nft.address, 1)).to.equal(dao.address);
        });
        

    });
    

});