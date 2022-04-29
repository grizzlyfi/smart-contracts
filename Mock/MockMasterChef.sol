//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "../Interfaces/IERC20.sol";

contract MockMasterChef {
    address private cakeTokenAddress;
    address private lpTokenAddress;
    uint256 private currentPendingCake;

    mapping(uint256 => uint256) public deposits;

    constructor(address _lpTokenAddress, address _cakeTokenAddress) {
        cakeTokenAddress = _cakeTokenAddress;
        lpTokenAddress = _lpTokenAddress;
    }

    function cake() external view returns (address) {
        return cakeTokenAddress;
    }

    function poolInfo(uint256 _pid)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        )
    {
        return (lpTokenAddress, 1, 1, 1);
    }

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256, uint256)
    {
        return (deposits[_pid], deposits[_pid]);
    }

    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        return currentPendingCake;
    }

    function setCurrentPendingCake(uint256 _currentPendingCake) external {
        IERC20(cakeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _currentPendingCake
        );
        currentPendingCake = _currentPendingCake;
    }

    function deposit(uint256 _pid, uint256 _amount) external {
        deposits[_pid] = deposits[_pid] + _amount;
        if (_amount == 0) {
            IERC20(cakeTokenAddress).transfer(msg.sender, currentPendingCake);
        }
    }

    function withdraw(uint256 _pid, uint256 _amount) external {}
}
