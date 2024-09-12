// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract PriorityFeeAndPriceReturnVolatilitySimulator {
    uint256 public historicalBlocks;
    uint256[] public priorityFees;
    uint256[] public prices;
    uint256[] public blockNumbers;
    uint256 public index;

    constructor() {
        // include GBM to create hist blocks
        // historicalBlocks = _historicalBlocks;
        // priorityFees = new uint256[](_historicalBlocks);
        // prices = new uint256[](_historicalBlocks);
        // blockNumbers = new uint256[](_historicalBlocks);
        // index = 0;
    }

    function recordData(uint256 priorityFee, uint256 price) public {
        if (block.number > blockNumbers[index]) {
            priorityFees[index] = priorityFee;
            prices[index] = price;
            blockNumbers[index] = block.number;
            index = (index + 1) % historicalBlocks;
        }
    }

    function calculateMean(
        uint256[] memory data) internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function calculateStdDev(uint256[] memory data, uint256 mean) internal view returns (uint256) {
        uint256 variance = 0;
        for (uint256 i = 0; i < data.length; i++) {
            variance += (data[i] - mean) * (data[i] - mean);
        }
        variance /= data.length;
        return sqrt(variance);
    }

    function standardizeData(uint256[] memory data, uint256 mean, uint256 stdDev) internal view returns (uint256[] memory) {
        uint256[] memory standardizedData = new uint256[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            standardizedData[i] = (data[i] - mean) * 1e18 / stdDev; // Multiply by 1e18 to maintain precision
        }
        return standardizedData;
    }

    function calculateVolatility(uint256[] memory data) internal view returns (uint256) {
        uint256 mean = calculateMean(data);
        uint256 stdDev = calculateStdDev(data, mean);
        uint256[] memory standardizedData = standardizeData(data, mean, stdDev);

        uint256 variance = 0;
        for (uint256 i = 0; i < standardizedData.length; i++) {
            variance += standardizedData[i] * standardizedData[i];
        }
        variance /= standardizedData.length;

        return sqrt(variance);
    }

    function getPriorityFeeVolatility() public view returns (uint256) {
        return calculateVolatility(priorityFees);
    }

    function getPriceVolatility() public view returns (uint256) {
        return calculateVolatility(prices);
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
}