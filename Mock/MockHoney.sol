//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../HoneyToken.sol";

contract MockHoney is HoneyToken {
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialMintAmount,
        address admin,
        address developmentFounders,
        address advisors,
        address marketingReservesPool,
        address devTeam
    )
        HoneyToken(
            tokenName,
            tokenSymbol,
            initialMintAmount,
            admin,
            developmentFounders,
            advisors,
            marketingReservesPool,
            devTeam
        )
    {}
}
