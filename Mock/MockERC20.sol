//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialMintAmount
    ) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, initialMintAmount);
    }
}
