//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../Interfaces/IGrizzly.sol";

contract MockContractDepositor {
    function depositOnGrizzly(address grizzlyAddress, address referralGiver)
        public
        payable
    {
        address[] memory token = new address[](0);
        uint256[] memory value = new uint256[](0);
        IGrizzly GrizzlyInstance = IGrizzly(grizzlyAddress);
        GrizzlyInstance.deposit{value: msg.value}(
            referralGiver,
            token, token, value, value, 0, block.timestamp + 50
        );
    }
}
