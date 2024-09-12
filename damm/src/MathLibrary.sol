// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


contract MathLibrary {    
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
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