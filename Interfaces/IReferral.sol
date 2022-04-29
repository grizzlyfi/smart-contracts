//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IReferral {
    function totalReferralDepositForPool(address _poolAddress)
        external
        view
        returns (uint256);

    function referralDeposit(
        uint256 _amount,
        address _referralRecipient,
        address _referralGiver
    ) external;

    function referralWithdraw(uint256 _amount, address _referralRecipient)
        external;

    function getReferralRewards(address _poolAddress, address _referralGiver)
        external
        view
        returns (uint256);

    function withdrawReferralRewards(uint256 _amount, address _poolAddress)
        external;

    function withdrawAllReferralRewards(address _poolAddress)
        external
        returns (uint256);

    function referralUpdateRewards(uint256 _rewardedAmount) external;
}
