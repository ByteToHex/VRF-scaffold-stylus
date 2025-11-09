// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC20Example
 * @dev ERC20 token contract with capped supply, burnable, and authorized minter functionality
 * This is the Solidity equivalent of the Stylus erc20-example contract
 */
contract ERC20Example is ERC20, ERC20Capped, ERC20Burnable, Ownable {
    address public authorizedMinter;
    bool private minting;

    /**
     * @dev Constructor that initializes the ERC20 token
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
        // Constructor is handled by parent contracts
    }

    /**
     * @dev Returns the number of decimals for the token
     * @return The number of decimals (10)
     */
    function decimals() public pure override returns (uint8) {
        return 10;
    }

    /**
     * @dev Mint tokens to an account
     * @param account Address to mint tokens to
     * @param value Amount of tokens to mint
     */
    function mint(address account, uint256 value) external {
        require(!minting, "Minting in progress");
        minting = true;

        address caller = msg.sender;
        address tokenOwner = owner();
        address authorized = authorizedMinter;

        require(
            caller == tokenOwner || (authorized != address(0) && caller == authorized),
            "Unauthorized minter"
        );

        _mint(account, value);
        minting = false;
    }

    /**
     * @dev Get the authorized minter address
     * @return The authorized minter address
     */
    function getAuthorizedMinter() external view returns (address) {
        return authorizedMinter;
    }

    /**
     * @dev Set the authorized minter address (only owner)
     * @param minter Address of the authorized minter
     */
    function setAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinter = minter;
    }

    /**
     * @dev Override _update to enforce cap
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }
}

