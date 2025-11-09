// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Example} from "../contracts/ERC20Example.sol";
import {VrfConsumer} from "../contracts/VrfConsumer.sol";
import {MockVRFV2PlusWrapper} from "./mocks/MockVRFV2PlusWrapper.sol";

/**
 * @title VrfConsumerIntegrationTest
 * @dev Basic integration tests focused on core interdependent functionality
 * between VrfConsumer and ERC20Example contracts
 */
contract VrfConsumerIntegrationTest is Test {
    ERC20Example public token;
    VrfConsumer public vrfConsumer;
    MockVRFV2PlusWrapper public mockVrfWrapper;
    
    address public owner;
    address public user1;
    address public user2;
    
    // Token parameters
    string constant TOKEN_NAME = "TestToken";
    string constant TOKEN_SYMBOL = "TEST";
    uint256 constant TOKEN_CAP = 1_000_000 * 10**10; // 1M tokens with 10 decimals
    
    // VRF parameters
    uint256 constant REQUEST_PRICE = 0.001 ether;
    
    event RequestFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords,
        address winner
    );
    
    function setUp() public {
        // Setup accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
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
        
        // Setup integration: Set VrfConsumer as authorized minter
        token.setAuthorizedMinter(address(vrfConsumer));
        
        // Set ERC20 token address on VRF consumer
        vrfConsumer.setErc20Token(address(token));
        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
    
    /**
     * @dev Test that VrfConsumer can mint tokens when set as authorized minter
     */
    function test_MintingAuthorization_Success() public {
        // Setup: Add participants and fulfill randomness
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        // User1 participates
        vm.prank(user1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // User2 participates
        vm.prank(user2);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        // Fast forward time to allow request
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        // Request random words
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        // Fulfill randomness - this should mint tokens to winner
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42; // Fixed random value for testing
        
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        // Calculate expected reward: entry_fee * participant_count
        uint256 expectedReward = entryFee * 2;
        
        // Determine winner (randomWords[0] % participants.length = 42 % 2 = 0, so user1 wins)
        address winner = user1;
        
        // Verify winner received tokens
        assertEq(token.balanceOf(winner), expectedReward, "Winner should receive correct token amount");
        assertEq(token.totalSupply(), expectedReward, "Total supply should match minted amount");
    }
    
    /**
     * @dev Test that minting fails when VrfConsumer is not authorized
     */
    function test_MintingFailure_UnauthorizedMinter() public {
        // Remove authorization
        token.setAuthorizedMinter(address(0));
        
        // Setup participants
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(user1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        
        // This should revert because VrfConsumer is not authorized to mint
        vm.prank(address(mockVrfWrapper));
        vm.expectRevert("ERC20Example: unauthorized minter");
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
    }
    
    /**
     * @dev Test that minting respects ERC20 cap
     */
    function test_TokenCap_Enforcement() public {
        // Set a very low cap to test cap enforcement
        uint256 lowCap = 1000 * 10**10; // 1000 tokens
        
        // Deploy new token with low cap
        ERC20Example lowCapToken = new ERC20Example(
            "LowCapToken",
            "LCT",
            lowCap,
            owner
        );
        
        // Set up integration
        lowCapToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(lowCapToken));
        
        // Set a high entry fee that would exceed cap
        uint256 highEntryFee = lowCap / 2; // 500 tokens per entry
        vrfConsumer.setLotteryEntryFee(highEntryFee);
        
        // Add participants
        vm.prank(user1);
        vrfConsumer.participateInLottery{value: highEntryFee}();
        
        vm.prank(user2);
        vrfConsumer.participateInLottery{value: highEntryFee}();
        
        // Calculate reward: highEntryFee * 2 = 1000 tokens (exactly at cap)
        uint256 reward = highEntryFee * 2;
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        
        // This should succeed as reward equals cap
        vm.prank(address(mockVrfWrapper));
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
        
        assertEq(lowCapToken.totalSupply(), reward, "Total supply should equal cap");
        
        // Now try to exceed cap with more participants
        vrfConsumer.setErc20Token(address(token)); // Reset to original token
        vrfConsumer.setLotteryEntryFee(500000); // Reset entry fee
        
        // Deploy another low cap token
        ERC20Example lowCapToken2 = new ERC20Example(
            "LowCapToken2",
            "LCT2",
            lowCap,
            owner
        );
        
        lowCapToken2.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(lowCapToken2));
        
        // Set entry fee that would cause reward to exceed cap
        vrfConsumer.setLotteryEntryFee(lowCap / 2 + 1); // 501 tokens per entry
        
        vm.prank(user1);
        vrfConsumer.participateInLottery{value: lowCap / 2 + 1}();
        
        vm.prank(user2);
        vrfConsumer.participateInLottery{value: lowCap / 2 + 1}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        requestId = vrfConsumer.requestRandomWords();
        randomWords[0] = 1;
        
        // This should revert because reward would exceed cap
        vm.prank(address(mockVrfWrapper));
        vm.expectRevert("ERC20Example: cap exceeded");
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
    }
    
    /**
     * @dev Test token address configuration
     */
    function test_TokenAddressConfiguration() public {
        // Initially token address should be set
        assertEq(vrfConsumer.erc20_token_address(), address(token), "Token address should be set");
        
        // Owner can change token address
        ERC20Example newToken = new ERC20Example(
            "NewToken",
            "NEW",
            TOKEN_CAP,
            owner
        );
        
        newToken.setAuthorizedMinter(address(vrfConsumer));
        vrfConsumer.setErc20Token(address(newToken));
        
        assertEq(vrfConsumer.erc20_token_address(), address(newToken), "Token address should be updated");
        
        // Non-owner cannot change token address
        vm.prank(user1);
        vm.expectRevert();
        vrfConsumer.setErc20Token(address(newToken));
    }
    
    /**
     * @dev Test that minting fails when token address is not set
     */
    function test_MintingFailure_TokenNotSet() public {
        // Clear token address
        vrfConsumer.setErc20Token(address(0));
        
        // Setup participants
        uint256 entryFee = vrfConsumer.lotteryEntryFee();
        
        vm.prank(user1);
        vrfConsumer.participateInLottery{value: entryFee}();
        
        vm.warp(block.timestamp + vrfConsumer.lotteryIntervalHours() * 3600 + 1);
        
        uint256 requestId = vrfConsumer.requestRandomWords();
        
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        
        // This should revert because token address is not set
        vm.prank(address(mockVrfWrapper));
        vm.expectRevert("Token not set");
        mockVrfWrapper.fulfillRandomWords(requestId, randomWords);
    }
    
    /**
     * @dev Test integration setup - authorized minter configuration
     */
    function test_IntegrationSetup_AuthorizedMinter() public {
        // Verify VrfConsumer is set as authorized minter
        assertEq(token.getAuthorizedMinter(), address(vrfConsumer), "VrfConsumer should be authorized minter");
        
        // Owner can change authorized minter
        token.setAuthorizedMinter(user1);
        assertEq(token.getAuthorizedMinter(), user1, "Authorized minter should be updated");
        
        // Non-owner cannot change authorized minter
        vm.prank(user2);
        vm.expectRevert();
        token.setAuthorizedMinter(user2);
    }
    
    /**
     * @dev Test that owner can still mint directly
     */
    function test_OwnerCanMintDirectly() public {
        uint256 mintAmount = 1000 * 10**10;
        
        // Owner can mint directly
        token.mint(user1, mintAmount);
        
        assertEq(token.balanceOf(user1), mintAmount, "User1 should receive minted tokens");
        assertEq(token.totalSupply(), mintAmount, "Total supply should reflect minted amount");
    }
}

