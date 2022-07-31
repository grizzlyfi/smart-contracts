//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IMasterChef {
    function CAKE() external pure returns (address);

    function lpToken(uint256 _pid) external view returns (address);

    function userInfo(uint256 _pid, address _user)
        external
        pure
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 boostMultiplier
        );

    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
}
