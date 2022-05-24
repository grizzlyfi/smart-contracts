//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title Share distribution
/// @notice This contract enables the distribution of honey tokens sent to it based on the amount of shares of its participants
/// @dev The share of honey rewards is done with roundmasks according to EIP-1973
contract ShareDistrubution is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    struct ParticipantData {
        uint256 shares;
        uint256 rewardMask;
        uint256 unclaimedRewards;
    }

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 private constant DECIMAL_OFFSET = 10e12;

    IERC20 public Token;

    uint256 public totalShares;
    uint256 public roundMask;
    uint256 public reservedTokens;

    mapping(address => ParticipantData) public participantData;

    event Claim(address indexed participant, uint256 amount);

    function initialize(address admin, address tokenAddress)
        public
        initializer
    {
        Token = IERC20(tokenAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        __Pausable_init();
    }

    /// @notice pause
    /// @dev pause the contract
    function pause() external whenNotPaused onlyRole(PAUSER_ROLE){
      _pause();
    }

    /// @notice unpause
    /// @dev unpause the contract
    function unpause() external whenPaused onlyRole(PAUSER_ROLE){
      _unpause();
    }

    /// @notice Claims the tokens made available to the caller
    /// @dev Reward mask are updated before claiming in order to use all available tokens. Reverts if nothing to claim
    function claimRewards() public whenNotPaused {
        updateRoundMask();

        uint256 claimedRewards = participantData[msg.sender].unclaimedRewards +
            ((roundMask - participantData[msg.sender].rewardMask) *
                participantData[msg.sender].shares) /
            DECIMAL_OFFSET;

        participantData[msg.sender].rewardMask = roundMask;
        participantData[msg.sender].unclaimedRewards = 0;

        require(claimedRewards > 0, "Nothing to claim");

        reservedTokens -= claimedRewards;
        Token.transfer(msg.sender, claimedRewards);
        emit Claim(msg.sender, claimedRewards);
    }

    /// @notice Returns the amount of tokens available for claiming by the caller
    /// @dev Reward mask will include the future updateRoundMask() call made at the time of claiming
    function pendingRewards() public view returns (uint256) {
        uint256 currentRoundMask = roundMask;

        if (totalShares > 0) {
            currentRoundMask +=
                (DECIMAL_OFFSET * availableRewards()) /
                totalShares;
        }

        return
            participantData[msg.sender].unclaimedRewards +
            ((currentRoundMask - participantData[msg.sender].rewardMask) *
                participantData[msg.sender].shares) /
            DECIMAL_OFFSET;
    }

    /// @notice Updates the round mask to include all tokens in the contract's balance
    /// @dev Reward mask will include the future updateRoundMask() call made at the time of claiming
    function updateRoundMask() internal {
        if (totalShares == 0) return;

        uint256 availableTokens = availableRewards();
        reservedTokens += availableTokens;
        roundMask += (DECIMAL_OFFSET * availableTokens) / totalShares;
    }

    /// @notice Returns the token balance of the contract
    function poolBalance() public view returns (uint256) {
        return Token.balanceOf(address(this));
    }

    /// @notice Returns the amount of tokens not included in the current round mask
    /// @dev Tokens included in the round mask are added to 'reservedTokens', which are then removed when claimed
    function availableRewards() public view returns (uint256) {
        uint256 tokenBalance = poolBalance();
        return
            tokenBalance <= reservedTokens ? 0 : tokenBalance - reservedTokens;
    }

    /// @notice Stakes the desired amount of honey into the staking pool
    /// @dev Lp reward masks are updated before the staking to have a clean state
    /// @param participant The address of the participant
    /// @param shares The amount of shares owned by the participant
    function setParticipantShares(address participant, uint256 shares)
        public
        onlyRole(UPDATER_ROLE)
    {
        updateRoundMask();

        // Compute the rewards with the current shares amount
        participantData[participant].unclaimedRewards +=
            ((roundMask - participantData[participant].rewardMask) *
                participantData[participant].shares) /
            DECIMAL_OFFSET;

        participantData[participant].rewardMask = roundMask;

        // Update new total shares based on the old and new shares amount
        totalShares =
            totalShares +
            shares -
            participantData[participant].shares;

        participantData[participant].shares = shares;
    }

    uint256[50] private __gap;
}
