//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../HoneyToken.sol";

contract MockFactory {
    function getPair(address tokenA, address tokenB) public view returns (address pair) {}
}