//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../HoneyToken.sol";

contract MockFactory {
    mapping(address => mapping(address => address)) private pairAddress;
    
    function getPair(address tokenA, address tokenB) public view returns (address pair) {
        return pairAddress[tokenA][tokenB];
    }
    
    function setPair(address tokenA, address tokenB, address lpToken) public {
        pairAddress[tokenA][tokenB] = lpToken;
        pairAddress[tokenB][tokenA] = lpToken;
    }
}