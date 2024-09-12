// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract RandomNumberGenerator {
    uint256 private counter;

    constructor() {
        counter = 0;
    }

    function getRandomNumber() internal returns (uint256) {
        counter++;
        uint256 randomHash = uint256(keccak256(abi.encodePacked(counter, msg.sender)));
        uint256 randomNumber = (randomHash % 9991) + 10; // 9991 is the range (10000 - 10 + 1)
        return randomNumber;
    }
}