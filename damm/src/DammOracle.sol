// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";

contract DammOracle {
    uint256 public OFF_CHAIN_MID_PRICE_ETH_USDT = 2200;
    uint256 public HALF_SPREAD = 5000;
    uint256 constant HUNDRED_PERCENT = 1_000_000;
    uint256 constant SCALING_FACTOR = 10**18;
    uint256 public SqrtX96Price;
    

    /**
     * Returns the off chain mid price for pool
     */
    function getOffchainMidPrice() public view returns(uint256 offChainMidPrice) {
        return OFF_CHAIN_MID_PRICE_ETH_USDT;
    }

    /*
    function sqrt(uint x) returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
    */

    /**
     * Returns the simulated orderbookpressure
     */
    function getOrderBookPressure() public view returns (uint256) {
        uint256 bidSize = random(1, 1000);
        // console.logUint("bid size");
        console.log("bid size:", bidSize);
        uint256 bidPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (HUNDRED_PERCENT - HALF_SPREAD) / HUNDRED_PERCENT;
        // console.logUint("bid price");
        console.log("bid price:", bidPrice);
        uint256 askPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (HUNDRED_PERCENT + HALF_SPREAD) / HUNDRED_PERCENT;
        // console.logUint("ask price");
        console.log("ask price:", askPrice);
        uint256 askSize = random(1, 1000);
        // console.logUint("ask size");
        console.log("ask size:", askSize);

        // while (askSize == bidSize) {
        //     askSize = random(1, 1000);
        // }

        // uint256 bidValue = bidSize * bidPrice;
        // uint256 askValue = askSize * askPrice;f
        // return (askValue - bidValue) * 1000 / (askValue + bidValue);
        return 5000;
    }

    function random(uint256 min, uint256 max) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % (max - min + 1) + min;
    }
}