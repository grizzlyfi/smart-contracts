//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IDEX.sol";
import "./Interfaces/IHoney.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title Honey-BNB-LP Staking pool
/// @notice The Honey-BNB-LP staking pool allows investors to deposit Honey-BNB-LP tokens. The investor recieves each block a certain reward in honey tokens. This blockReward can be updated by an account with UPDATER_ROLE.
/// @dev AccessControl from openzeppelin implementation is used to handle the UPDATER_ROLE, which can update the blockReward
/// User with DEFAULT_ADMIN_ROLE can grant UPDATER_ROLE to any address.
/// The DEFAULT_ADMIN_ROLE is intended to be a 2 out of 3 multisig wallet in the beginning and then be moved to governance in the future.
/// The Honey-BNB-LP staking pool uses EIP-1973 to for scalable rewards
contract HoneyBNBFarm is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    receive() external payable {}

    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct ParticipantData {
        uint256 stakedAmount;
        uint256 claimedTokens;
        uint256 rewardMask;
    }

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");
    uint256 private constant DECIMAL_OFFSET = 10e12;

    IDEX public DEX;
    IHoney public HoneyToken;
    IERC20Upgradeable public LPToken;

    uint256 public totalDeposits;
    uint256 private roundMask;
    uint256 private lastRoundMaskUpdateBlock;
    uint256 private blockRewardPhase1End;
    uint256 private blockRewardPhase2Start;
    uint256 private blockRewardPhase1Amount;
    uint256 private blockRewardPhase2Amount;

    mapping(address => ParticipantData) public participantData;

    event Stake(address indexed _staker, uint256 amount);
    event Unstake(address indexed _staker, uint256 amount);
    event ClaimRewards(address indexed _staker, uint256 amount);

    function initialize(
        address _honeyTokenAddress,
        address _lpTokenAddress,
        address _dexAddress,
        address _admin
    ) public initializer {
        roundMask = 1;
        HoneyToken = IHoney(_honeyTokenAddress);
        LPToken = IERC20Upgradeable(_lpTokenAddress);
        DEX = IDEX(_dexAddress);
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

    /// @notice Stakes the desired amount of Honey-BNB-LP tokens into the pool
    /// @dev Executes claimRewards before the staking to get a clean state for the roundMask and the rewards
    /// @param amount The desired staking amount for an investor in Honey-BNB-LP tokens
    function stakeLp(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");

        // The first person to stake will initiate reward distribution
        if (lastRoundMaskUpdateBlock == 0)
            lastRoundMaskUpdateBlock = block.number;

        claimRewards();
        participantData[msg.sender].stakedAmount += amount;
        totalDeposits += amount;

        IERC20Upgradeable(address(LPToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Stake(msg.sender, amount);
    }

    /// @notice Unstakes the desired amount of Honey-BNB-LP tokens from the pool
    /// @dev Executes claimRewards before the unstaking to get a clean state for the roundMask and the rewards
    /// @param amount The desired amount to unstake for an investor in Honey-BNB-LP tokens
    function unstakeLp(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= participantData[msg.sender].stakedAmount,
            "Amount exceeds current staked amount"
        );

        claimRewards();
        participantData[msg.sender].stakedAmount -= amount;
        totalDeposits -= amount;

        IERC20Upgradeable(address(LPToken)).safeTransfer(msg.sender, amount);

        emit Unstake(msg.sender, amount);
    }

    /// @notice Converts the supplied amount of ETH into Honey-BNB-LP tokens, then stakes it into the pool
    /// @dev Executes claimRewards before the staking to get a clean state for the roundMask and the rewards
    function stakeFromEth() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than zero");

        // The first person to stake will initiate reward distribution
        if (lastRoundMaskUpdateBlock == 0)
            lastRoundMaskUpdateBlock = block.number;

        // Convert supplied ETH into LP tokens
        (uint256 amount, uint256 unusedEth, uint256 unusedTokens) = DEX
            .convertEthToTokenLP{value: msg.value}(address(HoneyToken));

        // Send back unused ETH
        (bool transferSuccess, ) = payable(msg.sender).call{value: unusedEth}(
            ""
        );
        require(transferSuccess, "Failed to transfer unused ETH");

        // Send back unused tokens
        IERC20Upgradeable(address(HoneyToken)).transfer(
            msg.sender,
            unusedTokens
        );

        claimRewards();
        participantData[msg.sender].stakedAmount += amount;
        totalDeposits += amount;

        emit Stake(msg.sender, amount);
    }

    /// @notice Unstakes the desired amount of Honey-BNB-LP tokens from the pool, then converts it into ETH and sends it back to the caller
    /// @dev Executes claimRewards before the unstaking to get a clean state for the roundMask and the rewards
    /// @param amount The desired amount to unstake for an investor in Honey-BNB-LP tokens
    function unstakeToEth(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= participantData[msg.sender].stakedAmount,
            "Amount exceeds current staked amount"
        );

        claimRewards();
        participantData[msg.sender].stakedAmount -= amount;
        totalDeposits -= amount;

        // Allow DEX to spend supplied LP
        LPToken.approve(address(DEX), amount);

        // Convert LP tokens into ETH
        uint256 ethAmount = DEX.convertTokenLpToEth(
            address(HoneyToken),
            amount
        );

        // Send back the ETH
        (bool transferSuccess, ) = payable(msg.sender).call{value: ethAmount}(
            ""
        );
        require(transferSuccess, "Transfer failed");

        emit Unstake(msg.sender, amount);
    }

    /// @notice Converts the specified amount of the specified token into Honey-BNB-LP tokens, then stakes it into the pool
    /// @dev Executes claimRewards before the staking to get a clean state for the roundMask and the rewards
    /// @param token the address of the token to be converted into Honey-BNB-LP tokens
    /// @param tokenAmount the amount of tokens to be converted into Honey-BNB-LP tokens
    function stakeFromToken(address token, uint256 tokenAmount)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(tokenAmount > 0, "Amount must be greater than zero");

        // The first person to stake will initiate reward distribution
        if (lastRoundMaskUpdateBlock == 0)
            lastRoundMaskUpdateBlock = block.number;

        require(
            IERC20Upgradeable(token).allowance(msg.sender, address(this)) >=
                tokenAmount,
            "Token not approved"
        );

        // Pull tokens from caller
        IERC20Upgradeable(token).transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );

        // Allow DEX to spend supplied tokens
        IERC20Upgradeable(token).approve(address(DEX), tokenAmount);

        // Convert supplied tokens into ETH
        uint256 ethAmount = DEX.convertTokenToEth(tokenAmount, token);

        // Convert ETH into LP tokens
        (uint256 amount, uint256 unusedEth, uint256 unusedTokens) = DEX
            .convertEthToTokenLP{value: ethAmount}(address(HoneyToken));

        // Send back unused ETH
        (bool transferSuccess, ) = payable(msg.sender).call{value: unusedEth}(
            ""
        );
        require(transferSuccess, "Failed to transfer unused ETH");

        // Send back unused tokens
        IERC20Upgradeable(address(HoneyToken)).transfer(
            msg.sender,
            unusedTokens
        );

        claimRewards();
        participantData[msg.sender].stakedAmount += amount;
        totalDeposits += amount;

        emit Stake(msg.sender, amount);
    }

    /// @notice Unstakes the desired amount of Honey-BNB-LP tokens from the pool, then converts it into the specified token
    /// @dev Executes claimRewards before the unstaking to get a clean state for the roundMask and the rewards
    /// @param token The address of the token into which the Honey-BNB-LP tokens will be converted
    /// @param amount The desired amount to unstake for an investor in Honey-BNB-LP tokens
    function unstakeToToken(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= participantData[msg.sender].stakedAmount,
            "Amount exceeds current staked amount"
        );

        claimRewards();
        participantData[msg.sender].stakedAmount -= amount;
        totalDeposits -= amount;

        // Allow DEX to spend unstaked LP tokens
        LPToken.approve(address(DEX), amount);

        // Convert LP tokens into ETH
        uint256 ethAmount = DEX.convertTokenLpToEth(
            address(HoneyToken),
            amount
        );

        // Convert ETH into tokens
        uint256 tokenAmount = DEX.convertEthToToken{value: ethAmount}(token);

        // Send tokens back to the caller
        IERC20Upgradeable(token).transfer(msg.sender, tokenAmount);

        emit Unstake(msg.sender, amount);
    }

    /// @notice Returns the rewards generated in a specific block range
    /// @param fromBlock The starting block (exclusive)
    /// @param toBlock The ending block (inclusive)
    function getHoneyMintRewardsInRange(uint256 fromBlock, uint256 toBlock)
        public
        view
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

    /// @notice Returns the pending rewards for an investor
    /// @dev Caluclates the pending rewards by using the differrence of the currentRoundMask of the pool and the investors rewardMask and the share of the total staked amount.
    /// @return The pending reward for the investor
    function pendingRewards() external view returns (uint256) {
        if (participantData[msg.sender].rewardMask == 0) return 0;

        uint256 currentRoundMask = roundMask;

        if (totalDeposits > 0) {
            uint256 totalPendingRewards = getHoneyMintRewardsInRange(
                lastRoundMaskUpdateBlock,
                block.number
            );

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
    function claimRewards() public whenNotPaused {
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
            participantData[msg.sender].claimedTokens += rewardsToTransfer;

            IERC20Upgradeable(address(HoneyToken)).safeTransfer(
                msg.sender,
                rewardsToTransfer
            );
            emit ClaimRewards(msg.sender, rewardsToTransfer);
        }
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
    ) public onlyRole(UPDATER_ROLE) {
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

    /// @notice Updates the round mask for the pool
    /// @dev The round mask is calculated using block reward multiplied by the difference of the current block and the block where round mask was last updated at
    function updateRoundMask() internal {
        if (totalDeposits == 0) return;

        uint256 totalPendingRewards = getHoneyMintRewardsInRange(
            lastRoundMaskUpdateBlock,
            block.number
        );

        lastRoundMaskUpdateBlock = block.number;
        roundMask += (DECIMAL_OFFSET * totalPendingRewards) / totalDeposits;
    }

    /// @notice Used to recover funds sent to this contract by mistake
    function recoverFunds(uint256 amount)
        external
        nonReentrant
        onlyRole(FUNDS_RECOVERY_ROLE)
    {
        require(amount <= address(this).balance, "Insufficient funds");
        (bool transferSuccess, ) = payable(msg.sender).call{value: amount}("");
        require(transferSuccess, "Transfer failed");
    }

    uint256[50] private __gap;
}
