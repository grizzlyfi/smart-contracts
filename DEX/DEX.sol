//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../Config/BaseConfig.sol";
import "../Interfaces/IMasterChef.sol";
import "../Interfaces/IUniswapV2Router01.sol";
import "../Interfaces/IUniswapV2Pair.sol";

/// @title DEX proxy
/// @notice The DEX proxy is responsible to convert the different tokens and the native coin. It uses the pancakeswap swap router to exchange these tokens
/// @dev All swaps are done on behalf of this contract. This means all tokens are owned by this contract and are then divided for the different investors in the strategy contracts
abstract contract DEX is BaseConfig {
    receive() external payable {}

    /// @notice Converts bnbs to the two tokens for liquidity providing. Then provides these tokens to the liquidity pool and receives lp tokens
    /// @dev No slippage implemented at this time
    /// @param amount The amount in bnbs to be converted
    /// @param tokenA The address of the first token for liq. providing
    /// @param tokenB The address of the second token for liq. providing
    /// @return lpAmount The recieved lp tokens for the liq. providing
    /// @return unusedTokenA The amount of token A that could not be provided as liquidity
    /// @return unusedTokenB The amount of token B that could not be provided as liquidity
    function convertEthToPairLP(
        uint256 amount,
        address tokenA,
        address tokenB
    )
        internal
        returns (
            uint256 lpAmount,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        )
    {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = tokenA;
        uint256 tokenAValue = SwapRouter.swapExactETHForTokens{
            value: amount / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        pairs[1] = tokenB;
        uint256 tokenBValue = SwapRouter.swapExactETHForTokens{
            value: amount / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        (uint256 usedTokenA, uint256 usedTokenB, uint256 lpValue) = SwapRouter
            .addLiquidity(
                tokenA,
                tokenB,
                tokenAValue,
                tokenBValue,
                1,
                1,
                address(this),
                block.timestamp + 1
            );

        lpAmount = lpValue;
        unusedTokenA = tokenAValue - usedTokenA;
        unusedTokenB = tokenBValue - usedTokenB;
    }

    /// @notice Converts half of the bnbs to the one other token for liquidity providing in a bnb-token liquidity pool. Then provides bnb and the token to the liquidity pool and receives lp tokens
    /// @dev No slippage implemented at this time
    /// @param amount The amount in bnbs to be added for liq. providing
    /// @param token The address of the token for liq. providing
    /// @return lpAmount The recieved lp tokens for the bnb-token liq. providing
    /// @return unusedEth The amount bnbs that could not be provided as liquidity
    /// @return unusedToken The amount of the token that could not be provided as liquidity
    function convertEthToTokenLP(uint256 amount, address token)
        internal
        returns (
            uint256 lpAmount,
            uint256 unusedEth,
            uint256 unusedToken
        )
    {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = token;
        uint256 tokenValue = SwapRouter.swapExactETHForTokens{
            value: amount / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        (uint256 usedToken, uint256 usedEth, uint256 lpValue) = SwapRouter
            .addLiquidityETH{value: amount / 2}(
            token,
            tokenValue,
            1,
            1,
            address(this),
            block.timestamp + 1
        );

        lpAmount = lpValue;
        unusedToken = tokenValue - usedToken;
        unusedEth = amount / 2 - usedEth;
    }

    /// @notice Converts lp tokens back to bnbs. First removes liquidity using the lp tokens and then swaps the tokens to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount in lp tokens to be converted into bnbs
    /// @param tokenA The address of the token A that is provided as liquidity
    /// @param tokenB The address of the token B that is provided as liquidity
    /// @return ethAmount The total amount of bnbs that were received from the swaps
    function convertPairLpToEth(
        address tokenA,
        address tokenB,
        uint256 amount
    ) internal returns (uint256 ethAmount) {
        (uint256 tokenABalance, uint256 tokenBBalance) = SwapRouter
            .removeLiquidity(
                tokenA,
                tokenB,
                amount,
                1,
                1,
                address(this),
                block.timestamp + 1
            );

        address[] memory pairs = new address[](2);
        pairs[1] = SwapRouter.WETH();

        pairs[0] = tokenA;
        uint256 tokenAEth = SwapRouter.swapExactTokensForETH(
            tokenABalance,
            1,
            pairs,
            payable(address(this)),
            block.timestamp + 1
        )[1];

        // Convert Token B into ETH
        pairs[0] = tokenB;
        uint256 tokenBEth = SwapRouter.swapExactTokensForETH(
            tokenBBalance,
            1,
            pairs,
            payable(address(this)),
            block.timestamp + 1
        )[1];

        return tokenAEth + tokenBEth;
    }

    /// @notice Converts bnbs to a specific token
    /// @dev No slippage implemented at this time
    /// @param amount The amount of bnbs to be converted
    /// @param token The token address to which bnbs should be converted
    /// @return tokenAmount The amount of tokens received
    function convertEthToToken(uint256 amount, address token)
        internal
        returns (uint256 tokenAmount)
    {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = token;
        tokenAmount = SwapRouter.swapExactETHForTokens{value: amount}(
            1,
            pairs,
            address(this),
            block.timestamp + 1
        )[1];
    }

    /// @notice Converts a specific token to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount of tokens to be converted
    /// @param token The token address which should be converted to bnbs
    /// @return ethAmount The amount of bnbs received
    function convertTokenToEth(uint256 amount, address token)
        internal
        returns (uint256 ethAmount)
    {
        address[] memory pairs = new address[](2);
        pairs[0] = token;
        pairs[1] = SwapRouter.WETH();

        IERC20 tokenInstance = IERC20(token);
        uint256 allowance = tokenInstance.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowance < amount) {
            require(
                tokenInstance.approve(address(SwapRouter), 2**256 - 1),
                "Failed to approve SwapRouter"
            );
        }

        ethAmount = SwapRouter.swapExactTokensForETH(
            amount,
            1,
            pairs,
            address(this),
            block.timestamp + 1
        )[1];
    }

    /// @notice Tells how many tokens can be bought with one bnb
    /// @param token The address of the token to get the price
    /// @return price The amount of tokens that can be bought with one bnb
    function getTokenEthPrice(address token) internal view returns (uint256) {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();
        pairs[1] = token;

        return SwapRouter.getAmountsOut(1e18, pairs)[1];
    }

    /// @notice Gets the total pending reward from pancakeswap master chef
    /// @return pendingReward The total pending reward for the lp staking
    function totalPendingReward() external view returns (uint256) {
        uint256 pendingRewardToken = StakingContract.pendingCake(
            PoolID,
            address(this)
        );

        if (pendingRewardToken == 0) return 0;

        address[] memory pairs = new address[](3);
        pairs[0] = address(RewardToken);
        pairs[1] = SwapRouter.WETH();

        pairs[2] = address(TokenA);
        uint256 tokenAValue = SwapRouter.getAmountsOut(
            pendingRewardToken / 2,
            pairs
        )[2];

        pairs[2] = address(TokenB);
        uint256 tokenBValue = SwapRouter.getAmountsOut(
            pendingRewardToken / 2,
            pairs
        )[2];

        (uint256 reserveA, uint256 reserveB, ) = LPToken.getReserves();

        if (reserveA == 0 || reserveB == 0) return 0;

        uint256 lpValueA = (tokenAValue * LPToken.totalSupply()) / reserveA;
        uint256 lpValueB = (tokenBValue * LPToken.totalSupply()) / reserveB;

        return lpValueA < lpValueB ? lpValueA : lpValueB;
    }

    /// @notice Gets the total staked amount from pancakeswap master chef
    /// @return amount The currently total staked amount in lp tokens
    function totalStakedAmount() external view returns (uint256) {
        (uint256 amount, ) = StakingContract.userInfo(PoolID, address(this));
        return amount;
    }

    /// @notice Checks if the current price is within the slippage tolerance compared to the quoted price
    /// @dev Item order in the lists is critical. All lists must have the same length, otherwise the call revers. Reverts if splippage tolerance is not met
    /// @param fromToken The list of token addresses from which the conversion is done
    /// @param toToken The list of token addresses to which the conversion is done
    /// @param amountIn The list of quoted input amounts
    /// @param amountOut The list of output amounts for each quoted input amount
    /// @param slippage The allowed slippage
    function checkSlippage(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage
    ) public view {
        require(
            fromToken.length == toToken.length &&
                fromToken.length == amountIn.length &&
                fromToken.length == amountOut.length,
            "Invalid slippage parameters"
        );
        require(slippage <= MAX_PERCENTAGE, "Max slippage is MAX_PERCENTAGE");

        address[] memory pairs = new address[](2);

        for (uint256 i = 0; i < fromToken.length; i++) {
            pairs[0] = fromToken[i];
            pairs[1] = toToken[i];
            uint256 currentAmoutOut = SwapRouter.getAmountsOut(
                amountIn[i],
                pairs
            )[1];
            require(
                ((MAX_PERCENTAGE - slippage) * amountOut[i]) / MAX_PERCENTAGE <
                    currentAmoutOut,
                "Price slippage too high"
            );
        }
    }
}
