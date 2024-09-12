// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MathLibrary} from "../src/MathLibrary.sol";
import {console} from "forge-std/console.sol";

contract GeometricBrownianMotion {
    uint256 public initialPrice;
    uint256 public dailyStd;
    uint256 public blocksPerDay;
    uint256 public numberDays;
    uint256[] public prices; // State variable

    constructor(uint256 _initialPrice, uint256 _dailyStd, uint256 _blocksPerDay, uint256 _numberDays) {
        initialPrice = _initialPrice;
        dailyStd = _dailyStd;
        blocksPerDay = _blocksPerDay;
        numberDays = _numberDays;
    }

    function generatePricePath() public returns (uint256[] memory) {
        uint256 p0 = initialPrice;
        uint256 sigma = dailyStd / sqrt(blocksPerDay);
        uint256 totalNumberOfBlocks = numberDays * blocksPerDay;
        int256[] memory z = new int256[](totalNumberOfBlocks);
        uint256[] memory localPrices = new uint256[](totalNumberOfBlocks); // Renamed local variable

        // Generate random normal values (simplified)
        for (uint256 k = 0; k < totalNumberOfBlocks; k++) {
            z[k] = int256(randomNormal(0, sigma));
        }

        // Cumulative sum
        for (uint256 k = 1; k < totalNumberOfBlocks; k++) {
            z[k] = z[k - 1] + z[k];
        }

        // Calculate prices
        for (uint256 k = 0; k < totalNumberOfBlocks; k++) {
            int256 drift = int256(k * sigma * sigma / 2);
            localPrices[k] = uint256(exp(z[k] - drift)) * p0 / exp(z[0]);
        }

        prices = localPrices; // Update state variable
        return prices;
    }

    function randomNormal(int256 mean, uint256 stddev) internal view returns (int256) {
        // Simplified random normal distribution using Box-Muller transform
        uint256 u1 = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 1000000;
        uint256 u2 = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, u1))) % 1000000;
        int256 z0 = int256(sqrt(u1) * uint256(stddev) / 1000);
        return z0 + mean;
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

    function exp(int256 x) internal pure returns (uint256) {
        // Approximate exp function using Taylor series expansion
        uint256 sum = 1;
        uint256 term = 1;
        for (uint256 i = 1; i < 10; i++) {
            term = term * uint256(x) / i;
            sum = sum + term;
        }
        return sum;
    }
}