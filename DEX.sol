//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IMasterChef.sol";
import "./Interfaces/IUniswapV2Router01.sol";
import "./Interfaces/IUniswapV2Pair.sol";
import "./Interfaces/IUniswapV2Factory.sol";
import "./Interfaces/IDEX.sol";
import "./Interfaces/IMasterChef.sol";
import "./Interfaces/IHoney.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title DEX proxy
/// @notice The DEX proxy is responsible to convert the different tokens and the native coin. It uses the pancakeswap swap router to exchange these tokens
/// @dev All swaps are done on behalf of this contract. This means all tokens are owned by this contract and are then divided for the different investors in the strategy contracts
contract DEX is IDEX, ReentrancyGuard, AccessControl {
    // is necessary to receive unused bnb from the swaprouter
    receive() external payable {}

    using SafeERC20 for IERC20;

    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");

    uint256 private constant MAX_PERCENTAGE = 100000;

    IUniswapV2Router01 public override SwapRouter;
    IMasterChef public StakingContract;

    constructor(
        address _SwapRouterAddress,
        address _StakingContractAddress,
        address _Admin
    ) {
        SwapRouter = IUniswapV2Router01(_SwapRouterAddress);
        StakingContract = IMasterChef(_StakingContractAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, _Admin);
    }

    /// @notice Converts bnbs to the two tokens for liquidity providing. Then provides these tokens to the liquidity pool and receives lp tokens
    /// @dev No slippage implemented at this time. BNB needs to be provided as value.
    /// @param lpAddress The address for the LP Token
    /// @return lpAmount The recieved lp tokens for the liq. providing
    /// @return unusedTokenA The amount of token A that could not be provided as liquidity
    /// @return unusedTokenB The amount of token B that could not be provided as liquidity
    function convertEthToPairLP(address lpAddress)
        external
        payable
        override
        returns (
            uint256 lpAmount,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        )
    {
        IUniswapV2Pair LPToken = IUniswapV2Pair(lpAddress);

        if (LPToken.token0() == SwapRouter.WETH()) {
            (lpAmount, unusedTokenA, unusedTokenB) = convertEthToTokenLP(
                LPToken.token1()
            );
            return (lpAmount, unusedTokenA, unusedTokenB);
        }
        if (LPToken.token1() == SwapRouter.WETH()) {
            (lpAmount, unusedTokenB, unusedTokenA) = convertEthToTokenLP(
                LPToken.token0()
            );
            return (lpAmount, unusedTokenA, unusedTokenB);
        }

        IERC20 TokenA = IERC20(LPToken.token0());

        IERC20 TokenB = IERC20(LPToken.token1());

        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = address(TokenA);
        uint256 tokenAValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        pairs[1] = address(TokenB);
        uint256 tokenBValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        uint256 allowanceA = TokenA.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceA < tokenAValue) {
            require(
                TokenA.approve(address(SwapRouter), tokenAValue),
                "Failed to approve SwapRouter"
            );
        }

        uint256 allowanceB = TokenB.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceB < tokenBValue) {
            require(
                TokenB.approve(address(SwapRouter), tokenBValue),
                "Failed to approve SwapRouter"
            );
        }

        (uint256 usedTokenA, uint256 usedTokenB, uint256 lpValue) = SwapRouter
            .addLiquidity(
                address(TokenA),
                address(TokenB),
                tokenAValue,
                tokenBValue,
                1,
                1,
                msg.sender,
                block.timestamp + 1
            );

        lpAmount = lpValue;
        unusedTokenA = tokenAValue - usedTokenA;
        unusedTokenB = tokenBValue - usedTokenB;

        // send back unused tokens
        TokenA.safeTransfer(msg.sender, unusedTokenA);
        TokenB.safeTransfer(msg.sender, unusedTokenB);
    }

    /// @notice Converts half of the bnbs to the one other token for liquidity providing in a bnb-token liquidity pool. Then provides bnb and the token to the liquidity pool and receives lp tokens
    /// @dev No slippage implemented at this time. BNB needs to be provided as value.
    /// @param token The address of the token for liq. providing
    /// @return lpAmount The recieved lp tokens for the bnb-token liq. providing
    /// @return unusedEth The amount bnbs that could not be provided as liquidity
    /// @return unusedToken The amount of the token that could not be provided as liquidity
    function convertEthToTokenLP(address token)
        public
        payable
        override
        returns (
            uint256 lpAmount,
            uint256 unusedEth,
            uint256 unusedToken
        )
    {
        IERC20 Token = IERC20(token);

        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = address(Token);

        uint256 tokenValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, pairs, address(this), block.timestamp + 1)[1];

        uint256 allowance = Token.allowance(address(this), address(SwapRouter));
        if (allowance < tokenValue) {
            require(
                Token.approve(address(SwapRouter), tokenValue),
                "Failed to approve SwapRouter"
            );
        }

        (uint256 usedToken, uint256 usedEth, uint256 lpValue) = SwapRouter
            .addLiquidityETH{value: msg.value / 2}(
            address(Token),
            tokenValue,
            1,
            1,
            msg.sender,
            block.timestamp + 1
        );

        lpAmount = lpValue;
        unusedToken = tokenValue - usedToken;
        unusedEth = msg.value / 2 - usedEth;

        // send back unused tokens / BNB
        Token.safeTransfer(msg.sender, unusedToken);
        (bool transferSuccess, ) = payable(msg.sender).call{value: unusedEth}(
            ""
        );
        require(transferSuccess, "Transfer failed");
    }

    /// @notice Converts lp tokens back to bnbs. First removes liquidity using the lp tokens and then swaps the tokens to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount in lp tokens to be converted into bnbs
    /// @param lpAddress The recieved lp tokens for the liq. providing
    /// @return ethAmount The total amount of bnbs that were received from the swaps
    function convertPairLpToEth(address lpAddress, uint256 amount)
        external
        override
        returns (uint256 ethAmount)
    {
        IUniswapV2Pair LPToken = IUniswapV2Pair(lpAddress);

        if (LPToken.token0() == SwapRouter.WETH()) {
            ethAmount = convertTokenLpToEth(LPToken.token1(), amount);
            return ethAmount;
        }
        if (LPToken.token1() == SwapRouter.WETH()) {
            ethAmount = convertTokenLpToEth(LPToken.token0(), amount);
            return ethAmount;
        }

        IERC20(lpAddress).safeTransferFrom(msg.sender, address(this), amount);

        IERC20 TokenA = IERC20(LPToken.token0());

        IERC20 TokenB = IERC20(LPToken.token1());

        uint256 allowance = LPToken.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowance < amount) {
            require(
                LPToken.approve(address(SwapRouter), amount),
                "Failed to approve SwapRouter"
            );
        }

        (uint256 tokenABalance, uint256 tokenBBalance) = SwapRouter
            .removeLiquidity(
                address(TokenA),
                address(TokenB),
                amount,
                1,
                1,
                address(this),
                block.timestamp + 1
            );

        address[] memory pairs = new address[](2);
        pairs[1] = SwapRouter.WETH();

        pairs[0] = address(TokenA);

        uint256 allowanceA = TokenA.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceA < tokenABalance) {
            require(
                TokenA.approve(address(SwapRouter), tokenABalance),
                "Failed to approve SwapRouter"
            );
        }

        uint256 tokenAEth = SwapRouter.swapExactTokensForETH(
            tokenABalance,
            1,
            pairs,
            payable(msg.sender),
            block.timestamp + 1
        )[1];

        uint256 allowanceB = TokenB.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceB < tokenBBalance) {
            require(
                TokenB.approve(address(SwapRouter), tokenBBalance),
                "Failed to approve SwapRouter"
            );
        }

        // Convert Token B into ETH
        pairs[0] = address(TokenB);
        uint256 tokenBEth = SwapRouter.swapExactTokensForETH(
            tokenBBalance,
            1,
            pairs,
            payable(msg.sender),
            block.timestamp + 1
        )[1];

        return tokenAEth + tokenBEth;
    }

    /// @notice Converts lp tokens back to bnbs for a BNB token liquidity pool. First removes liquidity using the lp tokens and then swaps the token to bnb and sends the swapped bnb plus the provided bnb
    /// @dev No slippage implemented at this time
    /// @param amount The amount in lp tokens to be converted into bnbs
    /// @param token The token that is one side of the bnb-token liquidity pool
    /// @return ethAmount The total amount of bnbs that were received from the swaps
    function convertTokenLpToEth(address token, uint256 amount)
        public
        override
        returns (uint256 ethAmount)
    {
        address lpToken = IUniswapV2Factory(SwapRouter.factory()).getPair(
            token,
            SwapRouter.WETH()
        );

        IUniswapV2Pair LPToken = IUniswapV2Pair(lpToken);

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20 Token = IERC20(token);

        uint256 allowanceLP = LPToken.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceLP < amount) {
            require(
                LPToken.approve(address(SwapRouter), amount),
                "Failed to approve SwapRouter"
            );
        }

        (uint256 tokenBalance, uint256 ethBalance) = SwapRouter
            .removeLiquidityETH(
                token,
                amount,
                1,
                1,
                address(this),
                block.timestamp + 1
            );

        address[] memory pairs = new address[](2);
        pairs[1] = SwapRouter.WETH();

        pairs[0] = address(Token);

        uint256 allowance = Token.allowance(address(this), address(SwapRouter));
        if (allowance < tokenBalance) {
            require(
                Token.approve(address(SwapRouter), tokenBalance),
                "Failed to approve SwapRouter"
            );
        }

        uint256 tokenEth = SwapRouter.swapExactTokensForETH(
            tokenBalance,
            1,
            pairs,
            payable(msg.sender),
            block.timestamp + 1
        )[1];

        (bool transferSuccess, ) = payable(msg.sender).call{value: ethBalance}(
            ""
        );
        require(transferSuccess, "Transfer failed");

        return tokenEth + ethBalance;
    }

    /// @notice Converts bnbs to a specific token
    /// @dev No slippage implemented at this time. BNB needs to be provided as value.
    /// @param token The token address to which bnbs should be converted
    /// @return tokenAmount The amount of tokens received
    function convertEthToToken(address token)
        external
        payable
        override
        returns (uint256 tokenAmount)
    {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();

        pairs[1] = token;
        tokenAmount = SwapRouter.swapExactETHForTokens{value: msg.value}(
            1,
            pairs,
            msg.sender,
            block.timestamp + 1
        )[1];
    }

    /// @notice Converts a specific token to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount of tokens to be converted
    /// @param token The token address which should be converted to bnbs
    /// @return ethAmount The amount of bnbs received
    function convertTokenToEth(uint256 amount, address token)
        external
        override
        returns (uint256 ethAmount)
    {
        IERC20 tokenInstance = IERC20(token);
        tokenInstance.safeTransferFrom(msg.sender, address(this), amount);

        address[] memory pairs = new address[](2);
        pairs[0] = token;
        pairs[1] = SwapRouter.WETH();

        uint256 allowance = tokenInstance.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowance < amount) {
            require(
                tokenInstance.approve(address(SwapRouter), amount),
                "Failed to approve SwapRouter"
            );
        }

        ethAmount = SwapRouter.swapExactTokensForETH(
            amount,
            1,
            pairs,
            payable(msg.sender),
            block.timestamp + 1
        )[1];
    }

    /// @notice Tells how many tokens can be bought with one bnb
    /// @param token The address of the token to get the price
    /// @return price The amount of tokens that can be bought with one bnb
    function getTokenEthPrice(address token)
        external
        view
        override
        returns (uint256)
    {
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();
        pairs[1] = token;

        return SwapRouter.getAmountsOut(1e18, pairs)[1];
    }

    /// @notice Gets the total pending reward from pancakeswap master chef
    /// @return pendingReward The total pending reward for the lp staking
    function totalPendingReward(uint256 poolID)
        external
        view
        override
        returns (uint256)
    {
        (address lpToken, , , ) = StakingContract.poolInfo(poolID);

        IUniswapV2Pair LPToken = IUniswapV2Pair(lpToken);

        IERC20 TokenA = IERC20(LPToken.token0());

        IERC20 TokenB = IERC20(LPToken.token1());

        IERC20 RewardToken = IERC20(StakingContract.cake());

        uint256 pendingRewardToken = StakingContract.pendingCake(
            poolID,
            msg.sender
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
    function totalStakedAmount(uint256 poolID)
        external
        view
        override
        returns (uint256)
    {
        (uint256 amount, ) = StakingContract.userInfo(poolID, msg.sender);
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
    ) external view override {
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

    /// @notice Used to recover remainder funds that are stuck
    function recoverFunds()
        external
        override
        nonReentrant
        onlyRole(FUNDS_RECOVERY_ROLE)
    {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool transferSuccess, ) = payable(msg.sender).call{value: balance}(
                ""
            );
            require(transferSuccess, "Transfer failed");
        }
    }
}
