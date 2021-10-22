// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface NftMarketplace {
    function getPrice(address nftContract, uint nftId) external returns (uint);
    function buy(address nftContract, uint nftId) external payable;
}