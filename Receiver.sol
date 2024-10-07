// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableMap.sol";


contract Receiver is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    error InvalidUsdcToken(); 
    error InvalidStaker(); 
    error InvalidSourceChain(); 
    error InvalidSenderAddress(); 
    error NoSenderOnSourceChain(uint64 sourceChainSelector); 
    error WrongSenderForSourceChain(uint64 sourceChainSelector); 
    error OnlySelf(); 
    error WrongReceivedToken(address usdcToken, address receivedToken); 
    error CallToStakerFailed(); 
    error NoReturnDataExpected(); 
    error MessageNotFailed(bytes32 messageId); 

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        bytes data,
        address token,
        uint256 tokenAmount
    );

    event MessageFailed(bytes32 indexed messageId, bytes reason);
    event MessageRecovered(bytes32 indexed messageId);
    event ManagerUpdated(address indexed newManager); 

    // Example error code, could have many different error codes.
    enum ErrorCode {
        RESOLVED,
        FAILED
    }

    struct FailedMessage {
        bytes32 messageId;
        ErrorCode errorCode;
    }

    IERC20 private immutable i_usdcToken;
    address private immutable i_staker;
    address private manager; 

    mapping(uint64 => address) public s_senders;
    mapping(bytes32 => Client.Any2EVMMessage) public s_messageContents;
    EnumerableMap.Bytes32ToUintMap internal s_failedMessages;

    modifier validateSourceChain(uint64 _sourceChainSelector) {
        if (_sourceChainSelector == 0) revert InvalidSourceChain();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

   
    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this");
        _;
    }

    
    constructor(
        address _router,
        address _usdcToken,
        address _staker,
        address _manager 
    ) CCIPReceiver(_router) {
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        if (_staker == address(0)) revert InvalidStaker();
        i_usdcToken = IERC20(_usdcToken);
        i_staker = _staker;
        manager = _manager; 

        i_usdcToken.safeApprove(_staker, type(uint256).max);
    }

    /// @notice  Changing the manager's address (available only for the current request)
    function updateManager(address _newManager) external onlyManager {
        require(_newManager != address(0), "Invalid manager address");
        manager = _newManager;
        emit ManagerUpdated(_newManager);
    }

    /// @dev Set the sender for the source chain (manager access only)
    function setSenderForSourceChain(
        uint64 _sourceChainSelector,
        address _sender
    ) external onlyManager validateSourceChain(_sourceChainSelector) {
        if (_sender == address(0)) revert InvalidSenderAddress();
        s_senders[_sourceChainSelector] = _sender;
    }

    /// @dev Delete a sender for a source chain (manager access only)
    function deleteSenderForSourceChain(
        uint64 _sourceChainSelector
    ) external onlyManager validateSourceChain(_sourceChainSelector) {
        if (s_senders[_sourceChainSelector] == address(0))
            revert NoSenderOnSourceChain(_sourceChainSelector);
        delete s_senders[_sourceChainSelector];
    }

    function ccipReceive(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external override onlyRouter {
        if (
            abi.decode(any2EvmMessage.sender, (address)) !=
            s_senders[any2EvmMessage.sourceChainSelector]
        ) revert WrongSenderForSourceChain(any2EvmMessage.sourceChainSelector);
        try this.processMessage(any2EvmMessage) {
        } catch (bytes memory err) {
            s_failedMessages.set(
                any2EvmMessage.messageId,
                uint256(ErrorCode.FAILED)
            );
            s_messageContents[any2EvmMessage.messageId] = any2EvmMessage;
            emit MessageFailed(any2EvmMessage.messageId, err);
            return;
        }
    }

    function processMessage(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external onlySelf {
        _ccipReceive(any2EvmMessage); 
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        if (any2EvmMessage.destTokenAmounts[0].token != address(i_usdcToken))
            revert WrongReceivedToken(
                address(i_usdcToken),
                any2EvmMessage.destTokenAmounts[0].token
            );

        (bool success, bytes memory returnData) = i_staker.call(
            any2EvmMessage.data
        );
        if (!success) revert CallToStakerFailed();
        if (returnData.length > 0) revert NoReturnDataExpected();
        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            any2EvmMessage.data,
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
        );
    }

    /// @notice Rerunning a failed message (manager access only)
    function retryFailedMessage(
        bytes32 messageId,
        address beneficiary
    ) external onlyManager {
        if (s_failedMessages.get(messageId) != uint256(ErrorCode.FAILED))
            revert MessageNotFailed(messageId);

        s_failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

        Client.Any2EVMMessage memory message = s_messageContents[messageId];

        IERC20(message.destTokenAmounts[0].token).safeTransfer(
            beneficiary,
            message.destTokenAmounts[0].amount
        );

        emit MessageRecovered(messageId);
    }

    /// @notice Getting a list of failed messages
    function getFailedMessages(
        uint256 offset,
        uint256 limit
    ) external view returns (FailedMessage[] memory) {
        uint256 length = s_failedMessages.length();
        uint256 returnLength = (offset + limit > length)
            ? length - offset
            : limit;
        FailedMessage[] memory failedMessages = new FailedMessage[](
            returnLength
        );

        for (uint256 i = 0; i < returnLength; i++) {
            (bytes32 messageId, uint256 errorCode) = s_failedMessages.at(
                offset + i
            );
            failedMessages[i] = FailedMessage(messageId, ErrorCode(errorCode));
        }
        return failedMessages;
    }
}
