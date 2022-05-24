//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IReferral.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title The referral contract
/// @notice This contract keeps track of the referral balances and their honey rewards. It uses the TokenA-TokenB-LP token from the referral recipient to split up the honey rewards for the referral giver using EIP-1973.
/// @dev This contract is intended to be called from a Rewarder contract like the Grizzly contract which wants to keep track of the referrals. It is important to note that the Grizzly contract needs to keep track of the deposit of the referral recipient as this contract only considers the sum of all the deposits from referral recipients for a given referral giver.
contract Referral is
    Initializable,
    AccessControlUpgradeable,
    IReferral,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct ReferralGiver {
        uint256 deposit;
        uint256 reward;
        uint256 rewardMask;
        uint256 claimedRewards;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // the role that allows updating parameters
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    uint256 public constant DECIMAL_OFFSET = 10e12;

    // (poolAddress) -> (referralGiverAddress) -> (ReferralGiver)
    // This mapping is used to keep track the rewards and the deposits for a referral giver
    mapping(address => mapping(address => ReferralGiver)) public referralGivers;

    // (referralRecipientAddress) -> (ReferralGiver))
    // This mapping is used to get the referral giver for a given referral recipient
    mapping(address => address) public referralGiverAddresses;

    // (ReferralGiver) -> (active friends)
    // this mapping shows the active friends for a referral giver
    mapping(address => uint256) public activeFriends;

    // (poolAddress) -> (totalReferralDeposit)
    mapping(address => uint256) private totalReferralDeposits;

    // (poolAddress) -> (roundMask)
    mapping(address => uint256) private roundMasks;

    IERC20Upgradeable private HoneyToken;
    address private DevTeam;

    function initialize(
        address _honeyTokenAddress,
        address _admin,
        address _devTeam
    ) public initializer {
        HoneyToken = IERC20Upgradeable(_honeyTokenAddress);
        DevTeam = _devTeam;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        __Pausable_init();
    }

    /// @notice pause
    /// @dev pause the contract
    function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice unpause
    /// @dev unpause the contract
    function unpause() external whenPaused onlyRole(PAUSER_ROLE) {
        _unpause();
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
    /// @dev Dev team used if no referralGiver is provided. Referral recipient and referral giver needs to be different. The referral giver is set once for a referral recipient, after that it will always be the same. Can only be called by a rewarder contract.
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
        if (_referralGiver == address(0)) {
            _referralGiver = DevTeam;
        }
        if (referralGiverAddresses[_referralRecipient] == address(0)) {
            require(
                _referralRecipient != _referralGiver,
                "referral to the same account"
            );
            referralGiverAddresses[_referralRecipient] = _referralGiver;
            activeFriends[_referralGiver] += 1;
        }

        address _constReferralGiver = referralGiverAddresses[
            _referralRecipient
        ];

        updatePendingRewards(msg.sender, _constReferralGiver);

        referralGivers[msg.sender][_constReferralGiver].deposit += _amount;

        totalReferralDeposits[msg.sender] += _amount;
    }

    /// @notice Withdraws LP tokens for a referral recipient such that the rewards for the referralGiver get updated
    /// @dev upadtes the users reward mask before the withdraw. It is important to note that the caller contract needs to keep track of the referral recipient deposits, such that no recipient can withdraw more than he provided for a given referral giver. Can only be called by a rewarder contract.
    /// @param _amount The withdraw amount
    /// @param _referralRecipient the recipient who withdraws LP tokens
    function referralWithdraw(uint256 _amount, address _referralRecipient)
        external
        override
        onlyRole(REWARDER_ROLE)
    {
        address _referralGiver = referralGiverAddresses[_referralRecipient];

        if (referralGivers[msg.sender][_referralGiver].deposit < _amount) {
            _amount = referralGivers[msg.sender][_referralGiver].deposit;
        }

        updatePendingRewards(msg.sender, _referralGiver);

        referralGivers[msg.sender][_referralGiver].deposit -= _amount;

        totalReferralDeposits[msg.sender] -= _amount;
    }

    /// @notice The current referral rewards for a referralGiver dependent on the pool
    /// @dev Calculated using the referral rewards plus the difference from the current round mask
    /// @param _poolAddress The address of the pool for which the rewards should be calculated
    /// @param _referralGiver The referral giver address
    /// @return the current reward for the referral giver
    function getReferralRewards(address _poolAddress, address _referralGiver)
        public
        view
        override
        returns (uint256)
    {
        return
            referralGivers[_poolAddress][_referralGiver].reward +
            ((roundMasks[_poolAddress] -
                referralGivers[_poolAddress][_referralGiver].rewardMask) *
                referralGivers[_poolAddress][_referralGiver].deposit) /
            DECIMAL_OFFSET;
    }

    /// @notice Withdraws the referral rewards for a referral giver
    /// @dev upadtes the users reward mask before the withdraw
    /// @param _amount The amount to be withdrawn
    /// @param _poolAddress The address of the pool for which the rewards should be withdrawn
    function withdrawReferralRewards(uint256 _amount, address _poolAddress)
        public
        override
        whenNotPaused
    {
        uint256 _currentReferralReward = getReferralRewards(
            _poolAddress,
            msg.sender
        );

        require(_amount <= _currentReferralReward, "Withdraw amount too large");

        referralGivers[_poolAddress][msg.sender].reward =
            _currentReferralReward -
            _amount;
        referralGivers[_poolAddress][msg.sender].rewardMask = roundMasks[
            _poolAddress
        ];
        referralGivers[_poolAddress][msg.sender].claimedRewards += _amount;

        IERC20Upgradeable(address(HoneyToken)).safeTransfer(
            msg.sender,
            _amount
        );
    }

    /// @notice Withdraws all the referral rewards for a referral giver
    /// @param _poolAddress The address of the pool for which the rewards should be withdrawn
    /// @return Returns the value that was withdrawn
    function withdrawAllReferralRewards(address _poolAddress)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 _amountToWithdraw = getReferralRewards(
            _poolAddress,
            msg.sender
        );
        withdrawReferralRewards(_amountToWithdraw, _poolAddress);
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

        IERC20Upgradeable(address(HoneyToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardedAmount
        );

        roundMasks[msg.sender] +=
            (DECIMAL_OFFSET * _rewardedAmount) /
            totalReferralDeposits[msg.sender];
    }

    /// @notice Gets the total earned amount for a referral giver
    /// @dev Calculates the current pending reward plus the withdrawn rewards
    /// @param _poolAddress The address of the pool for which the rewards should be calculated
    /// @param _referralGiver The referral giver address
    /// @return The total earned amount
    function getTotalEarnedAmount(address _poolAddress, address _referralGiver)
        external
        view
        returns (uint256)
    {
        uint256 currentReferralRewards = getReferralRewards(
            _poolAddress,
            _referralGiver
        );
        uint256 claimedReferralRewards = referralGivers[_poolAddress][
            _referralGiver
        ].claimedRewards;
        return currentReferralRewards + claimedReferralRewards;
    }

    /// @notice Updates the current pending rewards
    /// @dev Adds pending rewards to the referral reward for a referralRecipient and resets the roundmask again
    /// @param _poolAddress The address of the pool for which the pending rewards should be updated
    /// @param _referralGiver The address of the referral giver for which the pending rewards should be updated
    function updatePendingRewards(address _poolAddress, address _referralGiver)
        internal
    {
        uint256 _currentReferralReward = getReferralRewards(
            _poolAddress,
            _referralGiver
        );
        referralGivers[_poolAddress][_referralGiver]
            .reward = _currentReferralReward;
        referralGivers[_poolAddress][_referralGiver].rewardMask = roundMasks[
            _poolAddress
        ];
    }

    uint256[50] private __gap;
}
