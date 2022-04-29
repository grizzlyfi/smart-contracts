//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../StakingPool.sol";

contract MockStakingPool is StakingPool {
    constructor(
        address tokenAddress,
        address lpAddress,
        address swapRouterAddress,
        address admin
    ) StakingPool(tokenAddress, lpAddress, swapRouterAddress, admin) {}
}
