// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// VRF V2+ Wrapper interface
interface IVRFV2PlusWrapper {
    function calculateRequestPriceNative(
        uint32 _callbackGasLimit,
        uint32 _numWords
    ) external view returns (uint256);

    function requestRandomWordsInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        bytes calldata extraArgs
    ) external payable returns (uint256 requestId);
}

// ERC20 interface - minimal interface with only functions we use
interface IERC20 {
    function mint(address account, uint256 value) external;
}

/**
 * @title VrfConsumer
 * @dev A VRF consumer contract that requests randomness from Chainlink VRF V2+ wrapper
 * using native tokens (ETH) for payment. Implements a lottery system where participants
 * pay an entry fee and a winner is selected using VRF randomness.
 * This contract matches the functionality of the Stylus Rust vrf-consumer contract
 */
contract VrfConsumer is Ownable, ReentrancyGuard {

    // VRF variables
    address public iVrfV2PlusWrapper;
    address public lastWinner;

    // Request tracking variables (from DirectFundingConsumer)
    mapping(uint256 => uint256) public sRequestsPaid; // store the amount paid for request random words
    mapping(uint256 => uint256) public sRequestsValue; // store random word returned
    mapping(uint256 => bool) public sRequestsFulfilled; // store if request was fulfilled
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    // Event variables
    bool public acceptingParticipants;
    uint256 public lotteryIntervalHours;
    uint256 public lastRequestTimestamp;

    // Token distribution variables
    address public erc20TokenAddress;
    address[] public participants;
    uint256 public lotteryEntryFee;

    // Events
    event RequestSent(uint256 indexed requestId, uint32 numWords, uint256 payment);
    event RequestFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords,
        address winner
    );
    event Received(address indexed sender, uint256 value);

    // Errors
    error OnlyVRFWrapperCanFulfill(address have, address want);

    /**
     * @dev Constructor - initializes the contract with VRF wrapper address and owner
     * @param vrfV2PlusWrapper Address of the VRF V2+ wrapper contract
     * @param owner Initial owner address
     */
    constructor(address vrfV2PlusWrapper, address owner) Ownable(owner) {
        iVrfV2PlusWrapper = vrfV2PlusWrapper;
        erc20TokenAddress = address(0);

        lotteryEntryFee = 500000; // 0.0005 ETH in wei
        lotteryIntervalHours = 4;
        acceptingParticipants = true;

        callbackGasLimit = 100000;
        requestConfirmations = 3;
        numWords = 1;
    }

    /**
     * @dev Internal function to request randomness paying in native ETH
     * @param _callbackGasLimit Gas limit for the callback
     * @param _requestConfirmations Number of confirmations to wait
     * @param _numWords Number of random words to request
     * @return requestId The VRF request ID
     * @return reqPrice The price paid for the request
     */
    function requestRandomnessPayInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords
    ) internal returns (uint256 requestId, uint256 reqPrice) {
        IVRFV2PlusWrapper vrfWrapper = IVRFV2PlusWrapper(iVrfV2PlusWrapper);
        require(
            iVrfV2PlusWrapper.code.length > 0,
            "VRF wrapper contract does not exist at given address"
        );

        // Calculate request price
        reqPrice = vrfWrapper.calculateRequestPriceNative(
            _callbackGasLimit,
            _numWords
        );

        // Prepare extra args for native payment
        bytes memory extraArgs = getExtraArgsForNativePayment();

        // Request random words
        requestId = vrfWrapper.requestRandomWordsInNative{value: reqPrice}(
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            extraArgs
        );

        return (requestId, reqPrice);
    }

    /**
     * @dev Request random words to resolve the lottery
     * @return requestId The VRF request ID
     */
    function requestRandomWords() external returns (uint256 requestId) {
        // Check if enough time has passed since last request
        // Allow first call when lastRequestTimestamp is 0
        if (lastRequestTimestamp > 0) {
            uint256 intervalSecs = lotteryIntervalHours * 3600;
            require(
                block.timestamp >= lastRequestTimestamp + intervalSecs,
                "Too soon to resolve lottery"
            );
        }

        // Update state BEFORE external call (Checks-Effects-Interactions pattern)
        lastRequestTimestamp = block.timestamp;

        uint256 reqPrice;
        (requestId, reqPrice) = requestRandomnessPayInNative(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );

        // Store request status in separate mappings
        sRequestsFulfilled[requestId] = false;
        sRequestsPaid[requestId] = reqPrice;

        // Add to request IDs array and update last request ID
        requestIds.push(requestId);
        lastRequestId = requestId;

        emit RequestSent(requestId, numWords, reqPrice);

        return requestId;
    }

    /**
     * @dev Internal function to distribute ERC20 tokens to winner
     * @param recipient Address to receive tokens
     * @param amount Amount of tokens to mint
     */
    function mintDistributionReward(
        address recipient,
        uint256 amount
    ) internal {
        require(erc20TokenAddress != address(0), "Token not set");
        IERC20 token = IERC20(erc20TokenAddress);
        token.mint(recipient, amount);
    }

    /**
     * @dev Internal function to decide the winner from participants
     * @param randomWords Array of random words from VRF
     * @return winner The address of the winner
     */
    function decideWinner(
        uint256[] memory randomWords
    ) internal returns (address winner) {
        if (participants.length == 0 || randomWords.length == 0) {
            return address(0);
        }

        uint256 len = participants.length;
        uint256 idx = randomWords[0] % len;

        winner = participants[idx];

        if (winner != address(0)) {
            uint256 reward = lotteryEntryFee * len;
            delete participants; // Clear participants array
            mintDistributionReward(winner, reward);          
        }

        return winner;
    }

    /**
     * @dev Internal function to fulfill random words and select winner
     * @param requestId The VRF request ID
     * @param randomWords Array of random words from VRF
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        uint256 paidAmount = sRequestsPaid[requestId];
        require(paidAmount > 0, "Request not found");

        // Update request fulfillment status
        sRequestsFulfilled[requestId] = true;

        // Store random value for this request
        if (randomWords.length > 0) {
            sRequestsValue[requestId] = randomWords[0];
        }

        acceptingParticipants = false;

        address winnerAddress = decideWinner(randomWords);
        lastWinner = winnerAddress;

        emit RequestFulfilled(requestId, randomWords, winnerAddress);

        acceptingParticipants = true; // Accept new participants again
    }

    /**
     * @dev External function called by VRF wrapper to fulfill randomness
     * @param requestId The VRF request ID
     * @param randomWords Array of random words from VRF
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external nonReentrant {
        if (msg.sender != iVrfV2PlusWrapper) {
            revert OnlyVRFWrapperCanFulfill(msg.sender, iVrfV2PlusWrapper);
        }

        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Get the last winner address
     * @return The last winner address
     */
    function getLastWinner() external view returns (address) {
        return lastWinner;
    }

    /**
     * @dev Get the status of a randomness request
     * @param requestId The VRF request ID
     * @return paid The amount paid for the request
     * @return fulfilled Whether the request has been fulfilled
     * @return randomWord The random word returned (0 if not fulfilled)
     */
    function getRequestStatus(
        uint256 requestId
    ) external view returns (uint256 paid, bool fulfilled, uint256 randomWord) {
        paid = sRequestsPaid[requestId];
        require(paid > 0, "Request not found");
        
        fulfilled = sRequestsFulfilled[requestId];
        randomWord = sRequestsValue[requestId];
        
        return (paid, fulfilled, randomWord);
    }

    /**
     * @dev Get the last request ID
     * @return The last request ID (0 if no requests have been made)
     */
    function getLastRequestId() external view returns (uint256) {
        return lastRequestId;
    }

    /**
     * @dev View: get the current native price required to request randomness
     * @return The price in wei
     */
    function getRequestPrice() external view returns (uint256) {
        IVRFV2PlusWrapper vrfWrapper = IVRFV2PlusWrapper(iVrfV2PlusWrapper);
        return vrfWrapper.calculateRequestPriceNative(
            callbackGasLimit,
            numWords
        );
    }

    /**
     * @dev Withdraw native tokens (only owner)
     * @param amount The amount to withdraw in wei
     */
    function withdrawNative(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Set the ERC20 token address (only owner)
     * @param tokenAddress Address of the ERC20 token contract
     */
    function setErc20Token(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(0), "Token address cannot be zero");
        erc20TokenAddress = tokenAddress;
    }

    /**
     * @dev Participate in the lottery by paying the entry fee
     * Takes a flat amount from user's wallet and adds them to participants list
     */
    function participateInLottery() external payable nonReentrant {
        require(acceptingParticipants, "Not accepting participants");

        address msgSender = msg.sender;

        // Check if already participating
        for (uint256 i = 0; i < participants.length; i++) {
            require(
                participants[i] != msgSender,
                "Already participating"
            );
        }

        require(lotteryEntryFee > 0, "Fee not set");
        require(msg.value == lotteryEntryFee, "Wrong amount");

        participants.push(msgSender);
    }

    // lotteryEntryFee is public, so getter is automatically generated

    /**
     * @dev Set the lottery entry fee (only owner)
     * @param fee The entry fee in wei
     */
    function setLotteryEntryFee(uint256 fee) external onlyOwner {
        lotteryEntryFee = fee;
    }

    // lotteryIntervalHours is public, so getter is automatically generated

    /**
     * @dev Set the lottery interval in hours (only owner)
     * @param intervalHours The interval in hours
     */
    function setLotteryIntervalHours(
        uint256 intervalHours
    ) external onlyOwner {
        lotteryIntervalHours = intervalHours;
    }

    /**
     * @dev Get the number of participants
     * @return The number of participants
     */
    function getParticipantCount() external view returns (uint256) {
        return participants.length;
    }

    /**
     * @dev Get a participant address by index
     * @param index The index of the participant
     * @return The participant address
     */
    function getParticipantAddress(
        uint256 index
    ) external view returns (address) {
        require(index < participants.length, "Index out of bounds");
        return participants[index];
    }

    /**
     * @dev Receive function - handles incoming ETH
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev Prepare extra args for native payment to VRF wrapper
     * Format: abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs)
     * where EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1")) = 0x92fd1338
     * This matches the exact encoding format used in the Rust implementation
     * Format: [4 bytes tag][28 bytes padding][4 bytes bool][28 bytes padding] = 64 bytes total
     * @return extraArgs The encoded extra args (64 bytes total)
     */
    function getExtraArgsForNativePayment()
        internal
        pure
        returns (bytes memory)
    {
        // Manually construct the 64-byte encoding to match Rust implementation exactly
        // Rust format: [0x92, 0xfd, 0x13, 0x38][28 zeros][0x00, 0x00, 0x00, 0x01][28 zeros]
        // EXTRA_ARGS_V1_TAG = 0x92fd1338
        bytes memory extraArgs = new bytes(64);
        
        // Set the tag at the beginning (bytes 0-3)
        extraArgs[0] = 0x92;
        extraArgs[1] = 0xfd;
        extraArgs[2] = 0x13;
        extraArgs[3] = 0x38;
        
        // Bytes 4-31 are already zeros (padding)
        
        // Set nativePayment = true at bytes 32-35 (0x00000001)
        // The bool value is at the last byte of the 4-byte slot
        extraArgs[35] = 0x01; // nativePayment: true
        
        // Bytes 36-63 are already zeros (final padding)
        
        return extraArgs;
    }
}

