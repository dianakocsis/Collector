//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "./NftMarketplace.sol";
import "hardhat/console.sol";

contract NFTContract {
  mapping (uint => address) public tokens; // not realistic, just for testing purchase call
  uint price = 2 ether;

  function getPrice(address _addr, uint _tokenId) external view returns (uint) {
    console.log("in price");
    return price;
  }
  function buy(address _addr, uint _tokenId) external payable {
    require(msg.value >= price, "INSUFFICIENT_ETHER");
    console.log("in pruchase");
    tokens[_tokenId] = msg.sender;
  }

  function getOwner(address _addr, uint _tokenId) external view returns (address) {
    return tokens[_tokenId];
  }

  receive() external payable {}

  fallback() external payable {}
}