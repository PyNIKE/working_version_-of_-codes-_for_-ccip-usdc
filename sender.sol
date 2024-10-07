// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/Ownable.sol";

/**
 * @title Staker Contract
 * @dev This contract allows staking of USDC tokens, and is designed to work with a manager contract
 * to control transfer amounts and recipient addresses.
 */

interface IStaker {
    function stake(address beneficiary, uint256 amount) external;
    function redeem() external;
}

contract Staker is IStaker, ERC20, Ownable {
    using SafeERC20 for ERC20;

    // Errors for invalid operations
    error InvalidUsdcToken(); 
    error InvalidNumberOfDecimals(); 
    error InvalidBeneficiary();
    error InvalidAmount(); 
    error NothingToRedeem(); 
    error NotManager(); 

    // Events for important actions
    event UsdcStaked(address indexed beneficiary, uint256 amount);
    event UsdcRedeemed(address indexed beneficiary, uint256 amount);
    event TransferLimitUpdated(uint256 newLimit);
    event ManagerUpdated(address newManager);

    // USDC token contract
    ERC20 private immutable i_usdcToken;

    // Token decimal precision
    uint8 private immutable i_decimals;

    // Manager contract for managing staking operations
    address public manager;

    // Limit on the amount that can be transferred (can be managed through manager contract)
    uint256 public transferLimit;

    /// @notice Constructor initializes the contract with the USDC token address and sets the owner.
    /// @param _usdcToken The address of the USDC token contract.
    /// @param _manager The address of the initial manager contract.
    constructor(address _usdcToken, address _manager) ERC20("Simple Staker", "STK") {
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        if (_manager == address(0)) revert InvalidBeneficiary();

        i_usdcToken = ERC20(_usdcToken);
        i_decimals = i_usdcToken.decimals();

        if (i_decimals == 0) revert InvalidNumberOfDecimals();

        // Set the initial manager contract
        manager = _manager;
        transferLimit = 1000 * 10**i_decimals; // Set an initial limit of 1000 USDC
    }

    /// @notice Function to update the manager contract.
    /// @dev Can only be called by the owner.
    /// @param _manager The address of the new manager contract.
    function updateManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert InvalidBeneficiary();
        manager = _manager;
        emit ManagerUpdated(_manager);
    }

    /// @notice Function to update the transfer limit.
    /// @dev Can only be called by the manager contract.
    /// @param _newLimit The new transfer limit.
    function updateTransferLimit(uint256 _newLimit) external {
        if (msg.sender != manager) revert NotManager();
        transferLimit = _newLimit;
        emit TransferLimitUpdated(_newLimit);
    }

    /// @notice Function for staking USDC tokens.
    /// @param _beneficiary The address that will receive the staked tokens.
    /// @param _amount The amount of USDC to be staked.
    function stake(address _beneficiary, uint256 _amount) external override {
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_amount == 0 || _amount > transferLimit) revert InvalidAmount();

        i_usdcToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(_beneficiary, _amount);

        emit UsdcStaked(_beneficiary, _amount);
    }

    /// @notice Function for redeeming staked tokens and receiving USDC back.
    function redeem() external override {
        uint256 balance = balanceOf(msg.sender);
        if (balance == 0) revert NothingToRedeem();

        _burn(msg.sender, balance);
        i_usdcToken.safeTransfer(msg.sender, balance);

        emit UsdcRedeemed(msg.sender, balance);
    }

    /// @notice Function to override the decimals method to return the correct decimals of USDC token.
    /// @return The number of decimals used by the token.
    function decimals() public view override returns (uint8) {
        return i_decimals;
    }
}
