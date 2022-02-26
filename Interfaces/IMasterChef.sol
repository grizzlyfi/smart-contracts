//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IMasterChef {
  
    function cake() external pure returns (address);
    function poolInfo(uint256 _pid) external pure returns (address, uint256, uint256, uint256);
    function userInfo(uint256 _pid, address _user) external pure returns (uint256, uint256);
    function pendingCake(uint256 _pid, address _user) external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
}