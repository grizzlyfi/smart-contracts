//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapV2Router01 {
    mapping(address => mapping(address => uint256)) public userTokenAmounts;
    mapping(address => mapping(address => mapping(address => uint256)))
        public userLPAmounts;
    mapping(address => uint256) public tokenEthPrices;
    uint256 public tokenOffset = 0;
    uint256 public ethOffset = 0;
    address public factory;

    constructor() {}

    function setFactory(address _factory) external {
        factory = _factory;
    }

    function WETH() public pure returns (address) {
        return 0x0000000000000000000000000000000000000000;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(amountADesired <= userTokenAmounts[msg.sender][tokenA]);
        require(amountBDesired <= userTokenAmounts[msg.sender][tokenB]);
        userTokenAmounts[msg.sender][tokenA] =
            userTokenAmounts[msg.sender][tokenA] -
            amountADesired;
        userTokenAmounts[msg.sender][tokenB] =
            userTokenAmounts[msg.sender][tokenB] -
            amountBDesired;
        userLPAmounts[to][tokenA][tokenB] =
            userLPAmounts[to][tokenA][tokenB] +
            amountADesired +
            amountBDesired;
        return (
            (99950 * amountADesired) / 100000,
            (99950 * amountBDesired) / 100000,
            amountADesired + amountBDesired
        );
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        require(amountTokenDesired <= userTokenAmounts[msg.sender][token]);
        userTokenAmounts[msg.sender][token] =
            userTokenAmounts[msg.sender][token] -
            amountTokenDesired;

        userLPAmounts[to][token][WETH()] =
            userLPAmounts[to][token][WETH()] +
            amountTokenDesired +
            msg.value;

        if (ethOffset > 0) payable(msg.sender).transfer(ethOffset);

        return (
            amountTokenDesired - tokenOffset,
            msg.value - ethOffset,
            amountTokenDesired + msg.value
        );
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity <= userLPAmounts[msg.sender][tokenA][tokenB]);
        userLPAmounts[msg.sender][tokenA][tokenB] =
            userLPAmounts[msg.sender][tokenA][tokenB] -
            liquidity;

        userTokenAmounts[to][tokenA] =
            userTokenAmounts[to][tokenA] +
            liquidity /
            2;
        userTokenAmounts[to][tokenB] =
            userTokenAmounts[to][tokenB] +
            liquidity /
            2;
        return (liquidity / 2, liquidity / 2);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH) {
        require(liquidity <= userLPAmounts[to][token][WETH()]);
        userLPAmounts[to][token][WETH()] =
            userLPAmounts[to][token][WETH()] -
            liquidity;

        userTokenAmounts[to][token] =
            userTokenAmounts[to][token] +
            liquidity /
            2;
        payable(to).transfer(liquidity / 2);
        return (liquidity / 2, liquidity / 2);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        return (amountAMin, amountBMin);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {
        return (amountTokenMin, amountETHMin);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = amountIn;
        _amounts[1] = amountOutMin;
        return _amounts;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1;
        _amounts[1] = 1;
        return _amounts;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);

        userTokenAmounts[to][path[1]] =
            userTokenAmounts[to][path[1]] +
            msg.value;
        _amounts[0] = msg.value;
        _amounts[1] = msg.value;

        IERC20 token = IERC20(path[1]);
        if (token.balanceOf(address(this)) >= msg.value) {
            token.transfer(to, msg.value);
        }

        return _amounts;
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1;
        _amounts[1] = 1;
        return _amounts;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(amountIn <= userTokenAmounts[msg.sender][path[0]]);

        userTokenAmounts[msg.sender][path[0]] =
            userTokenAmounts[msg.sender][path[0]] -
            amountIn;

        payable(to).transfer(amountIn);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = amountIn;
        _amounts[1] = amountIn;
        return _amounts;
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1;
        _amounts[1] = 1;
        return _amounts;
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB) {
        return reserveB;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        return amountOut;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn) {
        return amountIn;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = amountIn;
        _amounts[1] = tokenEthPrices[path[1]];
        if (path.length == 3) {
            _amounts[2] = tokenEthPrices[path[2]];
        }
        return _amounts;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1;
        _amounts[1] = 1;
        return _amounts;
    }

    function setTokenEthPrice(address token, uint256 price) external {
        tokenEthPrices[token] = price;
    }

    function transferToken(
        address from,
        address to,
        address token,
        uint256 amount
    ) external {
        userTokenAmounts[from][token] -= amount;
        userTokenAmounts[to][token] += amount;
    }

    function transferLP(
        address from,
        address to,
        address tokenA,
        address tokenB,
        uint256 amount
    ) external {
        userLPAmounts[from][tokenA][tokenB] -= amount;
        userLPAmounts[to][tokenA][tokenB] += amount;
    }

    function setTokenAmount(address token, address to) external payable {
        userTokenAmounts[to][token] = userTokenAmounts[to][token] + msg.value;
    }

    function setTokenEthLpAmount(address token, address to) external payable {
        userLPAmounts[to][token][WETH()] =
            userLPAmounts[to][token][WETH()] +
            msg.value;
    }

    function setAddLiquidityOffset(uint256 _tokenOffset, uint256 _ethOffset)
        external
    {
        tokenOffset = _tokenOffset;
        ethOffset = _ethOffset;
    }
}
