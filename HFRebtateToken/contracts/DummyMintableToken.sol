// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HFRebtateToken.sol";

/**
 * @title DummyMintableToken
 * @dev A simple ERC20 token with a mint function.
 * This mock contract is used for testing HFRebtateToken.
 */
contract DummyMintableToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        // Optionally mint an initial supply here if needed.
    }

    /**
     * @notice Mint tokens to a specified address.
     * @param to The recipient address.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
