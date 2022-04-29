//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./IUniswapV2Router01.sol";

interface IDEX {
    function SwapRouter() external returns (IUniswapV2Router01);

    function convertEthToPairLP(address lpAddress)
        external
        payable
        returns (
            uint256 lpAmount,
            uint256 unusedTokenA,
            uint256 unusedTokenB
        );

    function convertEthToTokenLP(address token)
        external
        payable
        returns (
            uint256 lpAmount,
            uint256 unusedEth,
            uint256 unusedToken
        );

    function convertPairLpToEth(address lpAddress, uint256 amount)
        external
        returns (uint256 ethAmount);

    function convertTokenLpToEth(address token, uint256 amount)
        external
        returns (uint256 ethAmount);

    function convertEthToToken(address token)
        external
        payable
        returns (uint256 tokenAmount);

    function convertTokenToEth(uint256 amount, address token)
        external
        returns (uint256 ethAmount);

    function getTokenEthPrice(address token) external view returns (uint256);

    function totalPendingReward(uint256 poolID) external view returns (uint256);

    function totalStakedAmount(uint256 poolID) external view returns (uint256);

    function checkSlippage(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage
    ) external view;

    function recoverFunds() external;
}
