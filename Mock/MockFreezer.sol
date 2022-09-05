//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../Interfaces/IFreezer.sol";

contract MockFreezer is IFreezer {
    function freezerPoints(address participantAddress)
        external
        view
        returns (uint256)
    {
        return 50000 ether;
    }

    function getParticipant(address participantAddress, uint256 round)
        external
        view
        returns (Participant memory participant)
    {
        return Participant(1000, 0, 100000000, 1, 1);
    }

    function getRounds(address participantAddress)
        external
        view
        returns (uint256)
    {
        return 1;
    }

    function getTimeperiod(uint256 index)
        external
        view
        returns (TimePeriod memory timePeriod)
    {
        return TimePeriod(100000, 100);
    }

    function freeze(uint256 honeyAmount, uint256 periodIndex) external {}

    function unfreeze(uint256 freezingRound) external {}

    function claimPendingRewards(uint256 freezingRound) external {}

    function getPendingRewards(address freezerAddress, uint256 freezingRound)
        external
        returns (
            uint256 honeyRewards,
            uint256 bnbRewards,
            uint256 multipliedRewards
        )
    {
        return (0, 0, 0);
    }
}
