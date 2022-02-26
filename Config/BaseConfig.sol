//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Interfaces/IMasterChef.sol";
import "../Interfaces/IUniswapV2Router01.sol";
import "../Interfaces/IUniswapV2Pair.sol";
import "../Interfaces/IStakingPool.sol";
import "../Interfaces/IHoney.sol";
import "../Interfaces/IReferral.sol";

/// @title Base config for grizzly contract
/// @notice This contract contains all external addresses and dependencies for the grizzly contract. It also approves dependent contracts to spend tokens on behalf of grizzly.sol
/// @dev The contract grizzly.sol inherits this contract to have all dependencies available. This contract is always inherited and never deployed alone
abstract contract BaseConfig is AccessControl {
    using SafeERC20 for IERC20;
    // the role that allows updating parameters
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 public constant MAX_PERCENTAGE = 100000;
    uint256 public constant DECIMAL_OFFSET = 10e12;

    IUniswapV2Router01 public SwapRouter;
    IUniswapV2Pair public LPToken;
    IMasterChef public StakingContract;
    IStakingPool public StakingPool;
    IHoney public HoneyToken;
    IERC20 public HoneyBnbLpToken;
    IERC20 public RewardToken;
    IERC20 public TokenA;
    IERC20 public TokenB;
    IReferral public Referral;
    uint256 public PoolID;
    address public DevTeam;

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
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _Admin);

        SwapRouter = IUniswapV2Router01(_SwapRouterAddress);
        StakingContract = IMasterChef(_StakingContractAddress);
        StakingPool = IStakingPool(_StakingPoolAddress);
        HoneyToken = IHoney(_HoneyTokenAddress);
        HoneyBnbLpToken = IERC20(_HoneyBnbLpTokenAddress);
        Referral = IReferral(_ReferralAddress);

        DevTeam = _DevTeamAddress;
        PoolID = _PoolID;

        (address lpToken, , , ) = StakingContract.poolInfo(PoolID);

        LPToken = IUniswapV2Pair(lpToken);

        TokenA = IERC20(LPToken.token0());

        TokenB = IERC20(LPToken.token1());

        RewardToken = IERC20(StakingContract.cake());

        TokenA.safeApprove(address(SwapRouter), type(uint256).max);
        TokenB.safeApprove(address(SwapRouter), type(uint256).max);
        RewardToken.safeApprove(address(SwapRouter), type(uint256).max);

        IERC20(address(LPToken)).safeApprove(
            address(SwapRouter),
            type(uint256).max
        );
        IERC20(address(LPToken)).safeApprove(
            address(StakingContract),
            type(uint256).max
        );

        IERC20(address(HoneyToken)).safeApprove(
            address(StakingPool),
            type(uint256).max
        );
        IERC20(address(HoneyToken)).safeApprove(
            address(SwapRouter),
            type(uint256).max
        );
        IERC20(address(HoneyToken)).safeApprove(
            address(Referral),
            type(uint256).max
        );
        IERC20(address(HoneyBnbLpToken)).safeApprove(
            address(StakingPool),
            type(uint256).max
        );
    }
}
