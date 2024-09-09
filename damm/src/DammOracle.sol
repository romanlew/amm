// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


import {console} from "forge-std/console.sol";

contract DammOracle {
    uint256 public OFF_CHAIN_MID_PRICE_ETH_USDT = 2200;
    uint256 public HALF_SPREAD = 5000;
    

    /**
     * Returns the off chain mid price for pool
     */
    function getOffchainMidPrice() public view returns(uint256 offChainMidPrice) {
        return OFF_CHAIN_MID_PRICE_ETH_USDT;
    }

    /**
     * Returns the simulated orderbookpressure
     */
    function getOrderBookPressure() public view returns (uint256) {
        // uint256 bidSize = random(1, 1000);
        // console.logUint(1000 + HALF_SPREAD);
        // // uint256 bidPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (1000 - HALF_SPREAD) / 1000;
        // uint256 askPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (1000 + HALF_SPREAD) / 1000;
        // console.log("ASK PRICE:", askPrice);
        // uint256 askSize = random(1, 1000);

        // while (askSize == bidSize) {
        //     askSize = random(1, 1000);
        // }

        // uint256 bidValue = bidSize * bidPrice;
        // uint256 askValue = askSize * askPrice;
        // return (askValue - bidValue) * 1000 / (askValue + bidValue);
        return 5000;
    }

    function random(uint256 min, uint256 max) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % (max - min + 1) + min;
    }
}