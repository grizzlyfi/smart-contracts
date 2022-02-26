//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./DEX/DEX.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Strategy/GrizzlyStrategy.sol";
import "./Strategy/StableCoinStrategy.sol";
import "./Strategy/StandardStrategy.sol";
import "./Config/BaseConfig.sol";
import "./Interfaces/IGrizzly.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title The Grizzly contract
/// @notice This contract put together all abstract contracts and is deployed once for each token pair (hive). It allows the user to deposit and withdraw funds to the predefined hive. In addition, rewards can be staked using stakeReward.
/// @dev AccessControl from openzeppelin implementation is used to handle the update of the beeEfficiencyThreshold.
/// User with DEFAULT_ADMIN_ROLE can grant UPDATER_ROLE to any address.
/// The DEFAULT_ADMIN_ROLE is intended to be a 2 out of 3 multisig wallet in the beginning and then be moved to governance in the future.
/// The Contract uses ReentrancyGuard from openzeppelin for all transactions that transfer bnbs to the msg.sender
contract Grizzly is
    BaseConfig,
    ReentrancyGuard,
    GrizzlyStrategy,
    StableCoinStrategy,
    StandardStrategy,
    DEX,
    IGrizzly
{
    using SafeERC20 for IERC20;

    constructor(
        address _Admin,
        address _SwapRouterAddress,
        address _StakingContractAddress,
        address _StakingPoolAddress,
        address _HoneyTokenAddress,
        address _HoneyBnbLpTokenAddress,
        address _DevTeamAddress,
        address _ReferralAddress,
        uint256 _PoolID
    )
        BaseConfig(
            _Admin,
            _SwapRouterAddress,
            _StakingContractAddress,
            _StakingPoolAddress,
            _HoneyTokenAddress,
            _HoneyBnbLpTokenAddress,
            _DevTeamAddress,
            _ReferralAddress,
            _PoolID
        )
    {
        beeEfficiencyThreshold = 500 ether;
        isEmergency = false;
    }

    uint256 public beeEfficiencyThreshold;
    bool public isEmergency;

    mapping(address => Strategy) public userStrategy;
    uint256 private totalUnusedTokenA;
    uint256 private totalUnusedTokenB;

    modifier emergency(bool _state) {
        require(isEmergency == _state, "Not allowed in this emergency state");
        _;
    }

    event DepositEvent(
        address indexed user,
        uint256 lpAmount,
        Strategy indexed currentStrategy
    );
    event WithdrawEvent(
        address indexed user,
        uint256 lpAmount,
        Strategy indexed currentStrategy
    );
    event SwitchStrategyEvent(
        address indexed user,
        Strategy indexed fromStrategy,
        Strategy indexed toStrategy
    );
    event StakeRewardsEvent(
        address indexed caller,
        uint256 bnbAmount,
        uint256 standardShare,
        uint256 grizzlyShare,
        uint256 stablecoinShare
    );

    /// @notice The public deposit function
    /// @dev This is a payable function where the user can deposit bnbs
    /// @param referralGiver The address of the account that provided referral
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return The value in LP tokens that was deposited
    function deposit(
        address referralGiver,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    )
        external
        payable
        override
        nonReentrant
        emergency(false)
        returns (uint256)
    {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        return _deposit(msg.value, referralGiver);
    }

    /// @notice The public deposit from token function
    /// @dev The user can define a token which he would like to use to deposit. This token is then firstly converted into bnbs
    /// @param token The tokens address
    /// @param amount The amount of the token to be deposited
    /// @param referralGiver The address of the account that provided referral
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return The value in LP tokens that was deposited
    function depositFromToken(
        address token,
        uint256 amount,
        address referralGiver,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external override nonReentrant emergency(false) returns (uint256) {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        IERC20 tokenContract = IERC20(token);
        tokenContract.safeTransferFrom(msg.sender, address(this), amount);
        uint256 amountConverted = convertTokenToEth(amount, token);
        return _deposit(amountConverted, referralGiver);
    }

    /// @notice The public withdraw function
    /// @dev Withdraws the desired amount for the user and transfers the bnbs to the user by using the call function. Adds a reentrant guard
    /// @param amount The amount of the token to be withdrawn
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return The value in BNB that was withdrawn
    function withdraw(
        uint256 amount,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external override nonReentrant emergency(false) returns (uint256) {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        _stakeRewards();
        uint256 amountWithdrawn = _withdraw(amount);
        (bool transferSuccess, ) = payable(msg.sender).call{
            value: amountWithdrawn
        }("");
        require(transferSuccess, "Transfer failed");
        return amountWithdrawn;
    }

    /// @notice The public withdraw all function
    /// @dev Calculates the total staked amount in the first place and uses that to withdraw all funds. Adds a reentrant guard
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return The value in BNB that was withdrawn
    function withdrawAll(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external override nonReentrant emergency(false) returns (uint256) {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        _stakeRewards();
        uint256 currentDeposits = 0;

        if (userStrategy[msg.sender] == Strategy.STANDARD) {
            currentDeposits = getStandardStrategyBalance();
        } else if (userStrategy[msg.sender] == Strategy.GRIZZLY) {
            currentDeposits = getGrizzlyStrategyBalance();
        } else {
            currentDeposits = getStablecoinStrategyBalance();
        }

        uint256 amountWithdrawn = 0;
        if (currentDeposits > 0) {
            amountWithdrawn = _withdraw(currentDeposits);
            (bool transferSuccess, ) = payable(msg.sender).call{
                value: amountWithdrawn
            }("");
            require(transferSuccess, "Transfer failed");
        }
        return amountWithdrawn;
    }

    /// @notice The public withdraw to token function
    /// @dev The user can define a token in which he would like to withdraw the deposits. The bnb amount is converted into the token and transferred to the user
    /// @param token The tokens address
    /// @param amount The amount of the token to be withdrawn
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return The value in token amount that was withdrawn
    function withdrawToToken(
        address token,
        uint256 amount,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external override nonReentrant emergency(false) returns (uint256) {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        _stakeRewards();
        uint256 amountWithdrawn = _withdraw(amount);
        uint256 tokenAmountWithdrawn = convertEthToToken(
            amountWithdrawn,
            token
        );
        IERC20(token).safeTransfer(msg.sender, tokenAmountWithdrawn);
        return tokenAmountWithdrawn;
    }

    /// @notice The internal deposit function
    /// @dev The actual deposit function. Bnbs are converted to lp tokens of the token pair and then staked with masterchef
    /// @param amount The amount of bnb to be deposited
    /// @param referralGiver The address of the account that provided referral
    /// @return The value in LP tokens that was deposited
    function _deposit(uint256 amount, address referralGiver)
        internal
        returns (uint256)
    {
        require(amount > 0, "Deposit needs to be larger than 0");
        _stakeRewards();

        (
            uint256 lpValue,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        ) = convertEthToPairLP(amount, address(TokenA), address(TokenB));

        totalUnusedTokenA += unusedTokenA;
        totalUnusedTokenB += unusedTokenB;

        if (userStrategy[msg.sender] == Strategy.STANDARD) {
            standardStrategyDeposit(lpValue);
        } else if (userStrategy[msg.sender] == Strategy.GRIZZLY) {
            grizzlyStrategyDeposit(lpValue);
        } else {
            stablecoinStrategyDeposit(lpValue);
        }

        StakingContract.deposit(PoolID, lpValue);

        Referral.referralDeposit(lpValue, msg.sender, referralGiver);
        emit DepositEvent(msg.sender, lpValue, userStrategy[msg.sender]);
        return lpValue;
    }

    /// @notice The internal withdraw function
    /// @dev The actual withdraw function. First the withdrwan from the strategy is performed and then Lp tokens are withdrawn from masterchef, converted into bnbs and returned.
    /// @param amount The amount of bnb to be withdrawn
    /// @return Amount to be withdrawn
    function _withdraw(uint256 amount) internal returns (uint256) {
        if (userStrategy[msg.sender] == Strategy.STANDARD) {
            standardStrategyWithdraw(amount);
            standardStrategyClaimHoney();
        } else if (userStrategy[msg.sender] == Strategy.GRIZZLY) {
            grizzlyStrategyWithdraw(amount);
            grizzlyStrategyClaimHoney();
            grizzlyStrategyClaimLP();
        } else {
            stablecoinStrategyWithdraw(amount);
        }

        StakingContract.withdraw(PoolID, amount);

        uint256 bnbAmount = convertPairLpToEth(
            address(TokenA),
            address(TokenB),
            amount
        );

        Referral.referralWithdraw(amount, msg.sender);
        emit WithdrawEvent(msg.sender, amount, userStrategy[msg.sender]);
        return bnbAmount;
    }

    /// @notice Change the strategy of a user
    /// @dev When changing the strategy, the amount is withdrawn from the current strategy and deposited into the new strategy
    /// @param toStrategy the strategy the user wants to change to
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    function changeStrategy(
        Strategy toStrategy,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external override nonReentrant emergency(false) {
        require(deadline > block.timestamp, "Deadline expired");
        require(
            userStrategy[msg.sender] != toStrategy,
            "User already in selected strategy"
        );
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);

        _stakeRewards();
        uint256 currentDeposits = 0;

        if (userStrategy[msg.sender] == Strategy.STANDARD) {
            currentDeposits = getStandardStrategyBalance();
            if (currentDeposits > 0) {
                standardStrategyWithdraw(currentDeposits);
                standardStrategyClaimHoney();
            }
        } else if (userStrategy[msg.sender] == Strategy.GRIZZLY) {
            currentDeposits = getGrizzlyStrategyBalance();
            if (currentDeposits > 0) {
                grizzlyStrategyWithdraw(currentDeposits);
                grizzlyStrategyClaimHoney();
                grizzlyStrategyClaimLP();
            }
        } else {
            currentDeposits = getStablecoinStrategyBalance();
            if (currentDeposits > 0) {
                stablecoinStrategyWithdraw(currentDeposits);
            }
        }

        if (currentDeposits > 0) {
            if (toStrategy == Strategy.STANDARD)
                standardStrategyDeposit(currentDeposits);
            else if (toStrategy == Strategy.GRIZZLY)
                grizzlyStrategyDeposit(currentDeposits);
            else stablecoinStrategyDeposit(currentDeposits);
        }

        emit SwitchStrategyEvent(
            msg.sender,
            userStrategy[msg.sender],
            toStrategy
        );
        userStrategy[msg.sender] = toStrategy;
    }

    /// @notice Stake rewards public function and sends unused tokens to caller
    /// @dev Executes the restaking of the rewards. Adds a reentrant guard
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return rewardedTokenA The amount of the rewarded token A
    /// @return rewardedTokenB The amount of the rewarded token B
    function stakeRewardsForBounty(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    )
        external
        override
        nonReentrant
        emergency(false)
        returns (uint256 rewardedTokenA, uint256 rewardedTokenB)
    {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        _stakeRewards();
        TokenA.safeTransfer(msg.sender, totalUnusedTokenA);
        TokenB.safeTransfer(msg.sender, totalUnusedTokenB);
        rewardedTokenA = totalUnusedTokenA;
        rewardedTokenB = totalUnusedTokenB;
        totalUnusedTokenA = 0;
        totalUnusedTokenB = 0;
    }

    /// @notice Stake rewards public function
    /// @dev Executes the restaking of the rewards. Adds a reentrant guard
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    /// @param deadline The deadline for the transaction
    /// @return totalBnb The total BNB reward
    /// @return standardBnb the standard BNB reward
    /// @return grizzlyBnb the grizzly BNB reward
    /// @return stablecoinBnb the stalbcoin BNB reward
    function stakeRewards(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    )
        external
        override
        nonReentrant
        emergency(false)
        returns (
            uint256 totalBnb,
            uint256 standardBnb,
            uint256 grizzlyBnb,
            uint256 stablecoinBnb
        )
    {
        require(deadline > block.timestamp, "Deadline expired");
        checkSlippage(fromToken, toToken, amountIn, amountOut, slippage);
        return _stakeRewards();
    }

    /// @notice The actual internal stake rewards function
    /// @dev Executes the actual restaking of the rewards. Gets the current rewards from masterchef and divides the reward into the different strategies.
    /// Then executes the stakereward for the strategies. StakingContract.deposit(PoolID, 0); is executed in order to update the balance of the reward token
    /// @return totalBnb The total BNB reward
    /// @return standardBnb the standard BNB reward
    /// @return grizzlyBnb the grizzly BNB reward
    /// @return stablecoinBnb the stalbcoin BNB reward
    function _stakeRewards()
        internal
        returns (
            uint256 totalBnb,
            uint256 standardBnb,
            uint256 grizzlyBnb,
            uint256 stablecoinBnb
        )
    {
        // Get rewards from MasterChef
        StakingContract.deposit(PoolID, 0);
        uint256 currentRewards = RewardToken.balanceOf(address(this));

        if (currentRewards == 0) return (0, 0, 0, 0);

        // Convert all rewards to BNB
        uint256 bnbAmount = convertTokenToEth(
            currentRewards,
            address(RewardToken)
        );

        uint256 totalDeposits = standardStrategyDeposits +
            grizzlyStrategyDeposits +
            stablecoinStrategyDeposits;

        uint256 standardShare = 0;
        uint256 grizzlyShare = 0;
        if (totalDeposits != 0) {
            standardShare =
                (bnbAmount * standardStrategyDeposits) /
                totalDeposits;
            grizzlyShare =
                (bnbAmount * grizzlyStrategyDeposits) /
                totalDeposits;
        }
        uint256 stablecoinShare = bnbAmount - standardShare - grizzlyShare;

        if (standardShare > 100) stakeStandardRewards(standardShare);
        if (grizzlyShare > 100) stakeGrizzlyRewards(grizzlyShare);
        if (stablecoinShare > 100) stakeStablecoinRewards(stablecoinShare);

        if (bnbAmount > 100 && totalDeposits != 0) {
            // Get the price of Honey relative to BNB
            uint256 beeEfficiencyLevel = getTokenEthPrice(address(HoneyToken));
            // get 1 % of the referralDeposit totalDeposit share
            uint256 referralReward = (bnbAmount *
                Referral.totalReferralDepositForPool(address(this))) /
                totalDeposits /
                100;

            // Honey (based on Honey-BNB price) is minted
            uint256 mintedHoney = mintTokens(
                referralReward,
                beeEfficiencyLevel
            );
            // referral contract is rewarded with the minted honey
            Referral.referralUpdateRewards(mintedHoney);
        }

        emit StakeRewardsEvent(
            msg.sender,
            bnbAmount,
            standardShare,
            grizzlyShare,
            stablecoinShare
        );
        return (bnbAmount, standardShare, grizzlyShare, stablecoinShare);
    }

    /// @notice Stakes the rewards for the standard strategy
    /// @param bnbReward The pending bnb reward to be restaked
    function stakeStandardRewards(uint256 bnbReward) internal {
        // 70% of the BNB is converted into TokenA-TokenB LP tokens
        uint256 tokenPairLpShare = (bnbReward * 70) / 100;
        (
            uint256 tokenPairLpAmount,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        ) = convertEthToPairLP(
                tokenPairLpShare,
                address(TokenA),
                address(TokenB)
            );

        totalUnusedTokenA += unusedTokenA;
        totalUnusedTokenB += unusedTokenB;

        // Update TokenA-TokenB LP rewards
        standardStrategyRewardLP(tokenPairLpAmount);

        // The TokenA-TokenB LP tokens are staked in the MasterChef
        StakingContract.deposit(PoolID, tokenPairLpAmount);

        // Get the price of Honey relative to BNB
        uint256 beeEfficiencyLevel = getTokenEthPrice(address(HoneyToken));

        // If Honey price too low, use buyback strategy
        if (beeEfficiencyLevel > beeEfficiencyThreshold) {
            // 24% of the BNB is used to buy Honey from the DEX
            uint256 honeyBuybackShare = (bnbReward * 24) / 100;
            uint256 honeyBuybackAmount = convertEthToToken(
                honeyBuybackShare,
                address(HoneyToken)
            );

            // 6% of the equivalent amount of Honey (based on Honey-BNB price) is minted
            uint256 mintedHoney = mintTokens(
                (bnbReward * 6) / 100,
                beeEfficiencyLevel
            );

            // The purchased and minted Honey is rewarded to the Standard strategy participants
            standardStrategyRewardHoney(honeyBuybackAmount + mintedHoney);

            // The remaining 6% is transferred to the devs
            (bool transferSuccess, ) = payable(DevTeam).call{
                value: bnbReward - tokenPairLpShare - honeyBuybackShare
            }("");
            require(transferSuccess, "Dev transfer failed");
        } else {
            // If Honey price is high, 24% is converted into Honey-BNB LP
            uint256 honeyBnbLpShare = (bnbReward * 24) / 100;
            (uint256 honeyBnbLpAmount, , ) = convertEthToTokenLP(
                honeyBnbLpShare,
                address(HoneyToken)
            );

            // That Honey-BNB LP is sent as reward to the Staking Pool
            StakingPool.rewardLP(honeyBnbLpAmount);

            // 30% of the equivalent amount of Honey (based on Honey-BNB price) is minted
            uint256 mintedHoney = mintTokens(
                (bnbReward * 30) / 100,
                beeEfficiencyLevel
            );

            // The minted Honey is rewarded to the Standard strategy participants
            standardStrategyRewardHoney(mintedHoney);

            // The remaining 6% of BNB is transferred to the devs
            (bool transferSuccess, ) = payable(DevTeam).call{
                value: bnbReward - tokenPairLpShare - honeyBnbLpShare
            }("");
            require(transferSuccess, "Dev transfer failed");
        }
    }

    /// @notice Stakes the rewards for the grizzly strategy
    /// @param bnbReward The pending bnb reward to be restaked
    function stakeGrizzlyRewards(uint256 bnbReward) internal {
        // Get the price of Honey relative to BNB
        uint256 beeEfficiencyLevel = getTokenEthPrice(address(HoneyToken));

        // If Honey price too low, use buyback strategy
        if (beeEfficiencyLevel > beeEfficiencyThreshold) {
            // 94% (70% + 24%) of the BNB is used to buy Honey from the DEX
            uint256 honeyBuybackShare = (bnbReward * (70 + 24)) / 100;
            uint256 honeyBuybackAmount = convertEthToToken(
                honeyBuybackShare,
                address(HoneyToken)
            );

            // 6% of the equivalent amount of Honey (based on Honey-BNB price) is minted
            uint256 mintedHoney = mintTokens(
                (bnbReward * 6) / 100,
                beeEfficiencyLevel
            );

            // The purchased and minted Honey is staked
            grizzlyStrategyStakeHoney(honeyBuybackAmount + mintedHoney);

            // The remaining 6% of BNB is transferred to the devs
            (bool transferSuccess, ) = payable(DevTeam).call{
                value: bnbReward - honeyBuybackShare
            }("");
            require(transferSuccess, "Dev transfer failed");
        } else {
            // If Honey price is high, 70% of the BNB is used to buy Honey from the DEX
            uint256 honeyBuybackShare = (bnbReward * 70) / 100;
            uint256 honeyBuybackAmount = convertEthToToken(
                honeyBuybackShare,
                address(HoneyToken)
            );

            // 24% of the BNB is converted into Honey-BNB LP
            uint256 honeyBnbLpShare = (bnbReward * 24) / 100;
            (uint256 honeyBnbLpAmount, , ) = convertEthToTokenLP(
                honeyBnbLpShare,
                address(HoneyToken)
            );
            // The Honey-BNB LP is provided as reward to the Staking Pool
            StakingPool.rewardLP(honeyBnbLpAmount);

            // 30% of the equivalent amount of Honey (based on Honey-BNB price) is minted
            uint256 mintedHoney = mintTokens(
                (bnbReward * 30) / 100,
                beeEfficiencyLevel
            );

            // The purchased and minted Honey is staked
            grizzlyStrategyStakeHoney(honeyBuybackAmount + mintedHoney);

            // The remaining 6% of BNB is transferred to the devs
            (bool transferSuccess, ) = payable(DevTeam).call{
                value: bnbReward - honeyBuybackShare - honeyBnbLpShare
            }("");
            require(transferSuccess, "Dev transfer failed");
        }
    }

    /// @notice Stakes the rewards for the stablecoin strategy
    /// @param bnbReward The pending bnb reward to be restaked
    function stakeStablecoinRewards(uint256 bnbReward) internal {
        // 97% of the BNB is converted into TokenA-TokenB LP tokens
        uint256 pairLpShare = (bnbReward * 97) / 100;
        (
            uint256 pairLpAmount,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        ) = convertEthToPairLP(pairLpShare, address(TokenA), address(TokenB));

        totalUnusedTokenA += unusedTokenA;
        totalUnusedTokenB += unusedTokenB;

        // The stablecoin strategy round mask is updated
        stablecoinStrategyUpdateRewards(pairLpAmount);

        // The TokenA-TokenB LP tokens are staked in the MasterChef
        StakingContract.deposit(PoolID, pairLpAmount);

        // The remaining 3% of BNB is transferred to the devs
        (bool transferSuccess, ) = payable(DevTeam).call{
            value: bnbReward - pairLpShare
        }("");
        require(transferSuccess, "Dev transfer failed");
    }

    /// @notice Mints tokens according to the bee efficiency level
    /// @param share The share that should be minted in honey
    /// @param beeEfficiencyLevel The bee efficiency level to be uset to convert bnb shares into honey amounts
    /// @return tokens The amount minted in honey tokens
    function mintTokens(uint256 share, uint256 beeEfficiencyLevel)
        internal
        returns (uint256 tokens)
    {
        tokens = (share * beeEfficiencyLevel) / (1 ether);

        HoneyToken.claimTokens(tokens);
    }

    /// @notice Updates the bee efficiency threshold
    /// @dev only updater role can perform this function
    /// @param _beeEfficiencyThreshold The threshold for the bee efficiency level
    function updateBeeEfficiencyLevel(uint256 _beeEfficiencyThreshold)
        external
        override
        emergency(false)
        onlyRole(UPDATER_ROLE)
    {
        beeEfficiencyThreshold = _beeEfficiencyThreshold;
    }

    /// @notice Used to recover funds sent to this contract by mistake
    function recoverFunds(uint256 amount)
        external
        override
        nonReentrant
        onlyRole(FUNDS_RECOVERY_ROLE)
    {
        require(amount <= address(this).balance, "Insufficient funds");
        (bool transferSuccess, ) = payable(msg.sender).call{value: amount}("");
        require(transferSuccess, "Transfer failed");
    }

    /// @notice Puts the contract into emergency state
    /// @dev Can only be executed by the Emergency role. After that deposit/withdraw/stakeRewards does not work anymore. Only funds can be withdrawn with the withdrawEmergency() function
    function setEmergencyState() external override onlyRole(EMERGENCY_ROLE) {
        isEmergency = true;
    }

    /// @notice Withdraws in emergency state
    /// @dev this function can only be executed in emergency state. There is no stake reward performed. Only deposited funds can be withdrawn
    /// @return The amount withdrawn in BNB
    function withdrawEmergency()
        external
        override
        nonReentrant
        emergency(true)
        returns (uint256)
    {
        uint256 currentDeposits = 0;
        if (userStrategy[msg.sender] == Strategy.STANDARD) {
            currentDeposits = getStandardStrategyBalance();
        } else if (userStrategy[msg.sender] == Strategy.GRIZZLY) {
            currentDeposits = getGrizzlyStrategyBalance();
        } else {
            currentDeposits = getStablecoinStrategyBalance();
        }

        uint256 amountWithdrawn = 0;
        if (currentDeposits > 0) {
            amountWithdrawn = _withdraw(currentDeposits);
            (bool transferSuccess, ) = payable(msg.sender).call{
                value: amountWithdrawn
            }("");
            require(transferSuccess, "Transfer failed");
        }
        return amountWithdrawn;
    }
}
