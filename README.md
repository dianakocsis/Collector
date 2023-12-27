# The Dao Project

## Project Spec

You are writing a contract for Collector DAO, a DAO that aims to collect NFTs. This DAO wishes to have a contract that:

- Allows anyone to buy a membership for 1 ETH.

- Allows a member to create governance proposals, which include a series of proposed arbitrary functions to execute.

- Allows members to vote on proposals:
  - Members can vote over 7 day period, beginning immediately after the proposal is generated.
  - A vote is either "Yes" or "No" (no “Abstain” votes).
  - A member's vote on a proposal cannot be changed after it is cast.

> Any time duration should be measured in seconds, not the number of blocks that has passed.

- A proposal is considered passed when all of the following are true:

  - The voting period has concluded.
  - There are more Yes votes than No votes.
  - A 25% quorum requirement is met.

- Allows any address to execute successfully passed proposals.

- Reverts currently executing proposals if any of the proposed arbitrary function calls fail. (Entire transaction should revert.)

- Incentivizes positive interactions with the DAO's proposals, by:

      - Incentivizing rapid execution of successfully passed proposals by offering a 0.01 ETH execution reward, provided by the DAO contract, to the address that executes the proposal.

  &nbsp; > We don't want sending the execution reward to cause any problems with the proposal execution, so to keep it simple, if the reward payment fails, Collector DAO should ignore it (even though that means the executor doesn't get rewarded).

### Implementation Requirements

- A standardized NFT-buying function called buyNFTFromMarketplace should exist on the DAO contract so that DAO members can include it as one of the proposed arbitrary function calls on routine NFT purchase proposals.
- Even though this DAO has one main purpose (collecting NFTs), the proposal system should support proposing the execution of any arbitrarily defined functions on any contract.
- A function that allows an individual member to vote on a specific proposal should exist on the DAO contract.
- A function that allows any address to submit a DAO member's vote using off-chain generated EIP-712 signatures should exist on the DAO contract.
- Another function should exist that enables bulk submission and processing of many EIP-712 signature votes, from several DAO members, across multiple proposals, to be processed in a single function call.

#### Proposal System Caveats

- It should be possible to submit proposals with identical sets of proposed function calls.
  The proposal's data should not be stored in the contract's storage. Instead, only a hash of the data should be stored on-chain.

#### Voting System Caveats

- DAO members must have joined before a proposal is created in order to be allowed to vote on that proposal.
  - Note: This applies even when the two transactions - member joining and proposal creation - fall in the same block. In that case, the ordering of transactions in the block is what matters.
- A DAO member's voting power should be increased each time they perform one of the following actions:
  - +1 voting power (from zero) when an address purchases their DAO membership
  - +1 voting power to the creator of a successfully executed proposal
