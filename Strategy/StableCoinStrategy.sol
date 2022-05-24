//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../Config/BaseConfig.sol";

/// @title Stablecoin strategy handler
/// @notice The contract keeps track of the balances of stablecoin strategy investors and their reinvests (rewards) using EIP-1973
/// @dev This contract is abstract and is intended to be inherited by grizzly.sol. State change functions are all internal which are called by other contracts functions
abstract contract StableCoinStrategy is Initializable, BaseConfig {
    struct StablecoinStrategyParticipant {
        uint256 amount;
        uint256 rewardMask;
        uint256 totalReinvested;
    }

    uint256 public stablecoinStrategyDeposits;
    uint256 private roundMask;

    mapping(address => StablecoinStrategyParticipant) private participantData;

    function __StableCoinStrategy_init() internal initializer {
        roundMask = 1;
    }

    /// @notice Deposits the desired amount for a stablecoin strategy investor
    /// @dev The current round mask for rewards is updated before the deposit to have a clean state
    /// @param amount The desired deposit amount for an investor
    function stablecoinStrategyDeposit(uint256 amount) internal {
        uint256 currentBalance = getStablecoinStrategyBalance();
        uint256 currentAmount = participantData[msg.sender].amount;

        participantData[msg.sender].rewardMask = roundMask;
        participantData[msg.sender].amount = currentBalance + amount;
        participantData[msg.sender].totalReinvested +=
            currentBalance -
            currentAmount;

        stablecoinStrategyDeposits += currentBalance - currentAmount + amount;
    }

    /// @notice Withdraws the desired amount for a stablecoin strategy investor
    /// @dev The current round mask for rewards is updated before the deposit to have a clean state
    /// @param amount The desired withdraw amount for an investor
    function stablecoinStrategyWithdraw(uint256 amount) internal {
        require(amount > 0, "TZ");

        uint256 currentBalance = getStablecoinStrategyBalance();
        require(amount <= currentBalance, "SD");

        uint256 currentAmount = participantData[msg.sender].amount;
        participantData[msg.sender].rewardMask = roundMask;
        participantData[msg.sender].amount = currentBalance - amount;
        participantData[msg.sender].totalReinvested +=
            currentBalance -
            currentAmount;

        stablecoinStrategyDeposits =
            stablecoinStrategyDeposits +
            currentBalance -
            currentAmount -
            amount;
    }

    /// @notice Gets the current stablecoin balance for an investor. Rewards are included too
    /// @dev Pending rewards are calculated through the difference between the current round mask and the investors rewardMask according to EIP-1973
    /// @return Current stablecoin balance
    function getStablecoinStrategyBalance() public view returns (uint256) {
        if (participantData[msg.sender].rewardMask == 0) return 0;

        return
            participantData[msg.sender].amount +
            ((roundMask - participantData[msg.sender].rewardMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;
    }

    /// @notice Adds rewards to the contract
    /// @dev The roundmask is increased by the share of the rewarded amount such that investors get their share of pending rewards
    /// @param rewardedAmount The amount to be rewarded
    function stablecoinStrategyUpdateRewards(uint256 rewardedAmount) internal {
        if (stablecoinStrategyDeposits == 0) return;

        roundMask +=
            (DECIMAL_OFFSET * rewardedAmount) /
            stablecoinStrategyDeposits;
    }

    /// @notice Reads out the participant data
    /// @param participant The address of the participant
    /// @return Participant data
    function getStablecoinStrategyParticipantData(address participant)
        public
        view
        returns (StablecoinStrategyParticipant memory)
    {
        return participantData[participant];
    }

    uint256[50] private __gap;
}
