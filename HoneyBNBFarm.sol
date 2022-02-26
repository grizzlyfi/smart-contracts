//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IHoney.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Honey-BNB-LP Staking pool
/// @notice The Honey-BNB-LP staking pool allows investors to deposit Honey-BNB-LP tokens. The investor recieves each block a certain reward in honey tokens. This blockReward can be updated by an account with UPDATER_ROLE.
/// @dev AccessControl from openzeppelin implementation is used to handle the UPDATER_ROLE, which can update the blockReward
/// User with DEFAULT_ADMIN_ROLE can grant UPDATER_ROLE to any address.
/// The DEFAULT_ADMIN_ROLE is intended to be a 2 out of 3 multisig wallet in the beginning and then be moved to governance in the future.
/// The Honey-BNB-LP staking pool uses EIP-1973 to for scalable rewards
contract HoneyBNBFarm is AccessControl {
    using SafeERC20 for IERC20;

    struct ParticipantData {
        uint256 stakedAmount;
        uint256 rewardMask;
    }

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint256 private constant DECIMAL_OFFSET = 10e12;

    IHoney public HoneyToken;
    IERC20 public LPToken;

    uint256 public totalDeposits = 0;
    uint256 private roundMask = 1;
    uint256 private lastRoundMaskUpdateBlock = 0;
    uint256 public blockReward;

    mapping(address => ParticipantData) public participantData;

    event Stake(address indexed _staker, uint256 amount);
    event Unstake(address indexed _staker, uint256 amount);
    event ClaimRewards(address indexed _staker, uint256 amount);

    constructor(
        address _honeyTokenAddress,
        address _lpTokenAddress,
        uint256 _blockReward,
        address _admin
    ) {
        HoneyToken = IHoney(_honeyTokenAddress);
        LPToken = IERC20(_lpTokenAddress);
        blockReward = _blockReward;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Stakes the desired amount of Honey-BNB-LP tokens into the pool
    /// @dev Executes claimRewards before the staking to get a clean state for the roundMask and the rewards
    /// @param amount The desired staking amount for an investor in Honey-BNB-LP tokens
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        // The first person to stake will initiate reward distribution
        if (lastRoundMaskUpdateBlock == 0)
            lastRoundMaskUpdateBlock = block.number;

        claimRewards();
        participantData[msg.sender].stakedAmount += amount;
        totalDeposits += amount;

        IERC20(address(LPToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Stake(msg.sender, amount);
    }

    /// @notice Unstakes the desired amount of Honey-BNB-LP tokens from the pool
    /// @dev Executes claimRewards before the unstaking to get a clean state for the roundMask and the rewards
    /// @param amount The desired amount to unstake for an investor in Honey-BNB-LP tokens
    function unstake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= participantData[msg.sender].stakedAmount,
            "Amount exceeds current staked amount"
        );

        claimRewards();
        participantData[msg.sender].stakedAmount -= amount;
        totalDeposits -= amount;

        IERC20(address(LPToken)).safeTransfer(msg.sender, amount);

        emit Unstake(msg.sender, amount);
    }

    /// @notice Returns the pending rewards for an investor
    /// @dev Caluclates the pending rewards by using the differrence of the currentRoundMask of the pool and the investors rewardMask and the share of the total staked amount.
    /// @return The pending reward for the investor
    function pendingRewards() external view returns (uint256) {
        if (participantData[msg.sender].rewardMask == 0) return 0;

        uint256 currentRoundMask = roundMask;

        if (totalDeposits > 0 && blockReward > 0) {
            uint256 totalPendingRewards = (block.number -
                lastRoundMaskUpdateBlock) * blockReward;

            currentRoundMask +=
                (DECIMAL_OFFSET * totalPendingRewards) /
                totalDeposits;
        }

        return
            ((currentRoundMask - participantData[msg.sender].rewardMask) *
                participantData[msg.sender].stakedAmount) / DECIMAL_OFFSET;
    }

    /// @notice Claims the current rewards for an investor
    /// @dev The round mask is updated in the first place to update the current rewards for the investor. The rewards in honey tokens are then minted and transferred to the investor
    function claimRewards() public {
        updateRoundMask();

        if (participantData[msg.sender].rewardMask == 0) {
            participantData[msg.sender].rewardMask = roundMask;
            return;
        }

        uint256 rewardsToTransfer = ((roundMask -
            participantData[msg.sender].rewardMask) *
            participantData[msg.sender].stakedAmount) / DECIMAL_OFFSET;

        participantData[msg.sender].rewardMask = roundMask;

        if (rewardsToTransfer > 0) {
            HoneyToken.claimTokens(rewardsToTransfer);

            IERC20(address(HoneyToken)).safeTransfer(
                msg.sender,
                rewardsToTransfer
            );
            emit ClaimRewards(msg.sender, rewardsToTransfer);
        }
    }

    /// @notice Updates the reward per block
    /// @dev Can only be executed by an account with UPDATER_ROLE
    /// @param _blockReward The desired new block reward
    function setBlockReward(uint256 _blockReward)
        external
        onlyRole(UPDATER_ROLE)
    {
        blockReward = _blockReward;
    }

    /// @notice Updates the round mask for the pool
    /// @dev The round mask is calculated using block reward multiplied by the difference of the current block and the block where round mask was last updated at
    function updateRoundMask() internal {
        if (totalDeposits == 0 || blockReward == 0) return;

        uint256 totalPendingRewards = (block.number -
            lastRoundMaskUpdateBlock) * blockReward;

        lastRoundMaskUpdateBlock = block.number;
        roundMask += (DECIMAL_OFFSET * totalPendingRewards) / totalDeposits;
    }
}
