// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "hardhat/console.sol";

contract VRFConsumer is VRFConsumerBase {
    // For Chainlink VRF
    bytes32 internal keyHash;
    uint256 internal fee;

    uint256 public rand;

    constructor(
        address _VRFCoordinator,
        address _LinkToken,
        bytes32 _keyhash
    ) VRFConsumerBase(_VRFCoordinator, _LinkToken) {
        keyHash = _keyhash;
        fee = 0.0001 * 10**18;
    }

    function doRandomRequest() public {
        bytes32 requestId = requestRandomness(keyHash, fee);
        console.logBytes32(requestId);
    }

    function resetRandom() public {
        rand = 0;
    }

    // Gets the randomness from VRF
    function fulfillRandomness(bytes32 requestId, uint256 randomNumber)
        internal
        override
    {
        rand = randomNumber;
    }
}
