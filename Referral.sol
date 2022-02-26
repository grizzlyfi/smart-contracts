//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Interfaces/IReferral.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title The referral contract
/// @notice This contract keeps track of the referral balances and their honey rewards. It uses the TokenA-TokenB-LP token from the referral recipient to split up the honey rewards for the referral giver using EIP-1973.
/// @dev This contract is intended to be called from a Rewarder contract like the Grizzly contract which wants to keep track of the referrals.
contract Referral is AccessControl, IReferral {
    using SafeERC20 for IERC20;

    struct ReferralRecipient {
        uint256 referralDeposit;
        uint256 referralReward;
        address referralGiver;
        uint256 rewardMask;
    }

    // the role that allows updating parameters
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    uint256 public constant DECIMAL_OFFSET = 10e12;

    // (poolAddress) -> (referralRecipientAddress) -> (ReferralRecipient)
    mapping(address => mapping(address => ReferralRecipient))
        private referralRecipients;

    // (poolAddress) -> (referralGiverAddress) -> (List of referralRecipients)
    // This mapping is used such that the referralGiver can show all his referralRecipients in order to claim his rewards from them
    mapping(address => mapping(address => address[])) public referralGivers;

    // (poolAddress) -> (totalReferralDeposit)
    mapping(address => uint256) private totalReferralDeposits;

    // (poolAddress) -> (roundMask)
    mapping(address => uint256) private roundMasks;

    IERC20 private HoneyToken;
    address private DevTeam;

    constructor(
        address _honeyTokenAddress,
        address _admin,
        address _devTeam
    ) {
        HoneyToken = IERC20(_honeyTokenAddress);
        DevTeam = _devTeam;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Getter for the total referral deposit for a pool
    /// @param _poolAddress The pool address for the total referral deposit
    /// @return The total referral deposit
    function totalReferralDepositForPool(address _poolAddress)
        external
        view
        override
        returns (uint256)
    {
        return totalReferralDeposits[_poolAddress];
    }

    /// @notice Deposits LP tokens for a referral recipient such that the reward share for a referralGiver can be calculated
    /// @dev Dev team used if no referralGiver is provided. An array and a mapping is created such that from both sides (referralGiver and referralRecipient) the data can be requested. Can only be called by a rewarder contract.
    /// @param _amount The deposit amount
    /// @param _referralRecipient The user depositing LP tokens
    /// @param _referralGiver The referralGiver, who will receive the rewards
    function referralDeposit(
        uint256 _amount,
        address _referralRecipient,
        address _referralGiver
    ) external override onlyRole(REWARDER_ROLE) {
        require(_referralRecipient != address(0), "Referral recipient missing");
        if (roundMasks[msg.sender] == 0) {
            roundMasks[msg.sender] = 1;
        }
        if (
            referralRecipients[msg.sender][_referralRecipient].referralGiver ==
            address(0)
        ) {
            require(
                _referralRecipient != _referralGiver,
                "referral to the same account"
            );
            if (_referralGiver == address(0)) {
                _referralGiver = DevTeam;
            }
            referralRecipients[msg.sender][_referralRecipient]
                .referralGiver = _referralGiver;
            referralGivers[msg.sender][_referralGiver].push(_referralRecipient);
        }

        updatePendingRewards(msg.sender, _referralRecipient);

        referralRecipients[msg.sender][_referralRecipient]
            .referralDeposit += _amount;

        totalReferralDeposits[msg.sender] += _amount;
    }

    /// @notice Withdraws LP tokens for a referral recipient such that the rewards for the referralGiver get updated
    /// @dev upadtes the users reward mask before the withdraw. Can only be called by a rewarder contract.
    /// @param _amount The withdraw amount
    /// @param _referralRecipient the recipient who withdraws LP tokens
    function referralWithdraw(uint256 _amount, address _referralRecipient)
        external
        override
        onlyRole(REWARDER_ROLE)
    {
        if (
            _amount >
            referralRecipients[msg.sender][_referralRecipient].referralDeposit
        ) {
            _amount = referralRecipients[msg.sender][_referralRecipient]
                .referralDeposit;
        }

        updatePendingRewards(msg.sender, _referralRecipient);

        referralRecipients[msg.sender][_referralRecipient]
            .referralDeposit -= _amount;

        totalReferralDeposits[msg.sender] -= _amount;
    }

    /// @notice The current referral rewards for a referralGiver dependent on his referralRecipient and the pool
    /// @dev Calculated using the referral rewards plus the difference from the current round mask
    /// @param _poolAddress The address of the pool for which the rewards should be calculated
    /// @param _referralRecipient The referral recipient that used the referral giver
    /// @return the current reward for the referral giver
    function getReferralRewards(
        address _poolAddress,
        address _referralRecipient
    ) public view override returns (uint256) {
        return
            referralRecipients[_poolAddress][_referralRecipient]
                .referralReward +
            ((roundMasks[_poolAddress] -
                referralRecipients[_poolAddress][_referralRecipient]
                    .rewardMask) *
                referralRecipients[_poolAddress][_referralRecipient]
                    .referralDeposit) /
            DECIMAL_OFFSET;
    }

    /// @notice Withdraws the referral rewards for a referral giver
    /// @dev upadtes the users reward mask before the withdraw
    /// @param _amount The amount to be withdrawn
    /// @param _poolAddress The address of the pool for which the rewards should be withdrawn
    /// @param _referralRecipient The referral recipient that used the referral giver
    function withdrawReferralRewards(
        uint256 _amount,
        address _poolAddress,
        address _referralRecipient
    ) public override {
        require(
            referralRecipients[_poolAddress][_referralRecipient]
                .referralGiver == msg.sender,
            "Wrong referral"
        );
        uint256 _currentReferralReward = getReferralRewards(
            _poolAddress,
            _referralRecipient
        );

        require(_amount <= _currentReferralReward, "Withdraw amount too large");

        referralRecipients[_poolAddress][_referralRecipient].referralReward =
            _currentReferralReward -
            _amount;
        referralRecipients[_poolAddress][_referralRecipient]
            .rewardMask = roundMasks[_poolAddress];

        IERC20(address(HoneyToken)).safeTransfer(msg.sender, _amount);
    }

    /// @notice Withdraws all the referral rewards for a referral giver
    /// @param _poolAddress The address of the pool for which the rewards should be withdrawn
    /// @param _referralRecipient The referral recipient that used the referral giver
    /// @return Returns the value that was withdrawn
    function withdrawAllReferralRewards(
        address _poolAddress,
        address _referralRecipient
    ) external override returns (uint256) {
        uint256 _amountToWithdraw = getReferralRewards(
            _poolAddress,
            _referralRecipient
        );
        withdrawReferralRewards(
            _amountToWithdraw,
            _poolAddress,
            _referralRecipient
        );
        return _amountToWithdraw;
    }

    /// @notice Rewards the referral contract
    /// @dev Can only be called by a rewarder contract.
    /// @param _rewardedAmount The amount in honey that was rewarded to the contract
    function referralUpdateRewards(uint256 _rewardedAmount)
        external
        override
        onlyRole(REWARDER_ROLE)
    {
        if (totalReferralDeposits[msg.sender] == 0) return;

        IERC20(address(HoneyToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardedAmount
        );

        roundMasks[msg.sender] +=
            (DECIMAL_OFFSET * _rewardedAmount) /
            totalReferralDeposits[msg.sender];
    }

    /// @notice Updates the current pending rewards
    /// @dev Adds pending rewards to the referral reward for a referralRecipient and resets the roundmask again
    /// @param _poolAddress The address of the pool for which the pending rewards should be updated
    /// @param _referralRecipient The address of the referral recipient for which the pending rewards should be updated
    function updatePendingRewards(
        address _poolAddress,
        address _referralRecipient
    ) internal {
        uint256 _currentReferralReward = getReferralRewards(
            _poolAddress,
            _referralRecipient
        );
        referralRecipients[_poolAddress][_referralRecipient]
            .referralReward = _currentReferralReward;
        referralRecipients[_poolAddress][_referralRecipient]
            .rewardMask = roundMasks[_poolAddress];
    }
}
