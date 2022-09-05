//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IFreezer {
    struct Participant {
        uint256 amount;
        uint256 periodIndex;
        uint256 freezingStartTime;
        uint256 honeyRewardMask;
        uint256 bnbRewardMask;
    }

    struct TimePeriod {
        uint256 period;
        uint256 multiplier;
    }

    event Freezed(address participantAddress, uint256 round, uint256 amount);
    event Unfreezed(address participantAddress, uint256 round, uint256 amount);
    event ClaimedRewards(
        address participantAddress,
        uint256 round,
        uint256 bnbAmount,
        uint256 honeyAmount
    );

    function freezerPoints(address participantAddress)
        external
        view
        returns (uint256);

    function getParticipant(address participantAddress, uint256 round)
        external
        view
        returns (Participant memory participant);

    function getRounds(address participantAddress)
        external
        view
        returns (uint256);

    function getTimeperiod(uint256 index)
        external
        view
        returns (TimePeriod memory timePeriod);

    function freeze(uint256 honeyAmount, uint256 periodIndex) external;

    function unfreeze(uint256 freezingRound) external;

    function claimPendingRewards(uint256 freezingRound) external;

    function getPendingRewards(address freezerAddress, uint256 freezingRound)
        external
        returns (
            uint256 honeyRewards,
            uint256 bnbRewards,
            uint256 multipliedRewards
        );
}
