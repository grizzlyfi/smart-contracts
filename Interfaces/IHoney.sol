//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IHoney {
    function totalClaimed(address claimer) external view returns (uint256);

    function claimTokens(uint256 amount) external;

    function setDevelopmentFounders(address _developmentFounders) external;

    function setAdvisors(address _advisors) external;

    function setMarketingReservesPool(address _marketingReservesPool) external;

    function setDevTeam(address _devTeam) external;

    function claimTokensWithoutAdditionalTokens(uint256 amount) external;
}
