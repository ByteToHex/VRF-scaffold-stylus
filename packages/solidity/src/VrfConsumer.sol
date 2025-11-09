// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VrfConsumer
 * @dev VRF consumer contract that requests randomness from Chainlink VRF V2+ wrapper
 * using native tokens (ETH) for payment. This is the Solidity equivalent of the Stylus vrf-consumer contract.
 */
interface IERC20Mintable {
    function mint(address account, uint256 value) external;
}

interface IVRFV2PlusWrapper {
    function calculateRequestPriceNative(uint32 _callbackGasLimit, uint32 _numWords) external view returns (uint256);
    function requestRandomWordsInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        bytes calldata extraArgs
    ) external payable returns (uint256 requestId);
}

contract VrfConsumer is Ownable {
    // VRF variables
    IVRFV2PlusWrapper public i_vrfV2PlusWrapper;
    uint256 public lastFulfilledId;
    uint256 public lastFulfilledValue;

    // VRF configuration
    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    // Lottery variables
    bool public acceptingParticipants;
    uint256 public lotteryIntervalHours;
    uint256 public lastRequestTimestamp;
    address public erc20TokenAddress;
    address[] public participants;
    uint256 public lotteryEntryFee;

    // Events
    event RequestSent(uint256 indexed requestId, uint32 numWords, uint256 payment);
    event RequestFulfilled(uint256 indexed requestId, uint256[] randomWords, address winner);
    event Received(address indexed sender, uint256 value);

    // Errors
    error OnlyVRFWrapperCanFulfill(address have, address want);

    /**
     * @dev Constructor
     * @param vrfV2PlusWrapper Address of the VRF V2+ wrapper contract
     * @param owner Initial owner address
     */
    constructor(
        address vrfV2PlusWrapper,
        address owner
    ) Ownable(owner) {
        i_vrfV2PlusWrapper = IVRFV2PlusWrapper(vrfV2PlusWrapper);
        lotteryEntryFee = 500000; // 0.0005 ETH in wei
        lotteryIntervalHours = 4;
        acceptingParticipants = true;
        callbackGasLimit = 100000;
        requestConfirmations = 3;
        numWords = 1;
    }

    /**
     * @dev Request random words from VRF
     * @return requestId The request ID
     */
    function requestRandomWords() external returns (uint256) {
        require(
            block.timestamp >= lastRequestTimestamp + (lotteryIntervalHours * 3600),
            "Too soon to resolve lottery"
        );

        uint256 requestPrice = i_vrfV2PlusWrapper.calculateRequestPriceNative(callbackGasLimit, numWords);
        require(address(this).balance >= requestPrice, "Insufficient balance for VRF request");

        // Prepare extra args for native payment
        bytes memory extraArgs = abi.encodePacked(
            bytes4(0x92fd1338), // EXTRA_ARGS_V1_TAG
            bytes28(0),
            uint32(1) // nativePayment: true
        );

        uint256 requestId = i_vrfV2PlusWrapper.requestRandomWordsInNative{value: requestPrice}(
            callbackGasLimit,
            requestConfirmations,
            numWords,
            extraArgs
        );

        lastRequestTimestamp = block.timestamp;

        emit RequestSent(requestId, numWords, requestPrice);

        return requestId;
    }

    /**
     * @dev Fulfill random words callback from VRF wrapper
     * This function is called by the VRF wrapper
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        require(msg.sender == address(i_vrfV2PlusWrapper), "Only VRF wrapper can fulfill");
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Internal function to fulfill random words
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal {
        uint256 fulfilledValue = randomWords.length > 0 ? randomWords[0] : 0;

        lastFulfilledId = requestId;
        lastFulfilledValue = fulfilledValue;
        acceptingParticipants = false;

        address winner = decideWinner(randomWords);

        emit RequestFulfilled(requestId, randomWords, winner);

        acceptingParticipants = true;
    }

    /**
     * @dev Internal function to decide the winner
     * @param randomWords Array of random words
     * @return winner The winner address
     */
    function decideWinner(uint256[] memory randomWords) internal returns (address) {
        if (participants.length == 0 || randomWords.length == 0) {
            return address(0);
        }

        uint256 len = participants.length;
        uint256 idx = randomWords[0] % len;

        address winner = participants[idx];

        if (winner != address(0)) {
            uint256 reward = lotteryEntryFee * len;
            mintDistributionReward(winner, reward);

            // Clear participants array
            delete participants;
        }

        return winner;
    }

    /**
     * @dev Internal function to mint ERC20 tokens as reward
     * @param recipient Address to receive tokens
     * @param amount Amount of tokens to mint
     */
    function mintDistributionReward(address recipient, uint256 amount) internal {
        require(erc20TokenAddress != address(0), "Token not set");
        IERC20Mintable token = IERC20Mintable(erc20TokenAddress);
        token.mint(recipient, amount);
    }

    /**
     * @dev Participate in the lottery by paying the entry fee
     */
    function participateInLottery() external payable {
        require(acceptingParticipants, "Not accepting participants");

        address msgSender = msg.sender;
        for (uint256 i = 0; i < participants.length; i++) {
            require(participants[i] != msgSender, "Already participating");
        }

        require(lotteryEntryFee > 0, "Fee not set");
        require(msg.value == lotteryEntryFee, "Wrong amount");

        participants.push(msgSender);
    }

    /**
     * @dev Set ERC20 token address (only owner)
     * @param tokenAddress Address of the ERC20 token contract
     */
    function setErc20Token(address tokenAddress) external onlyOwner {
        erc20TokenAddress = tokenAddress;
    }

    /**
     * @dev Set lottery entry fee (only owner)
     * @param fee Entry fee in wei
     */
    function setLotteryEntryFee(uint256 fee) external onlyOwner {
        lotteryEntryFee = fee;
    }

    /**
     * @dev Set lottery interval hours (only owner)
     * @param intervalHours Interval in hours
     */
    function setLotteryIntervalHours(uint256 intervalHours) external onlyOwner {
        lotteryIntervalHours = intervalHours;
    }

    /**
     * @dev Get the VRF wrapper address
     * @return The VRF wrapper address
     */
    function iVrfV2PlusWrapper() external view returns (address) {
        return address(i_vrfV2PlusWrapper);
    }

    /**
     * @dev Get last fulfilled request ID
     * @return The last fulfilled request ID
     */
    function getLastFulfilledId() external view returns (uint256) {
        return lastFulfilledId;
    }

    /**
     * @dev Get last fulfilled random value
     * @return The last fulfilled random value
     */
    function getLastFulfilledValue() external view returns (uint256) {
        return lastFulfilledValue;
    }

    /**
     * @dev Receive function to handle incoming ETH
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

