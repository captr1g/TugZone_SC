// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PumpToken
 * @dev ERC-20 token with 1 billion total supply
 */
contract PumpToken is ERC20, Ownable {
    // Total supply: 1 billion tokens with 18 decimals
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    
    /**
     * @dev Constructor that gives msg.sender all existing tokens
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}