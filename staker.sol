// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStaker {
    function stake(address beneficiary, uint256 amount) external;
    function redeem() external;
}

contract Staker is IStaker, ERC20 {
    using SafeERC20 for ERC20;

    // wrong
    error InvalidUsdcToken();
    error InvalidNumberOfDecimals();
    error InvalidBeneficiary();
    error InvalidAmount();
    error NothingToRedeem();
    error NotManager(); // wrong for control

    event UsdcStaked(address indexed beneficiary, uint256 amount);
    event UsdcRedeemed(address indexed beneficiary, uint256 amount);
    event ManagerUpdated(address indexed newManager);

    ERC20 private immutable i_usdcToken;
    uint8 private immutable i_decimals;

    address private manager; // adress manager for control

    /// @notice incinalize usdc
    /// @param _usdcToken adress contract usdc
    /// @param _manager Address of the contract or account that will manage this contract
    constructor(address _usdcToken, address _manager) ERC20("Simple Staker", "STK") {
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        if (_manager == address(0)) revert InvalidBeneficiary();

        i_usdcToken = ERC20(_usdcToken);
        i_decimals = i_usdcToken.decimals();
        manager = _manager;

        if (i_decimals == 0) revert InvalidNumberOfDecimals();
    }

    // Restricting access to manager only
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /// @notice Change manager (available only for the current request)
    function updateManager(address _newManager) external onlyManager {
        if (_newManager == address(0)) revert InvalidBeneficiary();
        manager = _newManager;
        emit ManagerUpdated(_newManager);
    }

    function stake(address _beneficiary, uint256 _amount) external {
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_amount == 0) revert InvalidAmount();

        i_usdcToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(_beneficiary, _amount);
        emit UsdcStaked(_beneficiary, _amount);
    }

    function redeem() external {
        uint256 balance = balanceOf(msg.sender);
        if (balance == 0) revert NothingToRedeem();
        _burn(msg.sender, balance);
        i_usdcToken.safeTransfer(msg.sender, balance);
        emit UsdcRedeemed(msg.sender, balance);
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }
}
