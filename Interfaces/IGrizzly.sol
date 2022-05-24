//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IGrizzly {
    enum Strategy {
        STANDARD,
        GRIZZLY,
        STABLECOIN
    }

    function deposit(
        address referralGiver,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external payable returns (uint256);

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
    ) external returns (uint256);

    function withdraw(
        uint256 amount,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external returns (uint256);

    function withdrawAll(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external returns (uint256);

    function withdrawToToken(
        address token,
        uint256 amount,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external returns (uint256);

    function changeStrategy(
        Strategy toStrategy,
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    ) external;

    function stakeRewards(
        address[] memory fromToken,
        address[] memory toToken,
        uint256[] memory amountIn,
        uint256[] memory amountOut,
        uint256 slippage,
        uint256 deadline
    )
        external
        returns (
            uint256 totalBnb,
            uint256 standardBnb,
            uint256 grizzlyBnb,
            uint256 stablecoinBnb
        );

    function updateBeeEfficiencyLevel(uint256 _beeEfficiencyThreshold) external;

    function recoverFunds(uint256 amount) external;
}
