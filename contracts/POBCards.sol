// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract POBCards is ERC721Enumerable, Ownable, VRFConsumerBase {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    // Attribute Enums
    enum Rarity {
        Normal,
        MythicRare,
        Diamond
    }

    enum Alchemy {
        Ground,
        Air,
        Water,
        Fire,
        None
    }

    enum Pollution {
        Clean,
        Polluted,
        None
    }

    enum Type {
        One,
        Two
    }

    struct Metadata {
        Rarity rarity;
        Alchemy alchemy;
        Pollution pollution;
        Type cardType;
        string image;
    }

    struct MintData {
        bool overThresh;
        address burner;
        string txHash;
        uint256 randomNumber;
        // bool randomnessFulfilled;
        bool processed;
    }

    // struct RequestData {
    //     bytes32 requestId;
    //     uint256 randomNumber;
    //     bool processed;
    // }

    // Others
    bool public mintingEnabled;
    string public nftPrefix;
    address public link;

    // For NFT
    Counters.Counter private _tokenIds;
    mapping(uint256 => string) public tokenURIs;
    mapping(uint256 => Metadata) public metadata;
    mapping(bytes32 => MintData) public mintData;
    mapping(Pollution => mapping(Alchemy => mapping(Rarity => mapping(Type => string))))
        public nftImages;
    mapping(string => bool) public processedTxns;
    bytes32[] public requestIds;
    uint256 public requestIdsIdx;
    mapping(uint256 => bool) public metadataFrozen;
    mapping(uint256 => bytes32) public tokenIdToReqId;

    // For Chainlink VRF
    bytes32 internal keyHash;
    uint256 internal fee;

    // Events
    event Received(address, uint);

    constructor(
        address _VRFCoordinator,
        address _LinkToken,
        bytes32 _keyhash
    ) ERC721("POB Cards", "POB") VRFConsumerBase(_VRFCoordinator, _LinkToken) {
        mintingEnabled = true;
        keyHash = _keyhash;
        fee = 0.0001 * 10**18;
        requestIdsIdx = 0;
        link = _LinkToken;
        nftPrefix = "ipfs://QmYRcVA1SyuSTgQkkUfzRyVsNViRd4XvqBrPkrWGt8Y5tG/";

        nftImages[Pollution.Clean][Alchemy.Air][Rarity.Normal][Type.One] = "air01.mp4";
        nftImages[Pollution.Polluted][Alchemy.Air][Rarity.Normal][Type.One] = "air02.mp4";
        nftImages[Pollution.Polluted][Alchemy.Air][Rarity.Normal][Type.Two] = "air03.mp4";
        nftImages[Pollution.Clean][Alchemy.Air][Rarity.MythicRare][Type.One] = "air04.mp4";
        nftImages[Pollution.Polluted][Alchemy.Air][Rarity.MythicRare][Type.One] = "airground05.mp4";

        nftImages[Pollution.Polluted][Alchemy.None][Rarity.Diamond][Type.One] = "diamond01.mp4";
        nftImages[Pollution.Clean][Alchemy.None][Rarity.Diamond][Type.One] = "diamond02.mp4";

        nftImages[Pollution.Clean][Alchemy.Fire][Rarity.Normal][Type.One] = "fire01.mp4";
        nftImages[Pollution.Polluted][Alchemy.Fire][Rarity.Normal][Type.One] = "fire02.mp4";
        nftImages[Pollution.Clean][Alchemy.Fire][Rarity.MythicRare][Type.One] = "fire03.mp4";
        nftImages[Pollution.Polluted][Alchemy.Fire][Rarity.MythicRare][Type.One] = "fire04.mp4";

        nftImages[Pollution.Clean][Alchemy.Ground][Rarity.Normal][Type.One] = "ground01.mp4";
        nftImages[Pollution.Polluted][Alchemy.Ground][Rarity.Normal][Type.One] = "ground02.mp4";
        nftImages[Pollution.Clean][Alchemy.Ground][Rarity.Normal][Type.Two] = "ground03.mp4";
        nftImages[Pollution.Clean][Alchemy.Ground][Rarity.MythicRare][Type.One] = "ground04.mp4";
        nftImages[Pollution.Polluted][Alchemy.Ground][Rarity.MythicRare][Type.One] = "airground005.mp4";

        nftImages[Pollution.Polluted][Alchemy.Water][Rarity.Normal][Type.One] = "water01.mp4";
        nftImages[Pollution.Polluted][Alchemy.Water][Rarity.Normal][Type.Two] = "water02.mp4";
        nftImages[Pollution.Clean][Alchemy.Water][Rarity.Normal][Type.One] = "water03.mp4";
        nftImages[Pollution.Clean][Alchemy.Water][Rarity.MythicRare][Type.One] = "water04.mp4";
        nftImages[Pollution.Polluted][Alchemy.Water][Rarity.MythicRare][Type.One] = "water05.mp4";

    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return tokenURIs[tokenId];
    }

    function getRequestIdsLen() public view returns (uint) {
        return requestIds.length;
    }

    // Check the random number which was used to mint the NFT
    function getRandomNumberForTokenId(uint tokenId) public view returns (uint) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        bytes32 requestId = tokenIdToReqId[tokenId];
        return mintData[requestId].randomNumber;
    }

    // ***********************
    //  INTERNAL FUNCTIONS
    // ***********************

    // Internal function to get Pollution value from random number
    function _getRarity(uint256 rand, bool overThreshold)
        internal
        pure
        returns (Rarity)
    {
        if (overThreshold == false) {
            return Rarity.Normal;
        }
        uint256 num = rand % 100;
        if (num < 91) {
            return Rarity.Normal; // 91%
        } else if (num < 98) {
            return Rarity.MythicRare; // 7%
        } else return Rarity.Diamond; // 2%
    }

    // Internal function to get Alchemy value from random number
    function _getAlchemy(uint256 rand, Rarity rarity)
        internal
        pure
        returns (Alchemy)
    {
        if (rarity == Rarity.Diamond) {
            return Alchemy.None;
        }

        uint256 num = rand % 1000000;
        num = num % 100;
        if (num < 31) {
            return Alchemy.Ground; // 31%
        } else if (num < (31 + 26)) {
            return Alchemy.Air; // 26%
        } else if (num < (31 + 26 + 23)) {
            return Alchemy.Fire; // 23%
        } else return Alchemy.Water; // 20%
    }

    // Internal function to get Pollution value from random number
    function _getPollution(uint256 rand, Rarity rarity)
        internal
        pure
        returns (Pollution)
    {
        // if (rarity == Rarity.Diamond) {
        //     return Pollution.None;
        // }

        uint256 num = rand % 1000000;
        num = num % 100;
        if (num < 51) {
            return Pollution.Polluted; // 51%
        } else return Pollution.Clean; // 49%
    }

    function _getType(
        uint256 rand,
        Pollution poll,
        Rarity rar,
        Alchemy alc
    ) internal pure returns (Type) {
        if (
            (poll == Pollution.Polluted &&
                alc == Alchemy.Air &&
                rar == Rarity.Normal) ||
            (poll == Pollution.Clean &&
                alc == Alchemy.Ground &&
                rar == Rarity.Normal) ||
            (poll == Pollution.Polluted &&
                alc == Alchemy.Water &&
                rar == Rarity.Normal) ||
            (poll == Pollution.Polluted &&
                alc == Alchemy.Water &&
                rar == Rarity.Normal)
        ) {
            uint256 num = rand % 2;
            if (num == 0) return Type.One;
            else return Type.Two;
        }

        return Type.One;
    }

    function _getImage(Pollution poll, Alchemy alc, Rarity rar, Type cardType) internal view returns (string memory) {
        require (keccak256(bytes(nftImages[poll][alc][rar][cardType])) !=  keccak256(bytes("")), "No such NFT Image");
        return string(abi.encodePacked(nftPrefix, nftImages[poll][alc][rar][cardType]));
    }

    // Gets the randomness from VRF and mints NFT storing metadata on chain
    function fulfillRandomness(bytes32 requestId, uint256 randomNumber)
        internal
        override
    {
        MintData storage m = mintData[requestId];
        m.randomNumber = randomNumber;
        // m.randomnessFulfilled = true;
        requestIds.push(requestId);
    }

    

    // ***********************
    //  ADMIN ONLY FUNCTIONS
    // ***********************

    // Enable / Disable Minting
    function setMintingEnabled(bool _mintingEnabled) public onlyOwner {
        mintingEnabled = _mintingEnabled;
    }

    // Set Fee
    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    // Set keyHash
    function setKeyHash(bytes32 _keyHash) public onlyOwner {
        keyHash = _keyHash;
    }

    // Function to freeze metadata, so that token uri cannot be modified anymore
    function freezeMetadata(uint256 tokenId) public onlyOwner {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI setting for nonexistent token"
        );
        metadataFrozen[tokenId] = true;
    }

    

    // Just in case sometime chainlink does not respond
    // Commented out as requestIds is updated on VRF response
    // function incrementRequestIdIndex() external onlyOwner {
    //     requestIdsIdx++;
    // }

    function mintNFTs() public onlyOwner {
        uint256 i = requestIdsIdx;
        for (i; i < requestIds.length; i++) {
            // console.logBytes32(requestIds[i]);
            // console.log(mintData[requestIds[i]].randomnessFulfilled);
            // if (mintData[requestIds[i]].randomnessFulfilled == false) break;
            mintNFTfromMintData(requestIds[i]);
        }
        requestIdsIdx = i;
    }

    function mintNftSingle() public onlyOwner {
        if(requestIdsIdx < requestIds.length){
            mintNFTfromMintData(requestIds[requestIdsIdx]);
            requestIdsIdx++;
        }
    }

    // Mint a NFT storing attributes on chain
    function mintNFT(address owner, Pollution poll, Alchemy alc, Rarity rar, Type t) public onlyOwner returns(uint) {
        string memory image = _getImage(poll, alc, rar, t);
        // Mint a NFT to create a new token id
        uint256 newTokenID = _tokenIds.current();
        _safeMint(owner, newTokenID);
        _tokenIds.increment();

        // Store the metadata on chain, this will be used to generate off-chain metadata and set token URIs.
        metadata[newTokenID] = Metadata({
            rarity: rar,
            alchemy: alc,
            pollution: poll,
            cardType: t,
            image: image
        });
        metadataFrozen[newTokenID] = false;
        return newTokenID;
    }

    function mintNFTfromMintData(bytes32 requestId) internal {
        MintData storage _mintData = mintData[requestId];
        require(
            _mintData.processed == false,
            "MintData already processed to mint a NFT."
        );


        uint256 randomNumber = _mintData.randomNumber;

        // Generate the metadata from random number
        Rarity rar = _getRarity(randomNumber, _mintData.overThresh);
        Alchemy alc = _getAlchemy(randomNumber, rar);
        Pollution poll = _getPollution(randomNumber, rar);
        Type t = _getType(randomNumber, poll, rar, alc);

        // Mint the NFT from above data
        uint tokenId = mintNFT(_mintData.burner, poll, alc, rar, t);
        tokenIdToReqId[tokenId] = requestId;
        _mintData.processed = true;
    }

    // Initiate NFT Minting, this will request randomness from chainlink and save a few params to use later while actual minting
    function initiateMintFromBurn(
        address _burner,
        bool _overThresh,
        bool lockTxHash,
        string calldata _txHash
    ) public onlyOwner {
        require(mintingEnabled == true, "Minting is currently disabled");
        require(
            processedTxns[_txHash] == false,
            "Transaction already processed"
        );
        require(ERC20(link).balanceOf(address(this)) >= fee, "Insufficient Link Balance");
        mintNftSingle();
        bytes32 requestId = requestRandomness(keyHash, fee);
        // requestIds.push(requestId);
        mintData[requestId] = MintData({
            overThresh: _overThresh,
            burner: _burner,
            txHash: _txHash,
            randomNumber: 0,
            processed: false
            // randomnessFulfilled: false
        });

        // Lock tx Hash, so that no more minting against this tx hash
        if(lockTxHash == true){
            processedTxns[_txHash] = true;
        }
    }



    // Set token URI after uploading metadata to server / IPFS
    function setTokenURI(uint256 tokenId, string calldata _tokenURI)
        external
        onlyOwner
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI setting for nonexistent token"
        );
        require(metadataFrozen[tokenId] == false, "Metadata already frozen for this token ID.");

        tokenURIs[tokenId] = _tokenURI;
    }

    // Withdraw Ether Balance
    function withdraw() public payable onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ether left to withdraw");

        (bool success, ) = (msg.sender).call{value: balance}("");
        require(success, "Transfer failed.");
    }

    function withdrawERC20(address token, uint amt) public onlyOwner {
        IERC20(token).transfer(owner(), amt);
    }
}
