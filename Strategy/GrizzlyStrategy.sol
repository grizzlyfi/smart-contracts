//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../Config/BaseConfig.sol";

/// @title Grizzly strategy handler
/// @notice The contract keeps track of the liquidity pool balances, of the GHNY staking pool lp tokens and the GHNY staking pool honey rewards of a grizzly strategy investor using EIP-1973
/// @dev This contract is abstract and is intended to be inherited by grizzly.sol. Honey and lp rewards are handled using round masks
abstract contract GrizzlyStrategy is Initializable, BaseConfig {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct GrizzlyStrategyParticipant {
        uint256 amount;
        uint256 honeyMask;
        uint256 pendingHoney;
        uint256 lpMask;
        uint256 pendingLp;
        uint256 pendingAdditionalHoney;
        uint256 additionalHoneyMask;
    }

    uint256 public grizzlyStrategyDeposits;

    uint256 public grizzlyStrategyLastHoneyBalance;
    uint256 public grizzlyStrategyLastLpBalance;
    uint256 public grizzlyStrategyLastAdditionalHoneyBalance;

    uint256 private honeyRoundMask;
    uint256 private lpRoundMask;
    uint256 private additionalHoneyRoundMask;

    event GrizzlyStrategyClaimHoneyEvent(
        address indexed user,
        uint256 honeyAmount
    );
    event GrizzlyStrategyClaimLpEvent(
        address indexed user,
        uint256 honeyAmount,
        uint256 bnbAmount
    );

    mapping(address => GrizzlyStrategyParticipant) private participantData;

    function __GrizzlyStrategy_init() internal initializer {
        honeyRoundMask = 1;
        lpRoundMask = 1;
        additionalHoneyRoundMask = 1;
    }

    /// @notice Deposits the desired amount for a grizzly strategy investor
    /// @dev User masks are updated before the deposit to have a clean state
    /// @param amount The desired deposit amount for an investor
    function grizzlyStrategyDeposit(uint256 amount) internal {
        updateUserMask();
        participantData[msg.sender].amount += amount;
        grizzlyStrategyDeposits += amount;
    }

    /// @notice Withdraws the desired amount for a grizzly strategy investor
    /// @dev User masks are updated before the deposit to have a clean state
    /// @param amount The desired withdraw amount for an investor
    function grizzlyStrategyWithdraw(uint256 amount) internal {
        require(amount > 0, "TZ");
        require(amount <= getGrizzlyStrategyBalance(), "SD");

        updateUserMask();
        participantData[msg.sender].amount -= amount;
        grizzlyStrategyDeposits -= amount;
    }

    /// @notice Stakes the honey rewards into the honey staking pool
    /// @param amount The honey reward to be staked
    function grizzlyStrategyStakeHoney(uint256 amount) internal {
        StakingPool.stake(amount);
    }

    /// @notice Updates the round mask for the honey and lp rewards
    /// @dev The honey and lp rewards are requested from the GHNY staking pool for the whole contract
    function updateRoundMasks() public {
        isNotPaused();
        if (grizzlyStrategyDeposits == 0) return;

        // In order to keep track of how many new tokens were rewarded to this contract, we need to take
        // into account claimed tokens as well, otherwise the balance will become lower than "last balance"
        (
            ,
            ,
            ,
            ,
            uint256 claimedHoney,
            uint256 claimedLp,
            ,
            ,
            uint256 claimedAdditionalHoney
        ) = StakingPool.stakerAmounts(address(this));

        uint256 newHoneyTokens = claimedHoney +
            StakingPool.balanceOf(address(this)) -
            grizzlyStrategyLastHoneyBalance;
        uint256 newLpTokens = claimedLp +
            StakingPool.lpBalanceOf(address(this)) -
            grizzlyStrategyLastLpBalance;
        uint256 newAdditionalHoneyTokens = claimedAdditionalHoney +
            StakingPool.getPendingHoneyRewards() -
            grizzlyStrategyLastAdditionalHoneyBalance;

        grizzlyStrategyLastHoneyBalance += newHoneyTokens;
        grizzlyStrategyLastLpBalance += newLpTokens;
        grizzlyStrategyLastAdditionalHoneyBalance += newAdditionalHoneyTokens;

        honeyRoundMask +=
            (DECIMAL_OFFSET * newHoneyTokens) /
            grizzlyStrategyDeposits;
        lpRoundMask += (DECIMAL_OFFSET * newLpTokens) / grizzlyStrategyDeposits;
        additionalHoneyRoundMask +=
            (DECIMAL_OFFSET * newAdditionalHoneyTokens) /
            grizzlyStrategyDeposits;
    }

    /// @notice Updates the user round mask for the honey and lp rewards
    function updateUserMask() internal {
        updateRoundMasks();

        participantData[msg.sender].pendingHoney +=
            ((honeyRoundMask - participantData[msg.sender].honeyMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].honeyMask = honeyRoundMask;

        participantData[msg.sender].pendingLp +=
            ((lpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].lpMask = lpRoundMask;

        participantData[msg.sender].pendingAdditionalHoney +=
            ((additionalHoneyRoundMask -
                participantData[msg.sender].additionalHoneyMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender]
            .additionalHoneyMask = additionalHoneyRoundMask;
    }

    /// @notice Claims the staked honey for an investor. The investors honnies are first unstaked from the GHNY staking pool and then transfered to the investor.
    /// @dev The investors honey mask is updated to the current honey round mask and the pending honeies are paid out
    /// @dev Can be called static to get the current investors pending Honey
    /// @return the pending Honey
    function grizzlyStrategyClaimHoney() public returns (uint256) {
        isNotPaused();
        updateRoundMasks();
        uint256 pendingHoney = participantData[msg.sender].pendingHoney +
            ((honeyRoundMask - participantData[msg.sender].honeyMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].honeyMask = honeyRoundMask;

        if (pendingHoney > 0) {
            participantData[msg.sender].pendingHoney = 0;
            StakingPool.unstake(pendingHoney);

            IERC20Upgradeable(address(HoneyToken)).safeTransfer(
                msg.sender,
                pendingHoney
            );
        }
        emit GrizzlyStrategyClaimHoneyEvent(msg.sender, pendingHoney);
        return pendingHoney;
    }

    /// @notice Claims the staked lp tokens for an investor. The investors lps are first unstaked from the GHNY staking pool and then transfered to the investor.
    /// @dev The investors lp mask is updated to the current lp round mask and the pending lps are paid out
    /// @dev Can be called static to get the current investors pending LP
    /// @return claimedHoney The claimed honey amount
    /// @return claimedBnb The claimed bnb amount
    function grizzlyStrategyClaimLP()
        public
        returns (uint256 claimedHoney, uint256 claimedBnb)
    {
        isNotPaused();
        updateRoundMasks();
        uint256 pendingLp = participantData[msg.sender].pendingLp +
            ((lpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].lpMask = lpRoundMask;

        uint256 pendingAdditionalHoney = participantData[msg.sender]
            .pendingAdditionalHoney +
            ((additionalHoneyRoundMask -
                participantData[msg.sender].additionalHoneyMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender]
            .additionalHoneyMask = additionalHoneyRoundMask;

        uint256 _claimedHoney = 0;
        uint256 _claimedBnb = 0;
        if (pendingLp > 0 || pendingAdditionalHoney > 0) {
            participantData[msg.sender].pendingLp = 0;
            participantData[msg.sender].pendingAdditionalHoney = 0;
            (_claimedHoney, _claimedBnb) = StakingPool.claimLpTokens(
                pendingLp,
                pendingAdditionalHoney,
                msg.sender
            );
        }
        emit GrizzlyStrategyClaimLpEvent(
            msg.sender,
            _claimedHoney,
            _claimedBnb
        );
        return (_claimedHoney, _claimedBnb);
    }

    /// @notice Gets the current grizzly strategy balance from the liquidity pool
    /// @return The current grizzly strategy balance for the investor
    function getGrizzlyStrategyBalance() public view returns (uint256) {
        return participantData[msg.sender].amount;
    }

    /// @notice Gets the current staked honey for a grizzly strategy investor
    /// @dev Gets the current honey balance from the GHNY staking pool to calculate the current honey round mask. This is then used to calculate the total pending honey for the investor
    /// @return The current honey balance for a grizzly investor
    function getGrizzlyStrategyStakedHoney() public view returns (uint256) {
        if (
            participantData[msg.sender].honeyMask == 0 ||
            grizzlyStrategyDeposits == 0
        ) return 0;

        (, , , , uint256 claimedHoney, , , , ) = StakingPool.stakerAmounts(
            address(this)
        );

        uint256 newHoneyTokens = claimedHoney +
            StakingPool.balanceOf(address(this)) -
            grizzlyStrategyLastHoneyBalance;
        uint256 currentHoneyRoundMask = honeyRoundMask +
            (DECIMAL_OFFSET * newHoneyTokens) /
            grizzlyStrategyDeposits;

        return
            participantData[msg.sender].pendingHoney +
            ((currentHoneyRoundMask - participantData[msg.sender].honeyMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;
    }

    /// @notice Gets the current staked lps for a grizzly strategy investor
    /// @dev Gets the current lp balance from the GHNY staking pool to calculate the current lp round mask. This is then used to calculate the total pending lp for the investor
    /// @return The current lp balance for a grizzly investor
    function getGrizzlyStrategyLpRewards() external view returns (uint256) {
        if (
            participantData[msg.sender].lpMask == 0 ||
            grizzlyStrategyDeposits == 0
        ) return 0;

        (, , , , , uint256 claimedLp, , , ) = StakingPool.stakerAmounts(
            address(this)
        );

        uint256 newLpTokens = claimedLp +
            StakingPool.lpBalanceOf(address(this)) -
            grizzlyStrategyLastLpBalance;
        uint256 currentLpRoundMask = lpRoundMask +
            (DECIMAL_OFFSET * newLpTokens) /
            grizzlyStrategyDeposits;

        return
            participantData[msg.sender].pendingLp +
            ((currentLpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;
    }

    /// @notice Reads out the participant data
    /// @param participant The address of the participant
    /// @return Participant data
    function getGrizzlyStrategyParticipantData(address participant)
        external
        view
        returns (GrizzlyStrategyParticipant memory)
    {
        return participantData[participant];
    }

    uint256[50] private __gap;
}
