//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IMasterChef.sol";
import "./Interfaces/IUniswapV2Router01.sol";
import "./Interfaces/IUniswapV2Pair.sol";
import "./Interfaces/IUniswapV2Factory.sol";
import "./Interfaces/IDEX.sol";
import "./Interfaces/IMasterChef.sol";
import "./Interfaces/IHoney.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title DEX proxy
/// @notice The DEX proxy is responsible to convert the different tokens and the native coin. It uses the pancakeswap swap router to exchange these tokens
/// @dev All swaps are done on behalf of this contract. This means all tokens are owned by this contract and are then divided for the different investors in the strategy contracts
contract DEX is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    IDEX,
    PausableUpgradeable
{
    // is necessary to receive unused bnb from the swaprouter
    receive() external payable {}

    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private constant MAX_PERCENTAGE = 100000;

    IUniswapV2Router01 public override SwapRouter;
    IMasterChef public StakingContract;

    mapping(address => address[]) public pathFromTokenToEth;
    mapping(address => address[]) public pathFromEthToToken;

    function initialize(
        address _SwapRouterAddress,
        address _StakingContractAddress,
        address _Admin
    ) public initializer {
        SwapRouter = IUniswapV2Router01(_SwapRouterAddress);
        StakingContract = IMasterChef(_StakingContractAddress);
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _Admin);
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
        whenNotPaused
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

        IERC20Upgradeable TokenA = IERC20Upgradeable(LPToken.token0());

        IERC20Upgradeable TokenB = IERC20Upgradeable(LPToken.token1());

        address[] memory _pathFromEthToTokenA = pathFromEthToToken[
            address(TokenA)
        ];
        address[] memory _pathFromEthToTokenB = pathFromEthToToken[
            address(TokenB)
        ];

        require(
            _pathFromEthToTokenA.length >= 2 &&
                _pathFromEthToTokenB.length >= 2,
            "TN"
        );

        uint256 tokenAValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, _pathFromEthToTokenA, address(this), block.timestamp + 1)[
            _pathFromEthToTokenA.length - 1
        ];

        uint256 tokenBValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, _pathFromEthToTokenB, address(this), block.timestamp + 1)[
            _pathFromEthToTokenB.length - 1
        ];

        uint256 allowanceA = TokenA.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceA < tokenAValue) {
            require(TokenA.approve(address(SwapRouter), tokenAValue), "FS");
        }

        uint256 allowanceB = TokenB.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceB < tokenBValue) {
            require(TokenB.approve(address(SwapRouter), tokenBValue), "FS");
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
        whenNotPaused
        returns (
            uint256 lpAmount,
            uint256 unusedEth,
            uint256 unusedToken
        )
    {
        IERC20Upgradeable Token = IERC20Upgradeable(token);

        address[] memory _pathFromEthToToken = pathFromEthToToken[
            address(Token)
        ];

        require(_pathFromEthToToken.length >= 2, "TN");

        uint256 tokenValue = SwapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(1, _pathFromEthToToken, address(this), block.timestamp + 1)[
            _pathFromEthToToken.length - 1
        ];

        uint256 allowance = Token.allowance(address(this), address(SwapRouter));
        if (allowance < tokenValue) {
            require(Token.approve(address(SwapRouter), tokenValue), "FS");
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
        require(transferSuccess, "TF");
    }

    /// @notice Converts lp tokens back to bnbs. First removes liquidity using the lp tokens and then swaps the tokens to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount in lp tokens to be converted into bnbs
    /// @param lpAddress The recieved lp tokens for the liq. providing
    /// @return ethAmount The total amount of bnbs that were received from the swaps
    function convertPairLpToEth(address lpAddress, uint256 amount)
        external
        override
        whenNotPaused
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

        IERC20Upgradeable(lpAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        IERC20Upgradeable TokenA = IERC20Upgradeable(LPToken.token0());

        IERC20Upgradeable TokenB = IERC20Upgradeable(LPToken.token1());

        address[] memory _pathFromTokenAToEth = pathFromTokenToEth[
            address(TokenA)
        ];
        address[] memory _pathFromTokenBToEth = pathFromTokenToEth[
            address(TokenB)
        ];

        require(
            _pathFromTokenAToEth.length >= 2 &&
                _pathFromTokenBToEth.length >= 2,
            "TN"
        );

        uint256 allowance = LPToken.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowance < amount) {
            require(LPToken.approve(address(SwapRouter), amount), "FS");
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

        uint256 allowanceA = TokenA.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceA < tokenABalance) {
            require(TokenA.approve(address(SwapRouter), tokenABalance), "FS");
        }

        uint256 tokenAEth = SwapRouter.swapExactTokensForETH(
            tokenABalance,
            1,
            _pathFromTokenAToEth,
            payable(msg.sender),
            block.timestamp + 1
        )[_pathFromTokenAToEth.length - 1];

        uint256 allowanceB = TokenB.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceB < tokenBBalance) {
            require(TokenB.approve(address(SwapRouter), tokenBBalance), "FS");
        }

        // Convert Token B into ETH
        uint256 tokenBEth = SwapRouter.swapExactTokensForETH(
            tokenBBalance,
            1,
            _pathFromTokenBToEth,
            payable(msg.sender),
            block.timestamp + 1
        )[_pathFromTokenBToEth.length - 1];

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
        whenNotPaused
        returns (uint256 ethAmount)
    {
        address lpToken = IUniswapV2Factory(SwapRouter.factory()).getPair(
            token,
            SwapRouter.WETH()
        );

        IUniswapV2Pair LPToken = IUniswapV2Pair(lpToken);

        IERC20Upgradeable(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        IERC20Upgradeable Token = IERC20Upgradeable(token);

        address[] memory _pathFromTokenToEth = pathFromTokenToEth[
            address(Token)
        ];

        require(_pathFromTokenToEth.length >= 2, "TN");

        uint256 allowanceLP = LPToken.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowanceLP < amount) {
            require(LPToken.approve(address(SwapRouter), amount), "FS");
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

        uint256 allowance = Token.allowance(address(this), address(SwapRouter));
        if (allowance < tokenBalance) {
            require(Token.approve(address(SwapRouter), tokenBalance), "FS");
        }

        uint256 tokenEth = SwapRouter.swapExactTokensForETH(
            tokenBalance,
            1,
            _pathFromTokenToEth,
            payable(msg.sender),
            block.timestamp + 1
        )[_pathFromTokenToEth.length - 1];

        (bool transferSuccess, ) = payable(msg.sender).call{value: ethBalance}(
            ""
        );
        require(transferSuccess, "TF");

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
        whenNotPaused
        returns (uint256 tokenAmount)
    {
        address[] memory _pathFromEthToToken = pathFromEthToToken[token];
        require(_pathFromEthToToken.length >= 2, "TN");
        tokenAmount = SwapRouter.swapExactETHForTokens{value: msg.value}(
            1,
            _pathFromEthToToken,
            msg.sender,
            block.timestamp + 1
        )[_pathFromEthToToken.length - 1];
    }

    /// @notice Converts a specific token to bnbs
    /// @dev No slippage implemented at this time
    /// @param amount The amount of tokens to be converted
    /// @param token The token address which should be converted to bnbs
    /// @return ethAmount The amount of bnbs received
    function convertTokenToEth(uint256 amount, address token)
        external
        override
        whenNotPaused
        returns (uint256 ethAmount)
    {
        address[] memory _pathFromTokenToEth = pathFromTokenToEth[token];
        require(_pathFromTokenToEth.length >= 2, "TN");

        IERC20Upgradeable tokenInstance = IERC20Upgradeable(token);
        tokenInstance.safeTransferFrom(msg.sender, address(this), amount);

        uint256 allowance = tokenInstance.allowance(
            address(this),
            address(SwapRouter)
        );
        if (allowance < amount) {
            require(tokenInstance.approve(address(SwapRouter), amount), "FS");
        }

        ethAmount = SwapRouter.swapExactTokensForETH(
            amount,
            1,
            _pathFromTokenToEth,
            payable(msg.sender),
            block.timestamp + 1
        )[_pathFromTokenToEth.length - 1];
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
        address[] memory _pathFromEthToToken = pathFromEthToToken[token];
        require(_pathFromEthToToken.length >= 2, "TN");

        return
            SwapRouter.getAmountsOut(1e18, _pathFromEthToToken)[
                _pathFromEthToToken.length
            ];
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

        IERC20Upgradeable TokenA = IERC20Upgradeable(LPToken.token0());

        IERC20Upgradeable TokenB = IERC20Upgradeable(LPToken.token1());

        require(
            pathFromEthToToken[address(TokenA)].length >= 2 &&
                pathFromEthToToken[address(TokenB)].length >= 2,
            "TN"
        );

        IERC20Upgradeable RewardToken = IERC20Upgradeable(
            StakingContract.cake()
        );

        uint256 pendingRewardToken = StakingContract.pendingCake(
            poolID,
            msg.sender
        );

        if (pendingRewardToken == 0) return 0;

        address[] memory pairsTokenA = new address[](
            pathFromEthToToken[address(TokenA)].length + 1
        );

        pairsTokenA[0] = address(RewardToken);

        for (
            uint256 i = 1;
            i <= pathFromEthToToken[address(TokenA)].length;
            i++
        ) {
            pairsTokenA[i] = pathFromEthToToken[address(TokenA)][i - 1];
        }

        uint256 tokenAValue = SwapRouter.getAmountsOut(
            pendingRewardToken / 2,
            pairsTokenA
        )[2];

        address[] memory pairsTokenB = new address[](
            pathFromEthToToken[address(TokenB)].length + 1
        );

        pairsTokenB[0] = address(RewardToken);

        for (
            uint256 i = 1;
            i <= pathFromEthToToken[address(TokenB)].length;
            i++
        ) {
            pairsTokenB[i] = pathFromEthToToken[address(TokenB)][i - 1];
        }

        uint256 tokenBValue = SwapRouter.getAmountsOut(
            pendingRewardToken / 2,
            pairsTokenB
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
            "IS"
        );
        require(slippage <= MAX_PERCENTAGE, "MP");

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
                "SH"
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
            require(transferSuccess, "TF");
        }
    }

    /// @notice Sets the swapping path for a token
    /// @dev Requires non zero address for token and a swap path to eth and from eth with length >= 2, only updater role can set these variables
    /// @param token The token address for which the path is set
    /// @param pathFromEth The swapping path when converting from eth to token
    /// @param pathToEth The swapping path when converting from token to eth
    function setSwapPathForToken(
        address token,
        address[] memory pathFromEth,
        address[] memory pathToEth
    ) public onlyRole(UPDATER_ROLE) {
        require(token != address(0), "TA");
        require(pathFromEth.length >= 2, "PI");
        require(pathToEth.length >= 2, "PI");
        require(pathFromEth[0] == SwapRouter.WETH(), "FW");
        require(pathFromEth[pathFromEth.length - 1] == token, "LT");
        require(pathToEth[0] == token, "FP");
        require(pathToEth[pathToEth.length - 1] == SwapRouter.WETH(), "LW");
        pathFromEthToToken[token] = pathFromEth;
        pathFromTokenToEth[token] = pathToEth;
    }

    /// @notice Sets the swapping path for a token with bulk
    /// @dev Take care of out of gas issues as there is a for loop over the input arrays, each index of the tokens array needs to be corresponding to the same index in the paths array
    /// @param tokens The token addresses for which the paths are set
    /// @param pathsFromEth The swapping paths from eth to token according to Uniswap paths
    /// @param pathsToEth The swapping paths from token to eth according to Uniswap paths
    function setSwapPathForTokenBulk(
        address[] memory tokens,
        address[][] memory pathsFromEth,
        address[][] memory pathsToEth
    ) external onlyRole(UPDATER_ROLE) {
        require(
            tokens.length == pathsFromEth.length &&
                tokens.length == pathsToEth.length,
            "AS"
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            setSwapPathForToken(tokens[i], pathsFromEth[i], pathsToEth[i]);
        }
    }

    uint256[50] private __gap;
}
