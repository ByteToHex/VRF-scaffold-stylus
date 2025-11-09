// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

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
contract VrfConsumer is Ownable {

    // VRF variables
    address public i_vrf_v2_plus_wrapper;
    uint256 public last_fulfilled_id;
    uint256 public last_fulfilled_value;

    uint256 public callback_gas_limit;
    uint256 public request_confirmations;
    uint256 public num_words;

    // Event variables
    bool public accepting_participants;
    uint256 public lottery_interval_hours;
    uint256 public last_request_timestamp;

    // Token distribution variables
    address public erc20_token_address;
    address[] public participants;
    uint256 public lottery_entry_fee;

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
     * @param vrf_v2_plus_wrapper Address of the VRF V2+ wrapper contract
     * @param owner Initial owner address
     */
    constructor(address vrf_v2_plus_wrapper, address owner) Ownable(owner) {
        i_vrf_v2_plus_wrapper = vrf_v2_plus_wrapper;
        erc20_token_address = address(0);

        lottery_entry_fee = 500000; // 0.0005 ETH in wei
        lottery_interval_hours = 4;
        accepting_participants = true;

        callback_gas_limit = 100000;
        request_confirmations = 3;
        num_words = 1;
    }

    /**
     * @dev Internal function to request randomness paying in native ETH
     * @param callbackGasLimit Gas limit for the callback
     * @param requestConfirmations Number of confirmations to wait
     * @param numWords Number of random words to request
     * @return requestId The VRF request ID
     * @return reqPrice The price paid for the request
     */
    function requestRandomnessPayInNative(
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords
    ) internal returns (uint256 requestId, uint256 reqPrice) {
        IVRFV2PlusWrapper vrfWrapper = IVRFV2PlusWrapper(i_vrf_v2_plus_wrapper);
        require(
            i_vrf_v2_plus_wrapper.code.length > 0,
            "VRF wrapper contract does not exist at given address"
        );

        // Calculate request price
        reqPrice = vrfWrapper.calculateRequestPriceNative(
            callbackGasLimit,
            numWords
        );

        // Prepare extra args for native payment
        bytes memory extraArgs = getExtraArgsForNativePayment();

        // Request random words
        requestId = vrfWrapper.requestRandomWordsInNative{value: reqPrice}(
            callbackGasLimit,
            requestConfirmations,
            numWords,
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
        uint256 intervalSecs = lottery_interval_hours * 3600;
        require(
            block.timestamp >= last_request_timestamp + intervalSecs,
            "Too soon to resolve lottery"
        );

        // casting to 'uint32' is safe because callback_gas_limit is initialized to 100000 and will not exceed uint32 max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 callbackGasLimit = uint32(callback_gas_limit);
        // casting to 'uint16' is safe because request_confirmations is initialized to 3 and will not exceed uint16 max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 requestConfirmations = uint16(request_confirmations);
        // casting to 'uint32' is safe because num_words is initialized to 1 and will not exceed uint32 max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 numWordsValue = uint32(num_words);

        uint256 reqPrice;
        (requestId, reqPrice) = requestRandomnessPayInNative(
            callbackGasLimit,
            requestConfirmations,
            numWordsValue
        );

        last_request_timestamp = block.timestamp;

        emit RequestSent(requestId, numWordsValue, reqPrice);

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
        require(erc20_token_address != address(0), "Token not set");
        IERC20 token = IERC20(erc20_token_address);
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
            uint256 reward = lottery_entry_fee * len;
            mintDistributionReward(winner, reward);

            // Clear participants array
            delete participants;
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
        // Store only the last fulfilled request
        uint256 fulfilledValue = randomWords.length > 0
            ? randomWords[0]
            : 0;

        last_fulfilled_id = requestId;
        last_fulfilled_value = fulfilledValue;
        accepting_participants = false;

        address winnerAddress = decideWinner(randomWords);

        emit RequestFulfilled(requestId, randomWords, winnerAddress);

        accepting_participants = true; // Accept new participants again
    }

    /**
     * @dev External function called by VRF wrapper to fulfill randomness
     * @param requestId The VRF request ID
     * @param randomWords Array of random words from VRF
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != i_vrf_v2_plus_wrapper) {
            revert OnlyVRFWrapperCanFulfill(msg.sender, i_vrf_v2_plus_wrapper);
        }

        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Get the last fulfilled request ID
     * @return The last fulfilled request ID
     */
    function getLastFulfilledId() external view returns (uint256) {
        return last_fulfilled_id;
    }

    /**
     * @dev Get the last fulfilled random value
     * @return The last fulfilled random value
     */
    function getLastFulfilledValue() external view returns (uint256) {
        return last_fulfilled_value;
    }

    /**
     * @dev Set the ERC20 token address (only owner)
     * @param tokenAddress Address of the ERC20 token contract
     */
    function setErc20Token(address tokenAddress) external onlyOwner {
        erc20_token_address = tokenAddress;
    }

    /**
     * @dev Participate in the lottery by paying the entry fee
     * Takes a flat amount from user's wallet and adds them to participants list
     */
    function participateInLottery() external payable {
        require(accepting_participants, "Not accepting participants");

        address msgSender = msg.sender;

        // Check if already participating
        for (uint256 i = 0; i < participants.length; i++) {
            require(
                participants[i] != msgSender,
                "Already participating"
            );
        }

        require(lottery_entry_fee > 0, "Fee not set");
        require(msg.value == lottery_entry_fee, "Wrong amount");

        participants.push(msgSender);
    }

    /**
     * @dev Get the lottery entry fee
     * @return The entry fee in wei
     */
    function lotteryEntryFee() external view returns (uint256) {
        return lottery_entry_fee;
    }

    /**
     * @dev Set the lottery entry fee (only owner)
     * @param fee The entry fee in wei
     */
    function setLotteryEntryFee(uint256 fee) external onlyOwner {
        lottery_entry_fee = fee;
    }

    /**
     * @dev Get the lottery interval in hours
     * @return The interval in hours
     */
    function lotteryIntervalHours() external view returns (uint256) {
        return lottery_interval_hours;
    }

    /**
     * @dev Set the lottery interval in hours (only owner)
     * @param intervalHours The interval in hours
     */
    function setLotteryIntervalHours(
        uint256 intervalHours
    ) external onlyOwner {
        lottery_interval_hours = intervalHours;
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
     * @return extraArgs The encoded extra args
     */
    function getExtraArgsForNativePayment()
        internal
        pure
        returns (bytes memory)
    {
        // EXTRA_ARGS_V1_TAG = 0x92fd1338
        bytes4 tag = 0x92fd1338;
        // Struct: { bool nativePayment }
        // nativePayment = true
        bool nativePayment = true;

        return abi.encodeWithSelector(tag, nativePayment);
    }
}

