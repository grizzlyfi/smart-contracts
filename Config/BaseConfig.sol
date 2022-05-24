//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../Interfaces/IMasterChef.sol";
import "../Interfaces/IUniswapV2Router01.sol";
import "../Interfaces/IUniswapV2Pair.sol";
import "../Interfaces/IStakingPool.sol";
import "../Interfaces/IHoney.sol";
import "../Interfaces/IReferral.sol";
import "../Interfaces/IAveragePriceOracle.sol";
import "../Interfaces/IDEX.sol";

/// @title Base config for grizzly contract
/// @notice This contract contains all external addresses and dependencies for the grizzly contract. It also approves dependent contracts to spend tokens on behalf of grizzly.sol
/// @dev The contract grizzly.sol inherits this contract to have all dependencies available. This contract is always inherited and never deployed alone
abstract contract BaseConfig is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    // the role that allows updating parameters
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_PERCENTAGE = 100000;
    uint256 public constant DECIMAL_OFFSET = 10e12;

    IUniswapV2Pair public LPToken;
    IMasterChef public StakingContract;
    IStakingPool public StakingPool;
    IHoney public HoneyToken;
    IERC20Upgradeable public HoneyBnbLpToken;
    IERC20Upgradeable public RewardToken;
    IERC20Upgradeable public TokenA;
    IERC20Upgradeable public TokenB;
    IReferral public Referral;
    IAveragePriceOracle public AveragePriceOracle;
    IDEX public DEX;
    uint256 public PoolID;
    address public DevTeam;

    function __BaseConfig_init(
        address _Admin,
        address _StakingContractAddress,
        address _StakingPoolAddress,
        address _HoneyTokenAddress,
        address _HoneyBnbLpTokenAddress,
        address _DevTeamAddress,
        address _ReferralAddress,
        address _AveragePriceOracleAddress,
        address _DEXAddress,
        uint256 _PoolID
    ) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, _Admin);

        StakingContract = IMasterChef(_StakingContractAddress);
        StakingPool = IStakingPool(_StakingPoolAddress);
        HoneyToken = IHoney(_HoneyTokenAddress);
        HoneyBnbLpToken = IERC20Upgradeable(_HoneyBnbLpTokenAddress);
        Referral = IReferral(_ReferralAddress);
        AveragePriceOracle = IAveragePriceOracle(_AveragePriceOracleAddress);
        DEX = IDEX(_DEXAddress);

        DevTeam = _DevTeamAddress;
        PoolID = _PoolID;

        (address lpToken, , , ) = StakingContract.poolInfo(PoolID);

        LPToken = IUniswapV2Pair(lpToken);

        TokenA = IERC20Upgradeable(LPToken.token0());

        TokenB = IERC20Upgradeable(LPToken.token1());

        RewardToken = IERC20Upgradeable(StakingContract.cake());

        IERC20Upgradeable(address(LPToken)).safeApprove(
            address(StakingContract),
            type(uint256).max
        );

        IERC20Upgradeable(address(RewardToken)).safeApprove(
            address(DEX),
            type(uint256).max
        );

        IERC20Upgradeable(address(LPToken)).safeApprove(
            address(DEX),
            type(uint256).max
        );

        IERC20Upgradeable(address(HoneyToken)).safeApprove(
            address(StakingPool),
            type(uint256).max
        );
        IERC20Upgradeable(address(HoneyToken)).safeApprove(
            address(Referral),
            type(uint256).max
        );
        IERC20Upgradeable(address(HoneyBnbLpToken)).safeApprove(
            address(StakingPool),
            type(uint256).max
        );
    }

    function isNotPaused() internal {
        require(!paused(), "PS");
    }

    function isPaused() internal {
        require(paused(), "NP");
    }

    uint256[50] private __gap;
}
