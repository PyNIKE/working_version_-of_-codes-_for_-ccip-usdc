// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/Ownable.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Manager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Adress contracts
    address public staker;    
    address public receiver;   

    // commission
    uint256 public ccipFee;   
    uint256 public customFee;  

    //adress USDC token
    IERC20 public usdcToken;

    // Events to track changes
    event StakerUpdated(address indexed newStaker);
    event ReceiverUpdated(address indexed newReceiver);
    event FeesUpdated(uint256 newCcipFee, uint256 newCustomFee);
    event Staked(address indexed beneficiary, uint256 amount);
    event Redeemed(address indexed beneficiary, uint256 amount);

    // Constructor
    constructor(
        address _usdcToken,
        address _staker,
        address _receiver,
        uint256 _ccipFee,
        uint256 _customFee
    ) {
        require(_usdcToken != address(0), "Invalid USDC address");
        require(_staker != address(0), "Invalid staker address");
        require(_receiver != address(0), "Invalid receiver address");

        usdcToken = IERC20(_usdcToken);
        staker = _staker;
        receiver = _receiver;
        ccipFee = _ccipFee;
        customFee = _customFee;
    }

    // Updating the staker address
    function updateStaker(address _newStaker) external onlyOwner {
        require(_newStaker != address(0), "Invalid address");
        staker = _newStaker;
        emit StakerUpdated(_newStaker);
    }

    // Recipient Address Update
    function updateReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid address");
        receiver = _newReceiver;
        emit ReceiverUpdated(_newReceiver);
    }

    // Fee Update
    function updateFees(uint256 _newCcipFee, uint256 _newCustomFee) external onlyOwner {
        ccipFee = _newCcipFee;
        customFee = _newCustomFee;
        emit FeesUpdated(_newCcipFee, _newCustomFee);
    }

    // Function for executing steak
    function stake(uint256 amount, address beneficiary) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(beneficiary != address(0), "Invalid beneficiary address");

        // Calculation of total commissions
        uint256 totalFees = ccipFee + customFee;
        uint256 totalAmount = amount + totalFees;

        // We check that the sender has enough funds
        usdcToken.safeTransferFrom(msg.sender, address(this), totalAmount);

        // commissions transfer
        usdcToken.safeTransfer(receiver, totalFees); 

        // Calling the stake function in the staker contract
        (bool success, ) = staker.call(abi.encodeWithSignature("stake(address,uint256)", beneficiary, amount));
        require(success, "Stake operation failed");

        emit Staked(beneficiary, amount);
    }

    // Function for making withdrawals
    function redeem() external nonReentrant {
        (bool success, ) = staker.call(abi.encodeWithSignature("redeem()"));
        require(success, "Redeem operation failed");

        uint256 redeemedAmount = usdcToken.balanceOf(address(this));
        require(redeemedAmount > 0, "Nothing to redeem");

        // We transfer funds back to the owner
        usdcToken.safeTransfer(msg.sender, redeemedAmount);

        emit Redeemed(msg.sender, redeemedAmount);
    }
}
