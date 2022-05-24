//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IStakingPool {
    function stakerAmounts(address staker)
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 honeyMask,
            uint256 lpMask,
            uint256 pendingLp,
            uint256 claimedHoney,
            uint256 claimedLp,
            uint256 honeyMintMask,
            uint256 pendingHoneyMint,
            uint256 claimedHoneyMint
        );

    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;

    function balanceOf(address staker) external view returns (uint256);

    function lpBalanceOf(address staker) external view returns (uint256);

    function rewardHoney(uint256 amount) external;

    function rewardLP(uint256 amount) external;

    function claimLpTokens(
        uint256 amount,
        uint256 additionalHoneyAmount,
        address to
    ) external returns (uint256 stakedTokenOut, uint256 bnbOut);

    function updateLpRewardMask() external;

    function updateAdditionalMintRoundMask() external;

    function getPendingHoneyRewards() external view returns (uint256);

    function getHoneyMintRewardsInRange(uint256 fromBlock, uint256 toBlock)
        external
        view
        returns (uint256);

    function setHoneyMintingRewards(
        uint256 _blockRewardPhase1End,
        uint256 _blockRewardPhase2Start,
        uint256 _blockRewardPhase1Amount,
        uint256 _blockRewardPhase2Amount
    ) external;
}
