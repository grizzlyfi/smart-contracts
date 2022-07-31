//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./Interfaces/IHoney.sol";
import "./Interfaces/IUniswapV2Router01.sol";
import "./Interfaces/IUniswapV2Factory.sol";
import "./Interfaces/IUniswapV2Pair.sol";

/// @title Launch Sale Contract
/// @notice This contract is used as an initial sale of tokens for early adopters. Users will deposit buy orders before the token is minted. The orders will be fulfilled after the token is deployed and the initial liquidity is provided. This contract enables the updater to provide the initial liquidity as well, filling the buy orders in the same block. This ensures that all the orders will be filled at once, preventing faster buyers from getting a better price.
/// @dev The contract can be in one of the 4 states, PENDING, OPEN, FINISHED or CANCELLED. When deployed, the contract starts in the PENDING state. The updater can then switch to the OPEN state by calling the openSale() function. While in the OPEN state, users can call the buy() function. Once the sale is ended, the updater can then call the finishSale() function, which provides the initial liquidity, as well as uses the coin deposited using the buy() function to buy Honey tokens. The users can then claim their purchased Honey tokens using the claim() function, which releases tokens linearly until the end of the vesting period. If the updater deems it neccessary to cancel the sale, they can call the cancelSale() function, setting the contract state to CANCELLED. If the contract state is set to CANCELLED, the buyers can get their coin back using the refund() function.
contract LaunchSale is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MAX_PERCENTAGE = 100000;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant FUNDS_RECOVERY_ROLE =
        keccak256("FUNDS_RECOVERY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct BuyerData {
        uint256 purchasedAmount;
        uint256 claimedTokens;
    }

    enum SaleState {
        PENDING,
        OPEN,
        ENDED,
        FINISHED,
        CANCELLED
    }

    IUniswapV2Router01 public SwapRouter;
    IUniswapV2Factory public SwapFactory;
    IERC20Upgradeable public HoneyToken;

    mapping(address => BuyerData) public buyerData;
    SaleState public saleState;

    uint256 public totalValueSupplied;
    uint256 public totalTokensPurchased;
    uint256 public finishedBlock;
    uint256 public releasePeriodBlocks;
    uint256 public saleCapValue;

    bool public canRefundWhileOpen;
    bool public whitelistingEnabled;
    mapping(address => bool) public whitelistState;

    receive() external payable {}

    event Buy(address indexed _buyAddress, uint256 _amount);

    event Refund(address indexed _refundAddress, uint256 _amount);

    event ClaimedTokens(address indexed _claimerAddress, uint256 _amount);

    function initialize(
        address _admin,
        address _swapRouterAddress,
        uint256 _releasePeriodBlocks
    ) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPDATER_ROLE, _admin);
        __Pausable_init();
        SwapRouter = IUniswapV2Router01(_swapRouterAddress);
        SwapFactory = IUniswapV2Factory(SwapRouter.factory());
        releasePeriodBlocks = _releasePeriodBlocks;
        saleState = SaleState.PENDING;
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

    /// @notice Used to increase the buy order amount for the user. Can be called multiple times. Can only be called while the contract is in the OPEN state
    function buy() public payable whenNotPaused {
        require(saleState == SaleState.OPEN, "Sale is not open");
        require(
            saleCapValue == 0 || totalValueSupplied + msg.value <= saleCapValue,
            "Sale cap exceeded"
        );
        require(
            !whitelistingEnabled || whitelistState[msg.sender],
            "Address not whitelisted"
        );
        buyerData[msg.sender].purchasedAmount += msg.value;
        totalValueSupplied += msg.value;
        emit Buy(msg.sender, msg.value);
    }

    /// @notice Used to refund all the buy positions for the caller. Can only be called while the contract state is OPEN or CANCELLED
    function refund() public nonReentrant whenNotPaused {
        require(
            saleState == SaleState.OPEN || saleState == SaleState.CANCELLED,
            "Sale is not open or cancelled"
        );
        require(
            saleState != SaleState.OPEN || canRefundWhileOpen,
            "Cannot refund while open"
        );
        require(buyerData[msg.sender].purchasedAmount > 0, "Nothing to refund");

        uint256 refundAmount = buyerData[msg.sender].purchasedAmount;
        totalValueSupplied -= refundAmount;
        buyerData[msg.sender].purchasedAmount = 0;

        (bool transferSuccess, ) = payable(msg.sender).call{
            value: refundAmount
        }("");
        require(transferSuccess, "Refund transfer failed");
        emit Refund(msg.sender, refundAmount);
    }

    /// @notice Returns the amount of tokens that can be claimed by the user
    /// @dev It linearly releases tokens for 'releasePeriodBlocks' blocks from the moment the the contract state is moved to FINISHED. Returns 0 unless the contract state is FINISHED.
    /// @return tokens The amount minted in honey tokens
    function pendingTokens() public view returns (uint256) {
        if (saleState != SaleState.FINISHED) return 0;

        uint256 totalUserTokens = (totalTokensPurchased *
            buyerData[msg.sender].purchasedAmount) / totalValueSupplied;

        uint256 releasedUserTokens = ((block.number - finishedBlock) >=
            releasePeriodBlocks)
            ? totalUserTokens
            : (((block.number - finishedBlock) * totalUserTokens) /
                releasePeriodBlocks);

        return
            (releasedUserTokens <= buyerData[msg.sender].claimedTokens)
                ? 0
                : releasedUserTokens - buyerData[msg.sender].claimedTokens;
    }

    /// @notice Used to claim all the tokens made available to the caller up to the current block
    /// @dev Reverts if the sale is not FINISHED or there's nothing to claim
    function claimTokens() public whenNotPaused {
        require(saleState == SaleState.FINISHED, "Sale is not finished");
        uint256 pendingAmount = pendingTokens();
        require(pendingAmount > 0, "Nothing to claim");

        buyerData[msg.sender].claimedTokens += pendingAmount;
        IERC20Upgradeable(address(HoneyToken)).safeTransfer(
            msg.sender,
            pendingAmount
        );
        emit ClaimedTokens(msg.sender, pendingAmount);
    }

    /// @notice Opens the sale, enabling buyers to place orders
    /// @dev Can only be called by an UPDATER_ROLE account while the contract state is PENDING
    function openSale() public onlyRole(UPDATER_ROLE) {
        require(saleState == SaleState.PENDING, "Sale must be pending");
        saleState = SaleState.OPEN;
    }

    /// @notice Ends the sale, enabling giving the devs space to finish the sale
    /// @dev Can only be called by an UPDATER_ROLE account while the contract state is OPEN
    function endSale() public onlyRole(UPDATER_ROLE) {
        require(saleState == SaleState.OPEN, "Sale must be open");
        saleState = SaleState.ENDED;
    }

    /// @notice Used to finish the sale, provide the initial liquidity and purchase tokens with the deposited funds allocated during the sale
    /// @dev This function requires the caller to send BNB and set allowance for Honey based on the amount of liquidity that needs to be provided.
    /// @param honeyTokenAddress The address of the Honey token
    /// @param liquidityTokenAmount The amount of tokens to be added as liquidity
    /// @param suppliedLiquidityShare The percentage of BNB supplied by the buyers which will be used as additional liquidity
    /// @return finalReserveBnb - The BNB liquidity reserve once this operation is finished
    /// @return finalReserveHoney - The Honey liquidity reserve once this operation is finished
    function finishSale(
        address honeyTokenAddress,
        uint256 liquidityTokenAmount,
        uint256 suppliedLiquidityShare
    )
        public
        payable
        nonReentrant
        onlyRole(UPDATER_ROLE)
        returns (
            uint256 finalReserveBnb,
            uint256 finalReserveHoney,
            uint256 userTokens
        )
    {
        require(saleState == SaleState.ENDED, "Sale must be ended");
        require(
            suppliedLiquidityShare <= MAX_PERCENTAGE,
            "suppliedLiquidityShare cannot exceed MAX_PERCENTAGE"
        );

        saleState = SaleState.FINISHED;
        finishedBlock = block.number;
        HoneyToken = IERC20Upgradeable(honeyTokenAddress);

        // Pull tokens from the caller
        IERC20Upgradeable(address(HoneyToken)).safeTransferFrom(
            msg.sender,
            address(this),
            liquidityTokenAmount
        );

        // Allow SwapRouter to spend tokens in order to add liquidity
        IERC20Upgradeable(address(HoneyToken)).safeApprove(
            address(SwapRouter),
            liquidityTokenAmount
        );

        // Add 'liquidityTokenAmount' tokens and 'msg.value' ETH as liquidity
        SwapRouter.addLiquidityETH{value: msg.value}(
            address(HoneyToken),
            liquidityTokenAmount,
            liquidityTokenAmount,
            msg.value,
            msg.sender,
            block.timestamp + 1
        );

        // Compute the amount of buyer supplied BNB that will go into liquidity
        uint256 suppliedLiquidityAmount = (totalValueSupplied *
            suppliedLiquidityShare) / MAX_PERCENTAGE;

        // Compute the amount of buyer supplied BNB used to buy tokens
        uint256 suppliedPurchaseAmount = totalValueSupplied -
            suppliedLiquidityAmount;

        // Purchase tokens with the supplied value via purchases
        address[] memory pairs = new address[](2);
        pairs[0] = SwapRouter.WETH();
        pairs[1] = address(HoneyToken);

        uint256 tokensPurchased = SwapRouter.swapExactETHForTokens{
            value: suppliedPurchaseAmount
        }(0, pairs, address(this), block.timestamp + 1)[1];

        // Add extra liquidity from supplied BNB and purchased tokens
        uint256 usedAdditionalTokens = 0;
        if (suppliedLiquidityAmount > 0) {
            // Allow SwapRouter to spend tokens in order to add liquidity
            IERC20Upgradeable(address(HoneyToken)).safeApprove(
                address(SwapRouter),
                tokensPurchased
            );

            (usedAdditionalTokens, , ) = SwapRouter.addLiquidityETH{
                value: suppliedLiquidityAmount
            }(
                address(HoneyToken),
                tokensPurchased,
                0,
                suppliedLiquidityAmount,
                msg.sender,
                block.timestamp + 1
            );
        }

        totalTokensPurchased = tokensPurchased - usedAdditionalTokens;
        userTokens = totalTokensPurchased;

        IUniswapV2Pair HoneyBnbPair = IUniswapV2Pair(
            SwapFactory.getPair(SwapRouter.WETH(), honeyTokenAddress)
        );

        if (HoneyBnbPair.token0() == honeyTokenAddress) {
            (finalReserveHoney, finalReserveBnb, ) = HoneyBnbPair.getReserves();
        } else {
            (finalReserveBnb, finalReserveHoney, ) = HoneyBnbPair.getReserves();
        }
    }

    /// @notice Cancels the sale, enabling buyers to refund their positions
    /// @dev Can only be called by an UPDATER_ROLE account while the contract state is OPEN
    function cancelSale() public onlyRole(UPDATER_ROLE) {
        require(
            saleState == SaleState.OPEN || saleState == SaleState.ENDED,
            "Sale must be open or ended"
        );
        saleState = SaleState.CANCELLED;
    }

    /// @notice Sets the number of blocks required to pass before all the tokens are made available for claim
    /// @dev Can only be called by an UPDATER_ROLE account
    /// @param _releasePeriodBlocks The release period in blocks
    function setReleasePeriodBlocks(uint256 _releasePeriodBlocks)
        public
        onlyRole(UPDATER_ROLE)
    {
        releasePeriodBlocks = _releasePeriodBlocks;
    }

    /// @notice Sets the BNB value above which the buy() function is disabled. The sale cap feature is disabled if the sale cap value is set to zero
    /// @param _saleCapValue The sale cap value
    function setSaleCapValue(uint256 _saleCapValue)
        public
        onlyRole(UPDATER_ROLE)
    {
        saleCapValue = _saleCapValue;
    }

    /// @notice Sets whether witelisting is enabled
    /// @param _whitelistingEnabled The whitelisting enabled state
    function setWhitelistingEnabled(bool _whitelistingEnabled)
        public
        onlyRole(UPDATER_ROLE)
    {
        whitelistingEnabled = _whitelistingEnabled;
    }

    /// @notice Sets or clears a buyer's address from the whitelist
    /// @param _buyer Buyer's address
    /// @param _state New whitelist state
    function setWhitelistingState(address _buyer, bool _state)
        public
        onlyRole(UPDATER_ROLE)
    {
        whitelistState[_buyer] = _state;
    }

    /// @notice Enables or disables the possibility to refund purchases while the launch sale is open
    /// @param _state New refund while open state
    function setCanRefundWhileOpen(bool _state)
        external
        onlyRole(UPDATER_ROLE)
    {
        canRefundWhileOpen = _state;
    }

    function getBuyPercentage(uint256 depositAmount)
        public
        pure
        returns (uint256)
    {
        return (
            depositAmount * 2 < 1000000 ? 100000 : depositAmount * 2 < 5000000
                ? 73000000000000 / (400 * depositAmount * 2 + 590000000) + 26000
                : 80000000000000 / (195 * depositAmount * 2 + 960000000) + 12800
        );
    }

    function getPriceData(
        uint256 userDeposit,
        uint256 initialBnb,
        uint256 initialGhny
    )
        public
        view
        returns (
            uint256 averagePrice,
            uint256 launchPrice,
            uint256 purchasedTokens,
            uint256 decimalOffset
        )
    {
        decimalOffset = 1000000;
        uint256 depositAmount = userDeposit + totalValueSupplied;
        uint256 k = initialBnb * initialGhny;
        uint256 buyPercentage = getBuyPercentage(depositAmount / (1 ether));

        uint256 bnbReserveAfterBuy = initialBnb +
            (depositAmount * buyPercentage) /
            MAX_PERCENTAGE;
        uint256 ghnyReserveAfterBuy = k / bnbReserveAfterBuy;

        launchPrice =
            (bnbReserveAfterBuy * decimalOffset) /
            ghnyReserveAfterBuy;

        uint256 buyShare = (depositAmount * (MAX_PERCENTAGE - buyPercentage)) /
            MAX_PERCENTAGE;
        uint256 bnbReserveAtLaunch = bnbReserveAfterBuy + buyShare;
        uint256 ghnyReserveAtLaunch = ghnyReserveAfterBuy +
            (buyShare * decimalOffset) /
            launchPrice;
        k = bnbReserveAtLaunch * ghnyReserveAtLaunch;

        averagePrice =
            (depositAmount * decimalOffset) /
            (initialGhny - ghnyReserveAtLaunch);
        purchasedTokens = (depositAmount * decimalOffset) / averagePrice;
    }

    uint256[50] private __gap;
}
