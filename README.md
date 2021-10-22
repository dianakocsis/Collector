# Collector-DAO
Project: Collector DAO

In this project you're going to write a governance smart contract for a decentralized autonomous organization (DAO) aimed at buying valuable NFTs. In doing so, you will:

Implement a treasury contract that buys NFTs
Implement a voting system with vote delegation
Implement a proposal system that calls arbitrary functions.
Context

Read through the context document before starting this project.

For examples of NFT DAOs that have governance, read this article.

Project Spec

You are writing a contract for Collector DAO, a DAO that aims to collect rare NFTs. This DAO wishes to have a contract that:

Allows anyone to buy a membership for 1 ETH
Allows a member to propose an NFT to buy
Allows members to vote on proposals:
With the ability to delegate votes to other members
With a 25% quorum
If passed, have the contract purchase the NFT in a reasonably automated fashion.
DO NOT use third party libraries for this project. You are free to reference other governance contract implementations, but you must write your own from scratch.

Project Extensions

Allow members to vote by signature.
Implement optimistic voting into your voting system.