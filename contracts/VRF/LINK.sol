pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract ERC677 is ERC20 {
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) public virtual returns (bool success);

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data
    );
}

// File: https://github.com/smartcontractkit/chainlink/blob/develop/evm-contracts/src/v0.4/ERC677Token.sol

abstract contract ERC677Token is ERC677 {
    /**
     * @dev transfer token to a contract address with additional data if the recipient is a contact.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     * @param _data The extra data to be passed to the receiving contract.
     */
    function transferAndCall(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) public virtual override returns (bool success) {
        super.transfer(_to, _value);
        emit Transfer(msg.sender, _to, _value, _data);
        if (isContract(_to)) {
            contractFallback(_to, _value, _data);
        }
        return true;
    }

    // PRIVATE

    function contractFallback(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) private {
        ERC677Receiver receiver = ERC677Receiver(_to);
        receiver.onTokenTransfer(msg.sender, _value, _data);
    }

    function isContract(address _addr) private view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length > 0;
    }
}

abstract contract ERC677Receiver {
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes calldata _data
    ) public virtual;
}

contract LINK is ERC20, ERC677Token {
    modifier validRecipient(address _recipient) {
        require(_recipient != address(0) && _recipient != address(this));
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    constructor() ERC20("Chainlink Mock Token", "LINK") {
        _mint(msg.sender, 10000000000 * 10**decimals());
    }

    // function transferAndCall(
    //     address to,
    //     uint256 value,
    //     bytes calldata data
    // ) external returns (bool success) {
    //     _transfer(msg.sender, to, value);
    //     return true;
    // }

    /**
     * @dev transfer token to a specified address with additional data if the recipient is a contract.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     * @param _data The extra data to be passed to the receiving contract.
     */
    function transferAndCall(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) public override validRecipient(_to) returns (bool success) {
        return super.transferAndCall(_to, _value, _data);
    }
}
