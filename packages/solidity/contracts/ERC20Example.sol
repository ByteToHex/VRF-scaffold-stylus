// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ERC20Example
 * @dev ERC20 token with metadata, capped supply, burnable functionality, and authorized minter
 * This contract matches the functionality of the Stylus Rust erc20-example contract
 */
contract ERC20Example is ERC20, ERC20Burnable, ERC20Capped, Ownable, ReentrancyGuard {
    uint8 private constant DECIMALS_VALUE = 10;
    
    // Authorized minter address (in addition to owner)
    address public authorizedMinter;

    /**
     * @dev Constructor that initializes the token
     * @param name Token name
     * @param symbol Token symbol
     * @param cap Maximum supply cap
     * @param owner Initial owner address
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        address owner
    ) ERC20(name, symbol) ERC20Capped(cap) Ownable(owner) {
        // Constructor sets up the token with name, symbol, cap, and owner
    }

    /**
     * @dev Mint tokens to an account
     * Can be called by owner or authorized minter
     * @param account Address to mint tokens to
     * @param value Amount of tokens to mint
     */
    function mint(address account, uint256 value) external nonReentrant {
        address caller = msg.sender;
        address tokenOwner = owner();
        
        // Allow either owner or authorized minter to mint
        require(
            caller == tokenOwner || (authorizedMinter != address(0) && caller == authorizedMinter),
            "ERC20Example: unauthorized minter"
        );

        // Check cap before minting
        uint256 maxSupply = cap();
        uint256 newSupply = totalSupply() + value;
        require(newSupply <= maxSupply, "ERC20Example: cap exceeded");

        _mint(account, value);
    }

    /**
     * @dev Get the authorized minter address
     * @return The address of the authorized minter
     */
    function getAuthorizedMinter() external view returns (address) {
        return authorizedMinter;
    }

    /**
     * @dev Set the authorized minter address (only owner)
     * @param minter Address to set as authorized minter
     */
    function setAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinter = minter;
    }

    /**
     * @dev Override decimals to return 10
     * @return The number of decimals
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS_VALUE;
    }

    /**
     * @dev Override _update to handle capped minting
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param value Amount of tokens
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }
}

