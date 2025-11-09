// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Example} from "../contracts/ERC20Example.sol";
import {VrfConsumer} from "../contracts/VrfConsumer.sol";
import {MockVRFV2PlusWrapper} from "./mocks/MockVRFV2PlusWrapper.sol";

/**
 * @title VrfConsumerE2ETest
 * @dev Full end-to-end tests covering complete lottery flow from deployment
 * to winner selection and token distribution
 */
contract VrfConsumerE2ETest is Test {
    ERC20Example public token;
    VrfConsumer public vrfConsumer;
    MockVRFV2PlusWrapper public mockVrfWrapper;
    
    address public owner;
    address public participant1;
    address public participant2;
    address public participant3;
    address public nonParticipant;
    
    // Token parameters
    string constant TOKEN_NAME = "LotteryToken";
    string constant TOKEN_SYMBOL = "LOT";
    uint256 constant TOKEN_CAP = 10_000_000 * 10**10; // 10M tokens with 10 decimals
    
    // VRF parameters
    uint256 constant REQUEST_PRICE = 0.001 ether;
    
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
    
    function setUp() public {
        // Setup accounts
        owner = address(this);
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");
        participant3 = makeAddr("participant3");
        nonParticipant = makeAddr("nonParticipant");
        
        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(participant1, 10 ether);
        vm.deal(participant2, 10 ether);
        vm.deal(participant3, 10 ether);
        vm.deal(nonParticipant, 10 ether);
        
        // Deploy mock VRF wrapper
        mockVrfWrapper = new MockVRFV2PlusWrapper(REQUEST_PRICE);
        
        // Deploy ERC20 token
        token = new ERC20Example(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_CAP,
            owner
        );
        
        // Deploy VRF consumer
        vrfConsumer = new VrfConsumer(address(mockVrfWrapper), owner);
        
        // Setup integration
        token.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(token));
    }
    
    // ============ Contract Deployment Tests ============
    
    /**
     * @dev Test contract deployment and initial state
     */
    function test_ContractDeployment_InitialState() public view {
        // Verify ERC20 token initial state
        assertEq(token.name(), TOKEN_NAME, "Token name should match");
        assertEq(token.symbol(), TOKEN_SYMBOL, "Token symbol should match");
        assertEq(token.cap(), TOKEN_CAP, "Token cap should match");
        assertEq(token.totalSupply(), 0, "Initial supply should be zero");
        assertEq(token.decimals(), 10, "Decimals should be 10");
        assertEq(token.owner(), owner, "Owner should be set correctly");
        
        // Verify VRF consumer initial state
        assertEq(vrfConsumer.iVrfV2PlusWrapper(), address(mockVrfWrapper), "VRF wrapper should be set");
        assertEq(vrfConsumer.erc20TokenAddress(), address(token), "ERC20 token address should be set");
        assertEq(vrfConsumer.lotteryEntryFee(), 500000, "Entry fee should be 500000 wei");
        assertEq(vrfConsumer.lotteryIntervalHours(), 4, "Lottery interval should be 4 hours");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants initially");
        assertEq(vrfConsumer.getParticipantCount(), 0, "Initial participant count should be zero");
        assertEq(vrfConsumer.lastFulfilledId(), 0, "Initial fulfilled ID should be zero");
        assertEq(vrfConsumer.lastFulfilledValue(), 0, "Initial fulfilled value should be zero");
    }
    
    // ============ Contract Integration Setup Tests ============
    
    /**
     * @dev Test setting up contract integration
     */
    function test_ContractIntegrationSetup() public view {
        // Verify integration setup from setUp
        assertEq(token.getAuthorizedMinter(), address(vrfConsumer), "VrfConsumer should be authorized minter");
        assertEq(vrfConsumer.erc20TokenAddress(), address(token), "Token address should be set on VrfConsumer");
    }
    
    // ============ Lottery Participation Flow Tests ============
    
    /**
     * @dev Test single participant entry
     */
    function test_LotteryParticipation_SingleParticipant() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        assertEq(vrfConsumer.getParticipantCount(), 1, "Should have 1 participant");
        assertEq(vrfConsumer.getParticipantAddress(0), participant1, "Participant1 should be at index 0");
    }
    
    /**
     * @dev Test multiple participants entry
     */
    function test_LotteryParticipation_MultipleParticipants() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant3);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        assertEq(vrfConsumer.getParticipantCount(), 3, "Should have 3 participants");
        assertEq(vrfConsumer.getParticipantAddress(0), participant1, "Participant1 should be at index 0");
        assertEq(vrfConsumer.getParticipantAddress(1), participant2, "Participant2 should be at index 1");
        assertEq(vrfConsumer.getParticipantAddress(2), participant3, "Participant3 should be at index 2");
    }
    
    /**
     * @dev Test duplicate participation prevention
     */
    function test_LotteryParticipation_DuplicatePrevention() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Try to participate again
        vm.prank(participant1);
        vm.expectRevert("Already participating");
        vrfConsumer.participateInLottery{value: entryFee}();
    }
    
    /**
     * @dev Test wrong fee amount rejection
     */
    function test_LotteryParticipation_WrongFeeAmount() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vm.expectRevert("Wrong amount");
        vrfConsumer.participateInLottery{value: entryFee - 1}();
        
        vm.prank(participant1);
        vm.expectRevert("Wrong amount");
        vrfConsumer.participateInLottery{value: entryFee + 1}();
    }
    
    /**
     * @dev Test participation when not accepting participants
     */
    function test_LotteryParticipation_NotAccepting() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Initially, should be accepting participants
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants initially");
        
        // Add a participant and fulfill to test the flow
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward and fulfill
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        
        // During fulfillment, acceptingParticipants is set to false temporarily
        // After fulfillment, it's set back to true
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // After fulfillment, should be accepting participants again
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants after fulfillment");
    }
    
    // ============ VRF Request Flow Tests ============
    
    /**
     * @dev Test requesting random words
     */
    function test_VRFRequest_RequestRandomWords() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Add participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward time
        uint256 intervalSecs = vrfConsumer.lotteryIntervalHours() * 3600;
        vm.warp(block.timestamp + intervalSecs + 1);
        
        // Fund VRF consumer for request
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        // Request random words
        vm.expectEmit(true, false, false, true);
        emit RequestSent(0, uint32(vrfConsumer.numWords()), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        assertEq(requestId, 0, "Request ID should be 0 for first request");
        assertEq(vrfConsumer.lastRequestTimestamp(), block.timestamp, "Last request timestamp should be updated");
    }
    
    /**
     * @dev Test time interval enforcement
     */
    function test_VRFRequest_TimeIntervalEnforcement() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Calculate expected price for later use
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        
        uint256 intervalSecs = vrfConsumer.lotteryIntervalHours() * 3600;
        
        // Try to request immediately - should fail due to time interval
        // lastRequestTimestamp is 0, so we need block.timestamp >= 0 + intervalSecs
        // Since block.timestamp starts small, this should fail
        vm.deal(address(vrfConsumer), expectedPrice);
        vm.expectRevert("Too soon to resolve lottery");
        vrfConsumer.requestRandomWords();
        
        // Fast forward but not enough - warp to a time that's still less than intervalSecs from 0
        // Since lastRequestTimestamp is still 0 (first call reverted), we need block.timestamp < intervalSecs
        vm.warp(intervalSecs - 1);
        
        vm.expectRevert("Too soon to resolve lottery");
        vrfConsumer.requestRandomWords();
        
        // Fast forward enough time - now block.timestamp should be >= intervalSecs
        vm.warp(intervalSecs);
        
        // Should succeed now
        vrfConsumer.requestRandomWords();
    }
    
    /**
     * @dev Test request price calculation
     */
    function test_VRFRequest_PriceCalculation() public view {
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        
        assertEq(expectedPrice, REQUEST_PRICE * vrfConsumer.numWords(), "Price should match");
    }
    
    // ============ VRF Fulfillment and Winner Selection Tests ============
    
    /**
     * @dev Test VRF fulfillment and winner selection
     */
    function test_VRFFulfillment_WinnerSelection() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Add participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant3);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        uint256 participantCount = vrfConsumer.getParticipantCount();
        assertEq(participantCount, 3, "Should have 3 participants");
        
        // Fast forward and request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        // Fulfill randomness
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 7; // 7 % 3 = 1, so participant2 should win
        
        address expectedWinner = participant2;
        uint256 expectedReward = entryFee * participantCount;
        
        vm.expectEmit(true, true, true, true);
        emit RequestFulfilled(requestId, randomWords, expectedWinner);
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify state updates
        assertEq(vrfConsumer.lastFulfilledId(), requestId, "Last fulfilled ID should be updated");
        assertEq(vrfConsumer.lastFulfilledValue(), randomWords[0], "Last fulfilled value should be updated");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants again");
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants array should be cleared");
        
        // Verify winner received tokens
        assertEq(token.balanceOf(expectedWinner), expectedReward, "Winner should receive correct reward");
        assertEq(token.totalSupply(), expectedReward, "Total supply should match reward");
    }
    
    /**
     * @dev Test token minting to winner with correct amount
     */
    function test_VRFFulfillment_TokenMintingAmount() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Add 5 participants
        address[5] memory participants = [
            makeAddr("p1"),
            makeAddr("p2"),
            makeAddr("p3"),
            makeAddr("p4"),
            makeAddr("p5")
        ];
        
        for (uint256 i = 0; i < 5; i++) {
            vm.deal(participants[i], 10 ether);
            vm.prank(participants[i]);
            vrfConsumer.participateInLottery{value: entryFee}();
        }
        
        uint256 participantCount = vrfConsumer.getParticipantCount();
        uint256 expectedReward = entryFee * participantCount;
        
        // Fast forward and fulfill
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 3; // 3 % 5 = 3, so participants[3] wins
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        address winner = participants[3];
        
        assertEq(token.balanceOf(winner), expectedReward, "Winner should receive entry_fee * participant_count");
        assertEq(token.totalSupply(), expectedReward, "Total supply should equal reward");
    }
    
    /**
     * @dev Test participants array is cleared after selection
     */
    function test_VRFFulfillment_ParticipantsCleared() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        assertEq(vrfConsumer.getParticipantCount(), 2, "Should have 2 participants");
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants should be cleared");
        
        // Try to get participant at index 0 - should revert
        vm.expectRevert("Index out of bounds");
        vrfConsumer.getParticipantAddress(0);
    }
    
    // ============ Multiple Lottery Rounds Tests ============
    
    /**
     * @dev Test multiple consecutive lottery rounds
     */
    function test_MultipleRounds_ConsecutiveLotteries() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Round 1
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId1 = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords1 = new uint256[](1);
        randomWords1[0] = 0; // participant1 wins
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId1, randomWords1);
        
        uint256 round1Reward = entryFee * 2;
        assertEq(token.balanceOf(participant1), round1Reward, "Participant1 should win round 1");
        
        // Round 2
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant3);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId2 = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords2 = new uint256[](1);
        randomWords2[0] = 1; // participant3 wins
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId2, randomWords2);
        
        uint256 round2Reward = entryFee * 2;
        assertEq(token.balanceOf(participant3), round2Reward, "Participant3 should win round 2");
        assertEq(token.totalSupply(), round1Reward + round2Reward, "Total supply should reflect both rounds");
    }
    
    // ============ Edge Cases Tests ============
    
    /**
     * @dev Test zero participants scenario
     */
    function test_EdgeCase_ZeroParticipants() public {
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        
        // Should not revert, but winner should be address(0)
        vm.expectEmit(true, true, true, true);
        emit RequestFulfilled(requestId, randomWords, address(0));
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participant count should remain 0");
        assertEq(token.totalSupply(), 0, "No tokens should be minted");
    }
    
    /**
     * @dev Test single participant scenario
     */
    function test_EdgeCase_SingleParticipant() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 999; // 999 % 1 = 0, so participant1 wins
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        uint256 expectedReward = entryFee * 1;
        assertEq(token.balanceOf(participant1), expectedReward, "Single participant should win");
    }
    
    /**
     * @dev Test token cap enforcement during minting
     */
    function test_EdgeCase_TokenCapEnforcement() public {
        // Create token with low cap
        uint256 lowCap = 1000 * 10**10;
        ERC20Example lowCapToken = new ERC20Example(
            "LowCap",
            "LC",
            lowCap,
            owner
        );
        
        lowCapToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(lowCapToken));
        
        // Set entry fee that would cause reward to exceed cap
        uint256 highEntryFee = lowCap / 2 + 1; // Would need 2+ participants to exceed
        vrfConsumer.setLotteryEntryFee(highEntryFee);
        
        vm.deal(participant1, 10 ether);
        vm.deal(participant2, 10 ether);
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: highEntryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: highEntryFee}();
        
        // Reward would be highEntryFee * 2 = lowCap + 2, which exceeds cap
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        
        vm.prank(address(mockVrfWrapper));
        vm.expectRevert("ERC20Example: cap exceeded");
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
    }
    
    /**
     * @dev Test time interval restrictions
     */
    function test_EdgeCase_TimeIntervalRestrictions() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Request once
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        vrfConsumer.requestRandomWords();
        
        // Try to request again immediately - should fail
        vm.expectRevert("Too soon to resolve lottery");
        vrfConsumer.requestRandomWords();
        
        // Fast forward enough time
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        vm.deal(address(vrfConsumer), expectedPrice);
        
        // Should succeed now
        vrfConsumer.requestRandomWords();
    }
    
    // ============ Access Control Tests ============
    
    /**
     * @dev Test owner-only functions
     */
    function test_AccessControl_OwnerOnlyFunctions() public {
        // setErc20Token
        vm.prank(participant1);
        vm.expectRevert();
        vrfConsumer.setErc20Token(address(token));
        
        // setLotteryEntryFee
        vm.prank(participant1);
        vm.expectRevert();
        vrfConsumer.setLotteryEntryFee(1000);
        
        // setLotteryIntervalHours
        vm.prank(participant1);
        vm.expectRevert();
        vrfConsumer.setLotteryIntervalHours(2);
        
        // Owner should be able to call these
        vrfConsumer.setLotteryEntryFee(1000);
        assertEq(vrfConsumer.lotteryEntryFee(), 1000, "Owner should be able to set entry fee");
        
        vrfConsumer.setLotteryIntervalHours(2);
        assertEq(vrfConsumer.lotteryIntervalHours(), 2, "Owner should be able to set interval");
    }
    
    /**
     * @dev Test VRF wrapper-only fulfillment
     */
    function test_AccessControl_VRFWrapperOnlyFulfillment() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        
        // Non-VRF wrapper should not be able to fulfill
        vm.prank(participant1);
        vm.expectRevert();
        vrfConsumer.rawFulfillRandomWords(requestId, randomWords);
        
        // VRF wrapper should be able to fulfill
        vm.prank(address(mockVrfWrapper));
        vrfConsumer.rawFulfillRandomWords(requestId, randomWords);
    }
    
    /**
     * @dev Test unauthorized access attempts
     */
    function test_AccessControl_UnauthorizedAccess() public {
        // Try to set authorized minter as non-owner
        vm.prank(participant1);
        vm.expectRevert();
        token.setAuthorizedMinter(participant1);
        
        // Try to change owner functions
        vm.prank(participant1);
        vm.expectRevert();
        vrfConsumer.setErc20Token(address(token));
    }
    
    /**
     * @dev Test receive function
     */
    function test_ReceiveFunction() public {
        vm.expectEmit(true, false, false, true);
        emit Received(participant1, 1 ether);
        
        vm.prank(participant1);
        (bool success, ) = address(vrfConsumer).call{value: 1 ether}("");
        assertTrue(success, "Receive should succeed");
    }
}

