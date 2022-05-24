//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Interfaces/IUniswapV2Router01.sol";
import "./Interfaces/IUniswapV2Pair.sol";
import "./Interfaces/IHoney.sol";
import "./Interfaces/IStakingPool.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title The honey staking pool
/// @notice The honey staking pool allows to stake honeys and get lp and honey rewards. Lp tokens are rewarded through rewards from the liquidity pools (see tokenflow)
/// @dev The share of lp and honey rewards is done with roundmasks according to EIP-1973
contract StakingPool is
    Initializable,
    AccessControlUpgradeable,
    IStakingPool,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant DECIMAL_OFFSET = 10e12;

    struct StakerAmounts {
        uint256 stakedAmount;
        uint256 honeyMask;
        uint256 lpMask;
        uint256 pendingLp;
        uint256 claimedHoney;
        uint256 claimedLp;
        uint256 honeyMintMask;
        uint256 pendingHoneyMint;
        uint256 claimedHoneyMint;
    }

    IUniswapV2Router01 public SwapRouter;
    IHoney public StakedToken;
    IERC20Upgradeable public LPToken;

    uint256 private honeyRoundMask;
    uint256 private lpRoundMask;
    uint256 private honeyMintRoundMask;
    uint256 private lastHoneyMintRoundMaskUpdateBlock;
    uint256 private blockRewardPhase1End;
    uint256 private blockRewardPhase2Start;
    uint256 private blockRewardPhase1Amount;
    uint256 private blockRewardPhase2Amount;

    uint256 public totalStaked;
    uint256 public totalBnbClaimed;
    uint256 public totalHoneyClaimed;

    mapping(address => StakerAmounts) public override stakerAmounts;

    event Stake(address indexed _staker, uint256 amount);
    event Unstake(address indexed _staker, uint256 amount);
    event ClaimRewards(
        address indexed _staker,
        uint256 _tokenAmount,
        uint256 _bnbAmount
    );

    function initialize(
        address tokenAddress,
        address lpAddress,
        address swapRouterAddress,
        address admin
    ) public initializer {
        require(
            IUniswapV2Pair(lpAddress).token0() == tokenAddress ||
                IUniswapV2Pair(lpAddress).token1() == tokenAddress,
            "LP token does not contain one side of token address"
        );

        honeyRoundMask = 1;
        lpRoundMask = 1;
        honeyMintRoundMask = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        SwapRouter = IUniswapV2Router01(swapRouterAddress);
        StakedToken = IHoney(tokenAddress);
        LPToken = IERC20Upgradeable(lpAddress);
        LPToken.safeApprove(swapRouterAddress, type(uint256).max);
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

    /// @notice Stakes the desired amount of honey into the staking pool
    /// @dev Lp reward masks are updated before the staking to have a clean state
    /// @param amount The desired staking amount
    function stake(uint256 amount) external override whenNotPaused {
        // if first stake initialize lastHoneyMintRoundMaskUpdateBlock
        if (lastHoneyMintRoundMaskUpdateBlock == 0) {
            lastHoneyMintRoundMaskUpdateBlock = block.number;
        }

        updateLpRewardMask();
        updateAdditionalMintRewardMask();
        uint256 currentBalance = balanceOf(msg.sender);

        if (stakerAmounts[msg.sender].honeyMintMask == 0)
            stakerAmounts[msg.sender].honeyMintMask = honeyMintRoundMask;

        if (amount > 0) {
            IERC20Upgradeable(address(StakedToken)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        totalStaked =
            totalStaked +
            currentBalance -
            stakerAmounts[msg.sender].stakedAmount +
            amount;

        stakerAmounts[msg.sender].stakedAmount = currentBalance + amount;
        stakerAmounts[msg.sender].honeyMask = honeyRoundMask;

        emit Stake(msg.sender, amount);
    }

    /// @notice Unstake the desired amount of honey from the staking pool
    /// @dev Lp reward masks are updated before the unstaking to have a clean state
    /// @param amount The desired unstaking amount
    function unstake(uint256 amount) external override whenNotPaused {
        require(amount > 0, "The amount of tokens must be greater than zero");

        updateLpRewardMask();
        updateAdditionalMintRewardMask();
        uint256 currentBalance = balanceOf(msg.sender);
        require(currentBalance >= amount, "Requested amount too large");

        totalStaked =
            totalStaked +
            currentBalance -
            stakerAmounts[msg.sender].stakedAmount -
            amount;

        stakerAmounts[msg.sender].stakedAmount = currentBalance - amount;
        stakerAmounts[msg.sender].honeyMask = honeyRoundMask;
        stakerAmounts[msg.sender].claimedHoney += amount;

        IERC20Upgradeable(address(StakedToken)).safeTransfer(
            msg.sender,
            amount
        );

        emit Unstake(msg.sender, amount);
    }

    /// @notice Gets the current staked balance
    /// @dev Returns the staked amount and all the honey rewards together
    /// @param staker The staker address whos balance is requested
    /// @return The staked amount in honey
    function balanceOf(address staker) public view override returns (uint256) {
        if (stakerAmounts[staker].honeyMask == 0) return 0;

        return
            stakerAmounts[staker].stakedAmount +
            ((honeyRoundMask - stakerAmounts[staker].honeyMask) *
                stakerAmounts[staker].stakedAmount) /
            DECIMAL_OFFSET;
    }

    /// @notice Rewards the staking pool with honey
    /// @dev The round mask is increased according to the reward
    /// @param amount The amount to be rewarded
    function rewardHoney(uint256 amount) external override whenNotPaused {
        require(totalStaked > 0, "totalStaked amount is 0");
        IERC20Upgradeable(address(StakedToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        honeyRoundMask += (DECIMAL_OFFSET * amount) / totalStaked;
    }

    /// @notice Gets the current lp balance
    /// @dev Returns the lp amount and the difference from the round mask
    /// @param staker The staker address whos lp balance is requested
    /// @return The staked lp amount
    function lpBalanceOf(address staker)
        public
        view
        override
        returns (uint256)
    {
        if (stakerAmounts[staker].lpMask == 0) return 0;

        return
            stakerAmounts[staker].pendingLp +
            ((lpRoundMask - stakerAmounts[staker].lpMask) *
                stakerAmounts[staker].stakedAmount) /
            DECIMAL_OFFSET;
    }

    /// @notice Updates the Lp reward mask
    /// @dev Assigns the current lp amount to the account and resets the round mask
    function updateLpRewardMask() public override whenNotPaused {
        uint256 currentLpBalance = lpBalanceOf(msg.sender);

        stakerAmounts[msg.sender].pendingLp = currentLpBalance;
        stakerAmounts[msg.sender].lpMask = lpRoundMask;
    }

    /// @notice Updates the additional Honey Minting round mask
    /// @dev Updates the round mask based on the number of blocks passed since last update, current block reward and total staked amount
    function updateAdditionalMintRoundMask() public override whenNotPaused {
        if (totalStaked == 0) return;

        uint256 totalPendingRewards = getHoneyMintRewardsInRange(
            lastHoneyMintRoundMaskUpdateBlock,
            block.number
        );

        lastHoneyMintRoundMaskUpdateBlock = block.number;
        honeyMintRoundMask +=
            (DECIMAL_OFFSET * totalPendingRewards) /
            totalStaked;
    }

    function updateAdditionalMintRewardMask() public whenNotPaused {
        updateAdditionalMintRoundMask();
        uint256 pendingHoneyRewards = getPendingHoneyRewards();

        stakerAmounts[msg.sender].pendingHoneyMint = pendingHoneyRewards;
        stakerAmounts[msg.sender].honeyMintMask = honeyMintRoundMask;
    }

    /// @notice Returns the rewards generated in a specific block range
    /// @param fromBlock The starting block (exclusive)
    /// @param toBlock The ending block (inclusive)
    function getHoneyMintRewardsInRange(uint256 fromBlock, uint256 toBlock)
        public
        view
        override
        returns (uint256)
    {
        uint256 phase1Rewards = 0;
        uint256 linearPhaseRewards = 0;
        uint256 phase2Rewards = 0;

        if (blockRewardPhase1End > fromBlock) {
            uint256 phaseEndBlock = toBlock < blockRewardPhase1End
                ? toBlock
                : blockRewardPhase1End;
            phase1Rewards =
                (phaseEndBlock - fromBlock) *
                blockRewardPhase1Amount;
        }

        if (
            fromBlock < blockRewardPhase2Start && blockRewardPhase1End < toBlock
        ) {
            uint256 phaseStartBlock = fromBlock < blockRewardPhase1End
                ? blockRewardPhase1End
                : fromBlock;
            uint256 phaseEndBlock = toBlock < blockRewardPhase2Start
                ? toBlock
                : blockRewardPhase2Start;

            uint256 linearPhaseRewardDifference = blockRewardPhase1Amount -
                blockRewardPhase2Amount;
            uint256 linearPhaseBlockLength = blockRewardPhase2Start -
                blockRewardPhase1End;
            uint256 phaseStartBlockReward = blockRewardPhase1Amount -
                ((phaseStartBlock - blockRewardPhase1End) *
                    linearPhaseRewardDifference) /
                linearPhaseBlockLength;
            uint256 phaseEndBlockReward = blockRewardPhase1Amount -
                ((phaseEndBlock - blockRewardPhase1End) *
                    linearPhaseRewardDifference) /
                linearPhaseBlockLength;

            linearPhaseRewards =
                ((phaseEndBlock - phaseStartBlock) *
                    (phaseStartBlockReward + phaseEndBlockReward)) /
                2;
        }

        if (blockRewardPhase2Start < toBlock) {
            uint256 phaseStartBlock = fromBlock < blockRewardPhase2Start
                ? blockRewardPhase2Start
                : fromBlock;
            phase2Rewards =
                (toBlock - phaseStartBlock) *
                blockRewardPhase2Amount;
        }

        return phase1Rewards + linearPhaseRewards + phase2Rewards;
    }

    /// @notice Returns te pending amount of minted Honey rewards
    /// @dev The result is based on the current round mask, as well as the change in the round mask since the last update
    /// @return Pending rewards
    function getPendingHoneyRewards() public view override returns (uint256) {
        if (stakerAmounts[msg.sender].honeyMintMask == 0) return 0;

        uint256 currentRoundMask = honeyMintRoundMask;

        if (totalStaked > 0) {
            uint256 totalPendingRewards = getHoneyMintRewardsInRange(
                lastHoneyMintRoundMaskUpdateBlock,
                block.number
            );

            currentRoundMask +=
                (DECIMAL_OFFSET * totalPendingRewards) /
                totalStaked;
        }

        return
            stakerAmounts[msg.sender].pendingHoneyMint +
            ((currentRoundMask - stakerAmounts[msg.sender].honeyMintMask) *
                stakerAmounts[msg.sender].stakedAmount) /
            DECIMAL_OFFSET;
    }

    /// @notice Withdraws LP tokens to remove liquidity from pancakeswap and withdraws additional honey rewards
    /// @dev Uses the pancakeswap router to remove liquidity with the desired LP amount. The staked token and the corresponding bnb are transferred to the account. In addition a reward in honey token is calculated and minted for the account
    /// @param amount The desired lp amount which should be used to remove liquidity from pancakeswap
    /// @param additionalHoneyAmount The desired additional honey amount to be claimed
    /// @param to The Account the staked token, the bnb and the additional honey reward is sent to
    function claimLpTokens(
        uint256 amount,
        uint256 additionalHoneyAmount,
        address to
    )
        external
        override
        whenNotPaused
        returns (uint256 stakedTokenOut, uint256 bnbOut)
    {
        updateLpRewardMask();
        updateAdditionalMintRewardMask();
        uint256 removedStakedToken = 0;
        uint256 removedBnb = 0;

        if (amount > 0) {
            require(
                stakerAmounts[msg.sender].pendingLp >= amount,
                "Requested amount too large"
            );

            stakerAmounts[msg.sender].pendingLp -= amount;
            stakerAmounts[msg.sender].claimedLp += amount;

            (removedStakedToken, removedBnb) = SwapRouter.removeLiquidityETH(
                address(StakedToken),
                amount,
                1,
                1,
                to,
                block.timestamp + 300
            );
        }

        if (additionalHoneyAmount > 0) {
            require(
                stakerAmounts[msg.sender].pendingHoneyMint >=
                    additionalHoneyAmount,
                "Requested additionalHoneyAmount too large"
            );

            stakerAmounts[msg.sender].pendingHoneyMint -= additionalHoneyAmount;
            stakerAmounts[msg.sender].claimedHoneyMint += additionalHoneyAmount;

            StakedToken.claimTokens(additionalHoneyAmount);
            IERC20Upgradeable(address(StakedToken)).safeTransfer(
                to,
                additionalHoneyAmount
            );
        }

        totalHoneyClaimed += removedStakedToken + additionalHoneyAmount;
        totalBnbClaimed += removedBnb;

        emit ClaimRewards(
            msg.sender,
            removedStakedToken + additionalHoneyAmount,
            removedBnb
        );
        return (removedStakedToken + additionalHoneyAmount, removedBnb);
    }

    /// @notice Rewards lp to the conract
    /// @dev The round mask is increased according to the reward
    /// @param amount The amount in lp to be rewarded
    function rewardLP(uint256 amount) external override whenNotPaused {
        if (totalStaked == 0) return;

        IERC20Upgradeable(address(LPToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        lpRoundMask += (DECIMAL_OFFSET * amount) / totalStaked;
    }

    /// @notice Sets the honey minting transition times and amounts
    /// @param _blockRewardPhase1End the block after which Phase 1 ends
    /// @param _blockRewardPhase2Start the block after which Phase 2 starts
    /// @param _blockRewardPhase1Amount the block rewards during Phase 1
    /// @param _blockRewardPhase2Amount the block rewards during Phase 2
    function setHoneyMintingRewards(
        uint256 _blockRewardPhase1End,
        uint256 _blockRewardPhase2Start,
        uint256 _blockRewardPhase1Amount,
        uint256 _blockRewardPhase2Amount
    ) public override onlyRole(UPDATER_ROLE) {
        require(
            _blockRewardPhase1End < _blockRewardPhase2Start,
            "Phase 1 must end before Phase 2 starts"
        );
        require(
            _blockRewardPhase2Amount < _blockRewardPhase1Amount,
            "Phase 1 amount must be greater than Phase 2 amount"
        );

        blockRewardPhase1End = _blockRewardPhase1End;
        blockRewardPhase2Start = _blockRewardPhase2Start;
        blockRewardPhase1Amount = _blockRewardPhase1Amount;
        blockRewardPhase2Amount = _blockRewardPhase2Amount;
    }

    uint256[50] private __gap;
}
