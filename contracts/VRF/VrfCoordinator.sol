pragma solidity 0.8.4;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/VRFRequestIDBase.sol";

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

import "hardhat/console.sol";

contract VrfCoordinator is VRFRequestIDBase {
    constructor(address _link) {
        LINK = LinkTokenInterface(_link);
    }

    // Structs
    struct ServiceAgreement {
        // Tracks oracle commitments to VRF service
        address vRFOracle; // Oracle committing to respond with VRF service
        uint96 fee; // Minimum payment for oracle response. Total LINK=1e9*1e18<2^96
        bytes32 jobID; // ID of corresponding chainlink job in oracle's DB
    }

    struct Callback {
        // Tracks an ongoing request
        address callbackContract; // Requesting contract, which will receive response
        // Amount of LINK paid at request time. Total LINK = 1e9 * 1e18 < 2^96, so
        // this representation is adequate, and saves a word of storage when this
        // field follows the 160-bit callbackContract address.
        uint96 randomnessFee;
        // Commitment to seed passed to oracle by this contract, and the number of
        // the block in which the request appeared. This is the keccak256 of the
        // concatenation of those values. Storing this commitment saves a word of
        // storage.
        bytes32 seedAndBlockNum;
    }

    modifier sufficientLINK(uint256 _feePaid, bytes32 _keyHash) {
        require(
            _feePaid >= serviceAgreements[_keyHash].fee,
            "Below agreed payment"
        );
        _;
    }

    LinkTokenInterface internal LINK;
    bytes32 public lastRequestId;

    // Mappings
    mapping(bytes32 => ServiceAgreement) /* provingKey */
        public serviceAgreements;
    mapping(bytes32 => Callback) /* (provingKey, seed) */
        public callbacks;
    mapping(bytes32 => mapping(address => uint256)) /* provingKey */ /* consumer */
        private nonces;

    modifier onlyLINK() {
        require(msg.sender == address(LINK), "Must use LINK token");
        _;
    }

    event RandomnessRequest(
        bytes32 keyHash,
        uint256 seed,
        bytes32 indexed jobID,
        address sender,
        uint256 fee,
        bytes32 requestID
    );

    function onTokenTransfer(
        address _sender,
        uint256 _fee,
        bytes memory _data
    ) public onlyLINK {
        (bytes32 keyHash, uint256 seed) = abi.decode(_data, (bytes32, uint256));
        randomnessRequest(keyHash, seed, _fee, _sender);
    }

    function randomnessRequest(
        bytes32 _keyHash,
        uint256 _consumerSeed,
        uint256 _feePaid,
        address _sender
    ) internal sufficientLINK(_feePaid, _keyHash) {
        uint256 nonce = nonces[_keyHash][_sender];
        // uint256 nonce = 0;
        uint256 preSeed = makeVRFInputSeed(
            _keyHash,
            _consumerSeed,
            _sender,
            nonce
        );
        bytes32 requestId = makeRequestId(_keyHash, preSeed);
        lastRequestId = requestId;
        console.logBytes32(requestId);
        // Cryptographically guaranteed by preSeed including an increasing nonce
        assert(callbacks[requestId].callbackContract == address(0));
        callbacks[requestId].callbackContract = _sender;
        assert(_feePaid < 1e27); // Total LINK fits in uint96
        callbacks[requestId].randomnessFee = uint96(_feePaid);
        callbacks[requestId].seedAndBlockNum = keccak256(
            abi.encodePacked(preSeed, block.number)
        );
        console.log("Emittting event");
        emit RandomnessRequest(
            _keyHash,
            preSeed,
            serviceAgreements[_keyHash].jobID,
            _sender,
            _feePaid,
            requestId
        );
        nonces[_keyHash][_sender] = nonces[_keyHash][_sender] + 1;
    }

    function sendRandomNum(
        uint256 rand,
        address consumerContract,
        bytes32 requestId
    ) public {
        VRFConsumerBase v;
        bytes memory resp = abi.encodeWithSelector(
            v.rawFulfillRandomness.selector,
            requestId,
            rand
        );
        // // The bound b here comes from https://eips.ethereum.org/EIPS/eip-150. The
        // // actual gas available to the consuming contract will be b-floor(b/64).
        // // This is chosen to leave the consuming contract ~200k gas, after the cost
        // // of the call itself.
        uint256 b = 206000;
        require(gasleft() >= b, "not enough gas for consumer");
        // // A low-level call is necessary, here, because we don't want the consuming
        // // contract to be able to revert this execution, and thus deny the oracle
        // // payment for a valid randomness response. This also necessitates the above
        // // check on the gasleft, as otherwise there would be no indication if the
        // // callback method ran out of gas.
        // //
        // // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = consumerContract.call(resp);
        // // Avoid unused-local-variable warning. (success is only present to prevent
        // // a warning that the return value of consumerContract.call is unused.)
        (success);

        //     VRFConsumerBase(to).rawFulfillRandomness(requestId, rand);
    }
}
