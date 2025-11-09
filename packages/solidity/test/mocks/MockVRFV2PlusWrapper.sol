// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../contracts/VrfConsumer.sol";

/**
 * @title MockVRFV2PlusWrapper
 * @dev Mock VRF V2+ Wrapper for testing purposes
 * Allows manual triggering of randomness fulfillment for testing
 */
contract MockVRFV2PlusWrapper is IVRFV2PlusWrapper {
    // Mapping to store pending requests
    mapping(uint256 => Request) public requests;
    
    // Counter for request IDs
    uint256 private requestIdCounter;
    
    // Configurable request price
    uint256 public requestPrice;
    
    // Struct to store request details
    struct Request {
        address consumer;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        uint32 numWords;
        bool fulfilled;
    }
    
    // Events
    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords
    );
    
    event RandomWordsFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords
    );
    
    /**
     * @dev Constructor
     * @param _requestPrice The price for each VRF request in wei
     */
    constructor(uint256 _requestPrice) {
        requestPrice = _requestPrice;
    }
    
    /**
     * @dev Calculate the request price in native tokens
     * @param _callbackGasLimit Gas limit for the callback
     * @param _numWords Number of random words requested
     * @return The price in wei
     */
    function calculateRequestPriceNative(
        uint32 _callbackGasLimit,
        uint32 _numWords
    ) public view override returns (uint256) {
        // Simple pricing: base price * numWords
        return requestPrice * _numWords;
    }
    
    /**
     * @dev Request random words (mock implementation)
     * @param _callbackGasLimit Gas limit for the callback
     * @param _requestConfirmations Number of confirmations to wait
     * @param _numWords Number of random words to request
     * @param extraArgs Extra arguments (not used in mock)
     * @return requestId The request ID
     */
    function requestRandomWordsInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        bytes calldata extraArgs
    ) external payable override returns (uint256 requestId) {
        require(msg.value >= calculateRequestPriceNative(_callbackGasLimit, _numWords), "Insufficient payment");
        
        requestId = requestIdCounter++;
        
        requests[requestId] = Request({
            consumer: msg.sender,
            callbackGasLimit: _callbackGasLimit,
            requestConfirmations: _requestConfirmations,
            numWords: _numWords,
            fulfilled: false
        });
        
        emit RandomWordsRequested(
            requestId,
            msg.sender,
            _callbackGasLimit,
            _requestConfirmations,
            _numWords
        );
        
        return requestId;
    }
    
    /**
     * @dev Fulfill a random words request (for testing)
     * @param requestId The request ID to fulfill
     * @param randomWords The random words to fulfill with
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        Request storage request = requests[requestId];
        require(!request.fulfilled, "Request already fulfilled");
        require(request.consumer != address(0), "Request does not exist");
        
        request.fulfilled = true;
        
        // Call the consumer's rawFulfillRandomWords function
        VrfConsumer consumer = VrfConsumer(payable(request.consumer));
        consumer.rawFulfillRandomWords(requestId, randomWords);
        
        emit RandomWordsFulfilled(requestId, randomWords);
    }
    
    /**
     * @dev Set the request price (for testing flexibility)
     * @param _requestPrice New request price in wei
     */
    function setRequestPrice(uint256 _requestPrice) external {
        requestPrice = _requestPrice;
    }
    
    /**
     * @dev Get request details
     * @param requestId The request ID
     * @return consumer The consumer address
     * @return callbackGasLimit The callback gas limit
     * @return requestConfirmations The number of confirmations
     * @return numWords The number of words requested
     * @return fulfilled Whether the request has been fulfilled
     */
    function getRequest(
        uint256 requestId
    ) external view returns (
        address consumer,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        bool fulfilled
    ) {
        Request memory request = requests[requestId];
        return (
            request.consumer,
            request.callbackGasLimit,
            request.requestConfirmations,
            request.numWords,
            request.fulfilled
        );
    }
}

