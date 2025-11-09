// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ERC20 interface - minimal interface with only functions we use
interface IERC20 {
    function mint(address account, uint256 value) external;
}

/**
 * @title VrfSubstitute
 * @dev A lottery contract that uses block number and timestamp to generate pseudo-randomness
 * instead of Chainlink VRF. Participants pay an entry fee and a winner is selected using
 * block-based randomness. This is NOT cryptographically secure randomness and should only
 * be used for testing or non-critical applications.
 * This contract matches the functionality of VrfConsumer but without external VRF dependency
 */
contract VrfSubstitute is Ownable, ReentrancyGuard {

    address public lastWinner;

    // Event variables
    bool public acceptingParticipants;
    uint256 public lotteryIntervalHours;
    uint256 public lastRequestTimestamp;

    // Token distribution variables
    address public erc20TokenAddress;
    address[] public participants;
    uint256 public lotteryEntryFee;

    // Events
    event LotteryResolved(
        uint256 indexed blockNumber,
        uint256 timestamp,
        uint256 randomValue,
        address winner
    );
    event Received(address indexed sender, uint256 value);

    /**
     * @dev Constructor - initializes the contract with owner
     * @param owner Initial owner address
     */
    constructor(address owner) Ownable(owner) {
        erc20TokenAddress = address(0);

        lotteryEntryFee = 500000; // 0.0005 ETH in wei
        lotteryIntervalHours = 4;
        acceptingParticipants = true;
    }

    /**
     * @dev Generate pseudo-random number using block number and timestamp
     * WARNING: This is NOT cryptographically secure. Miners can manipulate block.timestamp
     * and block.number is predictable. Use only for testing or non-critical applications.
     * @return randomValue A pseudo-random number
     */
    function generateRandomValue() internal view returns (uint256 randomValue) {
        // Combine block number, timestamp, and participants data for entropy
        // Using keccak256 to mix the values
        randomValue = uint256(
            keccak256(
                abi.encodePacked(
                    block.number,
                    block.timestamp,
                    participants.length,
                    block.prevrandao, // Additional entropy from block (if available)
                    blockhash(block.number - 1) // Previous block hash
                )
            )
        );
        return randomValue;
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
     * @param randomValue Random value to use for selection
     * @return winner The address of the winner
     */
    function decideWinner(
        uint256 randomValue
    ) internal returns (address winner) {
        if (participants.length == 0) {
            return address(0);
        }

        uint256 len = participants.length;
        uint256 idx = randomValue % len;

        winner = participants[idx];

        if (winner != address(0)) {
            uint256 reward = lotteryEntryFee * len;
            delete participants; // Clear participants array
            mintDistributionReward(winner, reward);          
        }

        return winner;
    }

    /**
     * @dev Resolve the lottery by generating randomness and selecting winner
     * This function immediately resolves the lottery (no async callback needed)
     * @return winner The address of the winner
     */
    function resolveLottery() external nonReentrant returns (address winner) {
        // Check if enough time has passed since last request
        // Allow first call when lastRequestTimestamp is 0
        if (lastRequestTimestamp > 0) {
            uint256 intervalSecs = lotteryIntervalHours * 3600;
            require(
                block.timestamp >= lastRequestTimestamp + intervalSecs,
                "Too soon to resolve lottery"
            );
        }

        // Update state BEFORE generating randomness (Checks-Effects-Interactions pattern)
        lastRequestTimestamp = block.timestamp;
        acceptingParticipants = false;

        // Generate pseudo-random value
        uint256 randomValue = generateRandomValue();

        // Select winner
        address winnerAddress = decideWinner(randomValue);
        lastWinner = winnerAddress;

        emit LotteryResolved(block.number, block.timestamp, randomValue, winnerAddress);

        acceptingParticipants = true; // Accept new participants again

        return winnerAddress;
    }

    /**
     * @dev Get the last winner address
     * @return The last winner address
     */
    function getLastWinner() external view returns (address) {
        return lastWinner;
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
}

