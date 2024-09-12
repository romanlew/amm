// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {PriorityFeeAndPriceReturnVolatilitySimulator} from "../src/PriorityFeeAndPriceReturnVolatilitySimulator.sol";
import {MevClassifier} from "../src/MevClassifier.sol";

contract DammOracle {
    uint256 public OFF_CHAIN_MID_PRICE_ETH_USDT = 2200;
    uint256 public HALF_SPREAD = 5000;
    uint256 constant HUNDRED_PERCENT = 1_000_000;
    uint256 constant SCALING_FACTOR = 10**18;
    uint256 public SqrtX96Price;
    
    PriorityFeeAndPriceReturnVolatilitySimulator public volatilityCalculator;

    constructor() {
        volatilityCalculator = new PriorityFeeAndPriceReturnVolatilitySimulator();
    }

    /**
     * Returns the off chain mid price for pool
     */
    function getOffchainMidPrice() public view returns(uint256 offChainMidPrice) {
        return OFF_CHAIN_MID_PRICE_ETH_USDT;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function getOrderBookPressure() public view returns (uint256) {
        uint256 bidSize = random(1, 1000);
        // console.logUint("bid size");
        console.log("getOrderBookPressure | bid size:", bidSize);
        uint256 bidPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (HUNDRED_PERCENT - HALF_SPREAD) / HUNDRED_PERCENT;
        // console.logUint("bid price");
        console.log("getOrderBookPressure | bid price:", bidPrice);
        uint256 askPrice = OFF_CHAIN_MID_PRICE_ETH_USDT * (HUNDRED_PERCENT + HALF_SPREAD) / HUNDRED_PERCENT;
        // console.logUint("ask price");
        console.log("getOrderBookPressure | ask price:", askPrice);
        uint256 askSize = random(1, 1000);
        // console.logUint("ask size");
        console.log("getOrderBookPressure | ask size:", askSize);

        // while (askSize == bidSize) {
        //     askSize = random(1, 1000);
        // }

        // uint256 bidValue = bidSize * bidPrice;
        // uint256 askValue = askSize * askPrice;
        return (askSize * askPrice - bidSize * bidPrice) / (askSize * askPrice + bidSize * bidPrice);
        // return 5000;
    }

    function getPriceVolatility() public view returns (uint256) {
        return volatilityCalculator.getPriceVolatility();
    }

    function getPriorityFeeVolatility() public view returns (uint256) {
        return volatilityCalculator.getPriorityFeeVolatility();
    }

    function random(uint256 min, uint256 max) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % (max - min + 1) + min;
    }

    function getPrices(uint256 blockId) external view returns (uint256 priceBeforePreviousBlock, 
                                                               uint256 priceAfterPreviousBlock) {
        // Simulate fetching two consecutive prices from Gbm
        // uint256 priceVolatility = getPriceVolatility(); 
        uint256 priceVolatility = 10 / (sqrt(86400 / 15) * 10);
        uint256 basePrice = 1000; // Example base price
        // Simulate price before the previous block
        priceBeforePreviousBlock = basePrice + random(0, priceVolatility);
        // Simulate price after the previous block
        priceAfterPreviousBlock = basePrice + random(0, priceVolatility);
        return (priceBeforePreviousBlock, priceAfterPreviousBlock);
    }
}