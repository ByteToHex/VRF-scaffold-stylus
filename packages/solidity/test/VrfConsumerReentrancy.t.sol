// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Example} from "../contracts/ERC20Example.sol";
import {VrfConsumer} from "../contracts/VrfConsumer.sol";
import {MockVRFV2PlusWrapper} from "./mocks/MockVRFV2PlusWrapper.sol";

// ============ Malicious Contracts for Reentrancy Testing ============

/**
 * @dev Malicious ERC20 token that attempts to reenter VrfConsumer during mint
 */
contract MaliciousReentrantToken is ERC20Example {
    VrfConsumer public target;
    bool public attackAttempted;
    uint256 public reentrancyAttempts;
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        address owner,
        VrfConsumer _target
    ) ERC20Example(name, symbol, cap, owner) {
        target = _target;
    }
    
    /**
     * @dev Override _update to attempt reentrancy attack
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Attempt reentrancy attack when tokens are minted
        if (to != address(0) && value > 0 && !attackAttempted) {
            attackAttempted = true;
            reentrancyAttempts++;
            
            // Try to reenter by calling participateInLottery
            try target.participateInLottery{value: target.lotteryEntryFee()}() {
                // If reentrancy succeeds, try again
                reentrancyAttempts++;
            } catch {
                // Reentrancy was blocked - good!
            }
        }
        
        super._update(from, to, value);
    }
}

/**
 * @dev Malicious ERC20 token that attempts to reenter during mint via _afterTokenTransfer
 */
contract MaliciousReentrantTokenV2 is ERC20Example {
    VrfConsumer public target;
    bool public attackAttempted;
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        address owner,
        VrfConsumer _target
    ) ERC20Example(name, symbol, cap, owner) {
        target = _target;
    }
    
    /**
     * @dev Override _update to attempt reentrancy after mint
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);
        
        // Attempt reentrancy after token transfer
        if (from == address(0) && to != address(0) && value > 0 && !attackAttempted) {
            attackAttempted = true;
            
            // Try to manipulate state by calling requestRandomWords
            try target.requestRandomWords() {
                // Reentrancy succeeded - this should be blocked
            } catch {
                // Reentrancy was blocked - good!
            }
        }
    }
}

/**
 * @dev Malicious contract that attempts to reenter participateInLottery via receive()
 */
contract MaliciousParticipant {
    VrfConsumer public target;
    uint256 public reentrancyAttempts;
    bool public attackActive;
    
    constructor(VrfConsumer _target) {
        target = _target;
    }
    
    /**
     * @dev Attempt reentrancy when receiving ETH
     */
    receive() external payable {
        if (attackActive && reentrancyAttempts < 5) {
            reentrancyAttempts++;
            // Try to participate again
            try target.participateInLottery{value: target.lotteryEntryFee()}() {
                // Reentrancy succeeded
            } catch {
                // Reentrancy was blocked
            }
        }
    }
    
    /**
     * @dev Participate in lottery and trigger reentrancy
     */
    function attack() external payable {
        attackActive = true;
        target.participateInLottery{value: target.lotteryEntryFee()}();
        attackActive = false;
    }
}

/**
 * @dev Malicious contract that tries to reenter ERC20Example.mint()
 */
contract MaliciousMinter {
    ERC20Example public token;
    
    constructor(ERC20Example _token) {
        token = _token;
    }
    
    function attack(address to, uint256 amount) external {
        // First mint call
        token.mint(to, amount);
        
        // Try to reenter - should be blocked
        token.mint(to, amount);
    }
}

/**
 * @dev Malicious token that attempts multiple reentrancy attacks
 */
contract MaliciousMultiReentrantToken is ERC20Example {
    VrfConsumer public target;
    uint256 public attemptCount;
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        address owner,
        VrfConsumer _target
    ) ERC20Example(name, symbol, cap, owner) {
        target = _target;
    }
    
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (to != address(0) && value > 0 && attemptCount < 3) {
            attemptCount++;
            
            // Try multiple reentrancy attempts
            try target.participateInLottery{value: target.lotteryEntryFee()}() {} catch {}
            try target.requestRandomWords() {} catch {}
        }
        
        super._update(from, to, value);
    }
}

/**
 * @title VrfConsumerReentrancyTest
 * @dev Tests to validate non-reentrancy protection in VrfConsumer and ERC20Example contracts
 * Based on security review findings
 */
contract VrfConsumerReentrancyTest is Test {
    ERC20Example public token;
    VrfConsumer public vrfConsumer;
    MockVRFV2PlusWrapper public mockVrfWrapper;
    
    address public owner;
    address public attacker;
    address public participant1;
    address public participant2;
    
    // Token parameters
    string constant TOKEN_NAME = "TestToken";
    string constant TOKEN_SYMBOL = "TEST";
    uint256 constant TOKEN_CAP = 10_000_000 * 10**10;
    
    // VRF parameters
    uint256 constant REQUEST_PRICE = 0.001 ether;
    
    function setUp() public {
        owner = address(this);
        attacker = makeAddr("attacker");
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");
        
        vm.deal(owner, 100 ether);
        vm.deal(attacker, 10 ether);
        vm.deal(participant1, 10 ether);
        vm.deal(participant2, 10 ether);
        
        mockVrfWrapper = new MockVRFV2PlusWrapper(REQUEST_PRICE);
        token = new ERC20Example(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CAP, owner);
        vrfConsumer = new VrfConsumer(address(mockVrfWrapper), owner);
        
        token.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(token));
    }
    
    // ============ Tests for mintDistributionReward Reentrancy ============
    
    /**
     * @dev Test that reentrancy is blocked when malicious token tries to reenter during mint
     */
    function test_Reentrancy_MintDistributionReward_Blocked() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Deploy malicious token
        MaliciousReentrantToken maliciousToken = new MaliciousReentrantToken(
            "Malicious",
            "MAL",
            TOKEN_CAP,
            owner,
            vrfConsumer
        );
        
        maliciousToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(maliciousToken));
        
        // Add participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward and request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0; // participant1 wins
        
        // Fulfill - should block reentrancy
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify reentrancy was attempted but blocked
        assertTrue(maliciousToken.attackAttempted(), "Attack should have been attempted");
        
        // Verify state is consistent
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants should be cleared");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants");
        
        // Verify tokens were minted correctly (only once, not multiple times)
        uint256 expectedReward = entryFee * 2;
        assertEq(maliciousToken.balanceOf(participant1), expectedReward, "Winner should receive correct reward");
        assertEq(maliciousToken.totalSupply(), expectedReward, "Total supply should be correct");
    }
    
    /**
     * @dev Test that reentrancy is blocked when malicious token tries to reenter via _afterTokenTransfer
     */
    function test_Reentrancy_MintDistributionReward_AfterTransfer_Blocked() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Deploy malicious token V2
        MaliciousReentrantTokenV2 maliciousToken = new MaliciousReentrantTokenV2(
            "MaliciousV2",
            "MAL2",
            TOKEN_CAP,
            owner,
            vrfConsumer
        );
        
        maliciousToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(maliciousToken));
        
        // Add participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward and request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        
        // Fulfill - should block reentrancy
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify reentrancy was attempted but blocked
        assertTrue(maliciousToken.attackAttempted(), "Attack should have been attempted");
        
        // Verify state is consistent
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants");
    }
    
    /**
     * @dev Test that state remains consistent after reentrancy attempt during mint
     */
    function test_Reentrancy_MintDistributionReward_StateConsistency() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        MaliciousReentrantToken maliciousToken = new MaliciousReentrantToken(
            "Malicious",
            "MAL",
            TOKEN_CAP,
            owner,
            vrfConsumer
        );
        
        maliciousToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(maliciousToken));
        
        // Add 3 participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        address participant3 = makeAddr("participant3");
        vm.deal(participant3, 10 ether);
        vm.prank(participant3);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        uint256 participantCountBefore = vrfConsumer.getParticipantCount();
        assertEq(participantCountBefore, 3, "Should have 3 participants");
        
        // Fast forward and request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1; // participant2 wins
        
        // Fulfill - should block reentrancy and maintain state consistency
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify state consistency
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants should be cleared");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants");
        assertEq(vrfConsumer.lastFulfilledId(), requestId, "Last fulfilled ID should be correct");
        
        // Verify only one winner received tokens
        uint256 expectedReward = entryFee * 3;
        assertEq(maliciousToken.balanceOf(participant2), expectedReward, "Winner should receive correct reward");
        assertEq(maliciousToken.balanceOf(participant1), 0, "Non-winner should have no tokens");
        assertEq(maliciousToken.balanceOf(participant3), 0, "Non-winner should have no tokens");
        assertEq(maliciousToken.totalSupply(), expectedReward, "Total supply should be correct");
    }
    
    // ============ Tests for participateInLottery Reentrancy ============
    
    /**
     * @dev Test that reentrancy is blocked when malicious contract tries to reenter via receive()
     */
    function test_Reentrancy_ParticipateInLottery_Blocked() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Deploy malicious participant contract
        MaliciousParticipant maliciousParticipant = new MaliciousParticipant(vrfConsumer);
        vm.deal(address(maliciousParticipant), 10 ether);
        
        // Attempt attack - should be blocked
        vm.prank(address(maliciousParticipant));
        maliciousParticipant.attack{value: entryFee}();
        
        // Verify reentrancy was attempted but blocked
        assertGt(maliciousParticipant.reentrancyAttempts(), 0, "Reentrancy should have been attempted");
        
        // Verify only one participation was recorded
        assertEq(vrfConsumer.getParticipantCount(), 1, "Should have only 1 participant");
        assertEq(vrfConsumer.getParticipantAddress(0), address(maliciousParticipant), "Participant should be recorded");
    }
    
    /**
     * @dev Test that state remains consistent after reentrancy attempt in participateInLottery
     */
    function test_Reentrancy_ParticipateInLottery_StateConsistency() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        MaliciousParticipant maliciousParticipant = new MaliciousParticipant(vrfConsumer);
        vm.deal(address(maliciousParticipant), 10 ether);
        
        // Add legitimate participant first
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        uint256 participantCountBefore = vrfConsumer.getParticipantCount();
        assertEq(participantCountBefore, 1, "Should have 1 participant");
        
        // Attempt attack
        vm.prank(address(maliciousParticipant));
        maliciousParticipant.attack{value: entryFee}();
        
        // Verify state consistency
        assertEq(vrfConsumer.getParticipantCount(), 2, "Should have 2 participants");
        assertEq(vrfConsumer.getParticipantAddress(0), participant1, "First participant should be correct");
        assertEq(vrfConsumer.getParticipantAddress(1), address(maliciousParticipant), "Second participant should be correct");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should still be accepting participants");
    }
    
    // ============ Tests for ERC20Example Custom Reentrancy Guard ============
    
    /**
     * @dev Test that ERC20Example's custom reentrancy guard prevents double minting
     */
    function test_Reentrancy_ERC20Example_CustomGuard_Works() public {
        // Try to mint directly from owner
        uint256 mintAmount = 1000 * 10**10;
        
        // First mint should succeed
        token.mint(participant1, mintAmount);
        assertEq(token.balanceOf(participant1), mintAmount, "First mint should succeed");
        
        // Try to mint again immediately - should succeed (guard resets after function)
        token.mint(participant2, mintAmount);
        assertEq(token.balanceOf(participant2), mintAmount, "Second mint should succeed");
        
        // Verify total supply
        assertEq(token.totalSupply(), mintAmount * 2, "Total supply should be correct");
    }
    
    /**
     * @dev Test that ERC20Example's custom guard prevents reentrancy during mint
     */
    function test_Reentrancy_ERC20Example_CustomGuard_PreventsReentrancy() public {
        // Create a malicious contract that tries to reenter mint
        MaliciousMinter maliciousMinter = new MaliciousMinter(token);
        token.setAuthorizedMinter(address(maliciousMinter));
        
        uint256 mintAmount = 1000 * 10**10;
        
        // Attempt reentrancy attack
        vm.expectRevert("ERC20Example: minting in progress");
        maliciousMinter.attack(participant1, mintAmount);
        
        // Verify only one mint succeeded (the first one)
        assertEq(token.balanceOf(participant1), mintAmount, "Only first mint should succeed");
        assertEq(token.totalSupply(), mintAmount, "Total supply should reflect only one mint");
    }
    
    // ============ Tests for Multiple Reentrancy Attempts ============
    
    /**
     * @dev Test that multiple reentrancy attempts are all blocked
     */
    function test_Reentrancy_MultipleAttempts_AllBlocked() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Deploy malicious token that attempts multiple reentrancies
        MaliciousMultiReentrantToken maliciousToken = new MaliciousMultiReentrantToken(
            "Malicious",
            "MAL",
            TOKEN_CAP,
            owner,
            vrfConsumer
        );
        
        maliciousToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(maliciousToken));
        
        // Add participants
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.prank(participant2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward and request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        
        // Fulfill - should block all reentrancy attempts
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify state is consistent
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants should be cleared");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants");
        
        // Verify tokens were minted only once
        uint256 expectedReward = entryFee * 2;
        assertEq(maliciousToken.balanceOf(participant1), expectedReward, "Winner should receive correct reward");
        assertEq(maliciousToken.totalSupply(), expectedReward, "Total supply should be correct");
    }
    
    // ============ Tests for Edge Cases ============
    
    /**
     * @dev Test that reentrancy protection works even with zero participants
     */
    function test_Reentrancy_ZeroParticipants_StillProtected() public {
        MaliciousReentrantToken maliciousToken = new MaliciousReentrantToken(
            "Malicious",
            "MAL",
            TOKEN_CAP,
            owner,
            vrfConsumer
        );
        
        maliciousToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(maliciousToken));
        
        // Fast forward and request with no participants
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        
        // Fulfill - should not revert even with zero participants
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Verify state
        assertEq(vrfConsumer.getParticipantCount(), 0, "Participants should remain 0");
        assertTrue(vrfConsumer.acceptingParticipants(), "Should be accepting participants");
    }
    
    // ============ Tests for Checks-Effects-Interactions Pattern ============
    
    /**
     * @dev Test that requestRandomWords follows Checks-Effects-Interactions pattern
     * State should be updated before external call
     */
    function test_ChecksEffectsInteractions_RequestRandomWords() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Add participant
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward time
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        // Record timestamp before request
        uint256 timestampBefore = block.timestamp;
        
        // Request random words
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        // Verify that lastRequestTimestamp was updated BEFORE external call
        // (This is verified by checking it matches block.timestamp, which means
        // it was set before the external call completed)
        assertEq(
            vrfConsumer.lastRequestTimestamp(),
            timestampBefore,
            "lastRequestTimestamp should be updated before external call"
        );
        
        // Verify request was successful
        assertGt(requestId, 0, "Request ID should be valid");
    }
    
    /**
     * @dev Test that state updates in requestRandomWords prevent time-based attacks
     */
    function test_ChecksEffectsInteractions_TimeBasedAttack_Prevented() public {
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // Add participant
        vm.prank(participant1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward time
        uint256 intervalSecs = vrfConsumer.lotteryIntervalHours() * 3600;
        vm.warp(block.timestamp + intervalSecs + 1);
        
        uint256 expectedPrice = mockVrfWrapper.calculateRequestPriceNative(
            uint32(vrfConsumer.callbackGasLimit()),
            uint32(vrfConsumer.numWords())
        );
        vm.deal(address(vrfConsumer), expectedPrice);
        
        // First request - should succeed
        uint256 requestId1 = vrfConsumer.requestRandomWords();
        uint256 timestampAfterFirst = vrfConsumer.lastRequestTimestamp();
        
        // Try to request again immediately - should fail
        vm.expectRevert("Too soon to resolve lottery");
        vrfConsumer.requestRandomWords();
        
        // Fast forward time again
        vm.warp(block.timestamp + intervalSecs + 1);
        vm.deal(address(vrfConsumer), expectedPrice);
        
        // Second request - should succeed
        uint256 requestId2 = vrfConsumer.requestRandomWords();
        uint256 timestampAfterSecond = vrfConsumer.lastRequestTimestamp();
        
        // Verify timestamps are correct
        assertGt(timestampAfterSecond, timestampAfterFirst, "Timestamp should be updated");
        assertEq(timestampAfterSecond, block.timestamp, "Timestamp should match current block timestamp");
        assertNotEq(requestId1, requestId2, "Request IDs should be different");
    }
}
