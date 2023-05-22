//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract EternalStorage {
    mapping(bytes32 => uint256) internal uintStorage;
    mapping(bytes32 => string) internal stringStorage;
    mapping(bytes32 => address) internal addressStorage;
    mapping(bytes32 => bytes) internal bytesStorage;
    mapping(bytes32 => bool) internal boolStorage;
    mapping(bytes32 => int256) internal intStorage;
}

contract Ownable is EternalStorage {
    event OwnershipTransferred(address previousOwner, address newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner());
        _;
    }

    function owner() public view returns (address) {
        return addressStorage[keccak256("owner")];
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0));
        setOwner(newOwner);
    }

    function setOwner(address newOwner) internal {
        emit OwnershipTransferred(owner(), newOwner);
        addressStorage[keccak256("owner")] = newOwner;
    }
}

contract Claimable is EternalStorage, Ownable {
    function pendingOwner() public view returns (address) {
        return addressStorage[keccak256("pendingOwner")];
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner());
        _;
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0));
        addressStorage[keccak256("pendingOwner")] = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner(), pendingOwner());
        addressStorage[keccak256("owner")] = addressStorage[
            keccak256("pendingOwner")
        ];
        addressStorage[keccak256("pendingOwner")] = address(0);
    }
}

interface ERC20Basic {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

interface ERC20 is ERC20Basic {
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Tsunami is Claimable {
    using SafeMath for uint256;

    event Multisended(uint256 total, address tokenAddress);
    event ClaimedTokens(address token, address owner, uint256 balance);

    modifier hasFee() {
        if (currentFee(msg.sender) > 0) {
            require(msg.value >= currentFee(msg.sender));
        }
        _;
    }

    constructor() {
        setOwner(msg.sender);
        setArrayLimit(200);
        setDiscountStep(0.00000 ether);
        setFee(0.00 ether);
        boolStorage[keccak256("rs_multisender_initialized")] = true;
    }

    receive() external payable {}

    function txCount(address customer) public view returns (uint256) {
        return uintStorage[keccak256(abi.encodePacked("txCount", customer))];
    }

    function arrayLimit() public view returns (uint256) {
        return uintStorage[keccak256(abi.encodePacked("arrayLimit"))];
    }

    function setArrayLimit(uint256 _newLimit) public onlyOwner {
        require(_newLimit != 0);
        uintStorage[keccak256("arrayLimit")] = _newLimit;
    }

    function discountStep() public view returns (uint256) {
        return uintStorage[keccak256("discountStep")];
    }

    function setDiscountStep(uint256 _newStep) public onlyOwner {
        // require(_newStep != 0);
        uintStorage[keccak256("discountStep")] = _newStep;
    }

    function fee() public view returns (uint256) {
        return uintStorage[keccak256("fee")];
    }

    function currentFee(address _customer) public view returns (uint256) {
        if (fee() > discountRate(msg.sender)) {
            return fee().sub(discountRate(_customer));
        } else {
            return 0;
        }
    }

    function setFee(uint256 _newStep) public onlyOwner {
        // require(_newStep != 0);
        uintStorage[keccak256("fee")] = _newStep;
    }

    function discountRate(address _customer) public view returns (uint256) {
        uint256 count = txCount(_customer);
        return count.mul(discountStep());
    }

    function multisendToken(
        address token,
        address[] memory _contributors,
        uint256[] memory _balances
    ) public payable hasFee {
        if (token == 0x000000000000000000000000000000000000bEEF) {
            multisendEther(_contributors, _balances);
        } else {
            uint256 total = 0;
            require(_contributors.length <= arrayLimit());
            ERC20 erc20token = ERC20(token);
            uint8 i = 0;
            for (i; i < _contributors.length; i++) {
                erc20token.transferFrom(
                    msg.sender,
                    _contributors[i],
                    _balances[i]
                );
                total += _balances[i];
            }
            setTxCount(msg.sender, txCount(msg.sender).add(1));
            emit Multisended(total, token);
        }
    }

    function multisendEther(
        address[] memory _contributors,
        uint256[] memory _balances
    ) public payable {
        uint256 total = msg.value;
        uint256 userfee = currentFee(msg.sender);
        require(total >= userfee);
        require(_contributors.length <= arrayLimit());
        total = total.sub(userfee);
        uint256 i = 0;
        for (i; i < _contributors.length; i++) {
            require(total >= _balances[i]);
            total = total.sub(_balances[i]);
            payable(_contributors[i]).transfer(_balances[i]);
        }
        setTxCount(msg.sender, txCount(msg.sender).add(1));
        emit Multisended(msg.value, 0x000000000000000000000000000000000000bEEF);
    }

    function claimEth() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
        return;
    }

    function claimTokens(address _token) public onlyOwner {
        ERC20 erc20token = ERC20(_token);
        (uint256 balance) = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
        emit ClaimedTokens(_token, owner(), balance);
    }

    function setTxCount(address customer, uint256 _txCount) private {
        uintStorage[
            keccak256(abi.encodePacked("txCount", customer))
        ] = _txCount;
    }
}

