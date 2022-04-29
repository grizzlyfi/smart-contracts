//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import "./MockERC20.sol";

contract MockUniswapV2Pair is MockERC20 {
    address private token0Address;
    address private token1Address;
    uint112 private reserve0Amount;
    uint112 private reserve1Amount;
    uint256 private priceCumulative0Last;
    uint256 private priceCumulative1Last;
    uint224 constant Q112 = 2**112;
    uint32 private lastTimestamp;

    constructor(
        address _token0Address,
        address _token1Address,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialMintAmount
    ) MockERC20(tokenName, tokenSymbol, initialMintAmount) {
        token0Address = _token0Address;
        token1Address = _token1Address;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return "";
    }

    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        return "";
    }

    function nonces(address owner) external view returns (uint256) {
        return 1;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {}

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256) {
        return 1;
    }

    function factory() external view returns (address) {
        return 0x0000000000000000000000000000000000000000;
    }

    function token0() external view returns (address) {
        return token0Address;
    }

    function token1() external view returns (address) {
        return token1Address;
    }

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        )
    {
        return (reserve0Amount, reserve1Amount, lastTimestamp);
    }

    function setLastTimestamp(uint32 _timestamp) external {
        lastTimestamp = _timestamp;
    }

    function setReserves(
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _timestamp
    ) external {
        require(_timestamp >= lastTimestamp);

        uint32 _timeElapsed = _timestamp - lastTimestamp;

        if (reserve0Amount > 0 && reserve1Amount > 0) {
            priceCumulative0Last +=
                ((Q112 * reserve1Amount) / reserve0Amount) *
                _timeElapsed;
            priceCumulative1Last +=
                ((Q112 * reserve0Amount) / reserve1Amount) *
                _timeElapsed;
        }

        reserve0Amount = _reserve0;
        reserve1Amount = _reserve1;
        lastTimestamp = _timestamp;
    }

    function price0CumulativeLast() external view returns (uint256) {
        return priceCumulative0Last;
    }

    function price1CumulativeLast() external view returns (uint256) {
        return priceCumulative1Last;
    }

    function kLast() external view returns (uint256) {
        return 1;
    }

    function mint(address to) external returns (uint256 liquidity) {
        return 1;
    }

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return (1, 1);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external {}

    function skim(address to) external {}

    function sync() external {}
}
