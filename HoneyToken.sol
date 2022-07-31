//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./Interfaces/IHoney.sol";

/// @title Honey token ERC20 contract
/// @notice The honey token is the token for grizzlyfi. It implements the ERC20 fungible token standard. In addition it allows defined contracts to mint freshly new tokens.
/// The token supports openzeppelin governance as an erc20 token with voting power. It will be used by a Governor in the future to determine the participants voting powers.
/// @dev AccessControl from openzeppelin implementation is used to handle the minter roles.
/// User with DEFAULT_ADMIN_ROLE can grant MINTER_ROLE to any address.
/// The DEFAULT_ADMIN_ROLE is intended to be a 2 out of 3 multisig wallet in the beginning and then be moved to governance in the future.
contract HoneyToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IHoney
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => uint256) public override totalClaimed;

    address public developmentFounders;
    address public advisors;
    address public marketingReservesPool;
    address public devTeam;

    uint256 private additionalTokenCounter;

    event AdditionalMinterAddressChange(
        address indexed _newAddress,
        string indexed _type
    );

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialMintAmount,
        address admin,
        address _developmentFounders,
        address _advisors,
        address _marketingReservesPool,
        address _devTeam
    ) public initializer {
        require(admin != address(0), "Admin address cannot be null");
        require(
            _developmentFounders != address(0),
            "Founders address cannot be null"
        );
        require(_advisors != address(0), "Advisors address cannot be null");
        require(
            _marketingReservesPool != address(0),
            "Marketing address cannot be null"
        );
        require(_devTeam != address(0), "Dev team address cannot be null");

        __ERC20_init(tokenName, tokenSymbol);
        __ERC20Permit_init(tokenName);
        __Pausable_init();

        _mint(admin, initialMintAmount);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        developmentFounders = _developmentFounders;
        advisors = _advisors;
        marketingReservesPool = _marketingReservesPool;
        devTeam = _devTeam;
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

    /// @notice Override for openzeppelin Governance
    /// @dev refer to https://docs.openzeppelin.com/contracts/4.x/governance
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) whenNotPaused {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @notice Override for openzeppelin Governance
    /// @dev refer to https://docs.openzeppelin.com/contracts/4.x/governance
    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    /// @notice Override for openzeppelin Governance
    /// @dev refer to https://docs.openzeppelin.com/contracts/4.x/governance
    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }

    /// @notice transfer can get paused
    function transfer(address to, uint256 amount)
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    /// @notice transferFrom can get paused
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    /// @notice Token mining function for addresses with MINTER_ROLE.
    /// If called by an active recipient, the requested amount of tokens will
    /// be minted and transferred to the recipients address.
    /// additionally 22 tokens per 100 tokens will be minted for third party
    /// @param amount The amount to be minted
    function claimTokens(uint256 amount)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        _mint(msg.sender, amount);
        totalClaimed[msg.sender] += amount;
        additionalTokenCounter += amount;
        claimAdditionalTokens();
    }

    /// @notice Token mining function for addresses with MINTER_ROLE.
    /// If called by an active recipient, the requested amount of tokens will
    /// be minted and transferred to the recipients address.
    /// no additional tokens to be minted here
    /// @param amount The amount to be minted
    function claimTokensWithoutAdditionalTokens(uint256 amount)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        _mint(msg.sender, amount);
        totalClaimed[msg.sender] += amount;
    }

    /// @notice The additional token claiming
    /// For every 100 tokens, 22 tokens will be minted and distributed among third party
    /// 5 go to the development founders
    /// 3 go to the advisors
    /// 2 go to the marketing and reserves pool
    /// 12 go to the dev team
    function claimAdditionalTokens() internal whenNotPaused {
        // the multiplier is cut off each 100 tokens
        uint256 multiplier = additionalTokenCounter / (100 * (10**decimals()));
        if (multiplier > 0) {
            // additional minting for development founders
            uint256 developmentFoundersAmount = multiplier *
                53 *
                (10**(decimals() - 1));
            _mint(developmentFounders, developmentFoundersAmount);
            totalClaimed[developmentFounders] += developmentFoundersAmount;

            // additional minting for advisors
            uint256 advisorsAmount = multiplier * 37 * (10**(decimals() - 1));
            _mint(advisors, advisorsAmount);
            totalClaimed[advisors] += advisorsAmount;

            // additional minting for marketing reserves pool
            uint256 marketingReservesPoolAmount = multiplier *
                60 *
                (10**(decimals() - 1));
            _mint(marketingReservesPool, marketingReservesPoolAmount);
            totalClaimed[marketingReservesPool] += marketingReservesPoolAmount;

            // additional minting for dev team
            uint256 devTeamAmount = multiplier * 70 * (10**(decimals() - 1));
            _mint(devTeam, devTeamAmount);
            totalClaimed[devTeam] += devTeamAmount;

            // upadate additionalTokenCounter
            additionalTokenCounter -= multiplier * 100 * (10**decimals());
        }
    }

    /// @notice Sets the development founders address
    /// @dev Only possible for updater role
    /// @param _developmentFounders The new development founders address
    function setDevelopmentFounders(address _developmentFounders)
        external
        override
        onlyRole(UPDATER_ROLE)
    {
        require(
            _developmentFounders != address(0),
            "Address must not be zero address"
        );
        developmentFounders = _developmentFounders;
        emit AdditionalMinterAddressChange(
            _developmentFounders,
            "Development Founders"
        );
    }

    /// @notice Sets the advisors address
    /// @dev Only possible for updater role
    /// @param _advisors The new advisors address
    function setAdvisors(address _advisors)
        external
        override
        onlyRole(UPDATER_ROLE)
    {
        require(_advisors != address(0), "Address must not be zero address");
        advisors = _advisors;
        emit AdditionalMinterAddressChange(_advisors, "Advisors");
    }

    /// @notice Sets the marketing reserves pool address
    /// @dev Only possible for updater role
    /// @param _marketingReservesPool The new marketing reserves pool address
    function setMarketingReservesPool(address _marketingReservesPool)
        external
        override
        onlyRole(UPDATER_ROLE)
    {
        require(
            _marketingReservesPool != address(0),
            "Address must not be zero address"
        );
        marketingReservesPool = _marketingReservesPool;
        emit AdditionalMinterAddressChange(
            _marketingReservesPool,
            "Marketing and Reserves"
        );
    }

    /// @notice Sets the dev team address
    /// @dev Only possible for updater role
    /// @param _devTeam The new dev team address
    function setDevTeam(address _devTeam)
        external
        override
        onlyRole(UPDATER_ROLE)
    {
        require(_devTeam != address(0), "Address must not be zero address");
        devTeam = _devTeam;
        emit AdditionalMinterAddressChange(_devTeam, "Dev Team");
    }

    uint256[50] private __gap;
}
