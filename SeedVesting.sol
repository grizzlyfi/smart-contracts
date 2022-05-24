//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Interfaces/IHoney.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract SeedVesting is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct InvestorData {
        uint256 totalAmount;
        uint256 claimed;
    }

    IHoney public HoneyToken;

    uint256 public startBlock;
    uint256 public endBlock;

    mapping(address => InvestorData) public investorData;

    event InvestorAmountSet(address indexed _investor, uint256 amount);
    event ClaimedTokens(address indexed _investor, uint256 amount);

    function initialize(
        address _admin,
        address _honeyTokenAddress,
        uint256 _startBlock,
        uint256 _endBlock
    )
        public
        initializer
    {
        require(
            _startBlock < _endBlock,
            "Start block must be lower than end block"
        );
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        HoneyToken = IHoney(_honeyTokenAddress);
        startBlock = _startBlock;
        endBlock = _endBlock;
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

    function getClaimableAmount() public view returns (uint256) {
        if (
            block.number < startBlock ||
            investorData[msg.sender].totalAmount == 0
        ) return 0;

        uint256 vestedAmount = endBlock < block.number
            ? investorData[msg.sender].totalAmount
            : ((investorData[msg.sender].totalAmount *
                (block.number - startBlock)) / (endBlock - startBlock));

        return
            investorData[msg.sender].claimed < vestedAmount
                ? vestedAmount - investorData[msg.sender].claimed
                : 0;
    }

    function claimTokens() public whenNotPaused {
        require(startBlock < block.number, "Vesting period not started yet");
        require(
            investorData[msg.sender].totalAmount > 0,
            "Caller has no vested tokens"
        );

        uint256 claimableAmount = getClaimableAmount();
        require(claimableAmount > 0, "Nothing to claim");

        investorData[msg.sender].claimed += claimableAmount;
        HoneyToken.claimTokensWithoutAdditionalTokens(claimableAmount);
        IERC20Upgradeable(address(HoneyToken)).safeTransfer(msg.sender, claimableAmount);
        emit ClaimedTokens(msg.sender, claimableAmount);
    }

    function setInvestorAmount(address investor, uint256 amount)
        public
        onlyRole(UPDATER_ROLE)
    {
        require(investor != address(0), "Investor cannot have null address");
        investorData[investor].totalAmount = amount;
        emit InvestorAmountSet(investor, amount);
    }

    function setInvestorAmountBulk(
        address[] memory investors,
        uint256[] memory amounts
    ) public onlyRole(UPDATER_ROLE) {
        require(
            investors.length == amounts.length,
            "Array lengths do not match"
        );

        for (uint256 i = 0; i < investors.length; i++) {
            require(
                investors[i] != address(0),
                "Investor cannot have null address"
            );
            investorData[investors[i]].totalAmount = amounts[i];
            emit InvestorAmountSet(investors[i], amounts[i]);
        }
    }

    function setStartBlock(uint256 _startBlock) public onlyRole(UPDATER_ROLE) {
        require(
            _startBlock < endBlock,
            "Start block must be lower than end block"
        );
        startBlock = _startBlock;
    }

    function setEndBlock(uint256 _endBlock) public onlyRole(UPDATER_ROLE) {
        require(
            startBlock < _endBlock,
            "Start block must be lower than end block"
        );
        endBlock = _endBlock;
    }

    uint256[50] private __gap;
}
