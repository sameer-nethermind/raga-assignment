// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Token } from "./Token.sol";
import { LaunchpadErrors } from "./LaunchpadErrors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract Launchpad is
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    LaunchpadErrors
{
    using SafeERC20 for IERC20;

    // Constants for token allocation percentages
    uint256 private constant TOTAL_SUPPLY = 1000 * 1e6 * 1e18; // 1B tokens
    uint256 private constant SALE_PERCENTAGE = 50; // 50% for sale (500M)
    uint256 private constant BENEFICIARY_PERCENTAGE = 20; // 20% for beneficiary (200M)
    uint256 private constant LIQUIDITY_PERCENTAGE = 25; // 25% for liquidity (250M)
    uint256 private constant PLATFORM_PERCENTAGE = 5; // 5% for platform (50M)

    // Storage slot for upgradeable pattern
    bytes32 private constant LAUNCHPAD_STORAGE_SLOT = 0xa44d8294f0e4adb9d0865948bd1fdf37d2de32fe309eb032411521430025c400;

    // Events
    event LaunchpadInitialized(
        address indexed token,
        address indexed beneficiary,
        address uniswapRouter,
        uint256 targetRaise,
        uint256 saleSupply
    );
    event TokensPurchased(address indexed buyer, uint256 reserveAmount, uint256 tokenAmount);
    event SaleFinalized(
        uint256 totalRaised,
        uint256 beneficiaryTokens,
        uint256 beneficiaryUSDC,
        uint256 liquidityTokens,
        uint256 liquidityUSDC
    );
    event FeeCollected(address indexed recipient, uint256 feeAmount);
    event Claimed(address indexed recipient, uint256 amount);

    /// @custom:storage-location erc7201:Launchpad.storage
    struct LaunchpadStorage {
        // Token sale parameters
        uint256 targetRaise;
        uint256 saleSupply;
        uint256 minimumTokenAmountPurchase;
        // State tracking
        uint256 tokensSoldSoFar;
        uint256 reserveBalance;
        bool isFinalized;
        // Addresses
        IERC20 token;
        IERC20 USDC;
        address beneficiary;
        address platform;
        address uniswapRouter;
        // Purchase tracking
        mapping(address => uint256) purchases; // Track individual purchases
    }

    /**
     * @dev Constructor disables initializers to prevent direct implementation initialization
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @dev Sets up the token sale parameters and creates the token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param beneficiary_ Address of the fundraise beneficiary
     * @param uniswapRouter_ Uniswap router address for liquidity provision
     * @param usdc_ USDC token contract address
     * @param targetRaise_ Target amount to raise in USDC (with 6 decimals)
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address beneficiary_,
        address uniswapRouter_,
        IERC20 usdc_,
        uint256 targetRaise_
    )
        public
        initializer
    {
        // Input validation
        if (beneficiary_ == address(0)) revert InvalidAddress();
        if (uniswapRouter_ == address(0)) revert InvalidAddress();
        if (address(usdc_) == address(0)) revert InvalidAddress();
        if (targetRaise_ == 0) revert InvalidAmount();

        // Initialize upgradeable contracts
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();

        // Initialize storage
        LaunchpadStorage storage $ = _getLaunchpadStorage();

        // Create new token and mint total supply to this contract
        Token token = new Token(name_, symbol_);
        $.token = IERC20(address(token));

        // Set storage values
        $.USDC = usdc_;
        $.targetRaise = targetRaise_;
        $.saleSupply = Math.mulDiv(TOTAL_SUPPLY, SALE_PERCENTAGE, 100);
        $.beneficiary = beneficiary_;
        $.uniswapRouter = uniswapRouter_;
        $.isFinalized = false;

        $.minimumTokenAmountPurchase =
            Math.sqrt(Math.mulDiv($.saleSupply, $.saleSupply, targetRaise_), Math.Rounding.Ceil);

        emit LaunchpadInitialized(address($.token), beneficiary_, uniswapRouter_, targetRaise_, $.saleSupply);
    }

    /**
     * @notice Returns the current state of the token sale
     * @return saleSupply The total tokens available for sale
     * @return currentSupply The tokens sold so far
     * @return currentReserve The USDC reserve balance
     * @return finalized Whether the sale has been finalized
     */
    function getState()
        external
        view
        returns (uint256 saleSupply, uint256 currentSupply, uint256 currentReserve, bool finalized)
    {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        return ($.saleSupply, $.tokensSoldSoFar, $.reserveBalance, $.isFinalized);
    }

    /// @dev Returns the token address user is purchasing
    function getToken() external view returns (address) {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        return address($.token);
    }

    /**
     * @notice Returns how many tokens a specific user has purchased
     * @param user The user's address
     * @return amount The amount of tokens purchased
     */
    function getUserPurchase(address user) external view returns (uint256 amount) {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        return $.purchases[user];
    }

    function getMinimumTokenAmountPurchase() external view returns (uint256) {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        return $.minimumTokenAmountPurchase;
    }

    // ===============================================
    // Bonding Curve & Purchase Functions
    // ===============================================

    /**
     * @notice Calculates the USDC cost to move the token supply from currentSupply to newSupply
     * @dev Uses the quadratic bonding curve formula
     * @param $ The Launchpad storage struct
     * @param newSupply_ The new token supply after purchase
     * @return cost The cost in USDC (in 1e6 scale)
     */
    function _getPrice(LaunchpadStorage storage $, uint256 newSupply_) internal view returns (uint256 cost) {
        // Handle edge case
        if ($.tokensSoldSoFar >= newSupply_) return 0;

        // Calculate using the quadratic formula
        uint256 newSupplySquared = newSupply_ * newSupply_;
        uint256 currentSupplySquared = $.tokensSoldSoFar * $.tokensSoldSoFar;
        uint256 numerator = newSupplySquared - currentSupplySquared;
        uint256 denominator = $.saleSupply * $.saleSupply;

        // Use safe math multiplication to avoid precision loss
        cost = Math.mulDiv($.targetRaise, numerator, denominator);
    }

    /**
     * @notice Given a USDC amount, calculates how many tokens can be purchased
     * @dev Uses the inverse of the bonding curve formula
     * @param usdcAmount_ The USDC provided (in 1e6 scale)
     * @return tokenAmount The amount of tokens to be purchased (in 1e18 scale)
     */
    function getTokenAmountForUSDC(uint256 usdcAmount_) public view returns (uint256 tokenAmount) {
        if (usdcAmount_ == 0) return 0;

        LaunchpadStorage storage $ = _getLaunchpadStorage();
        if ($.isFinalized) return 0;

        uint256 currentSupply = $.tokensSoldSoFar;
        uint256 currentSupplySquared = currentSupply * currentSupply;

        uint256 saleSupplySquared = $.saleSupply * $.saleSupply;
        uint256 delta = Math.mulDiv(usdcAmount_, saleSupplySquared, $.targetRaise);
        uint256 newSupplySquared = currentSupplySquared + delta;
        uint256 newSupply = Math.sqrt(newSupplySquared, Math.Rounding.Ceil);

        if (newSupply <= currentSupply) return 0;

        tokenAmount = newSupply - currentSupply; // amt out

        // Ensure we don't exceed the remaining supply
        uint256 remainingSupply = $.saleSupply - $.tokensSoldSoFar;
        if (tokenAmount > remainingSupply) {
            tokenAmount = remainingSupply;
        }
    }

    /**
     * @notice Given a desired token amount to purchase, calculates the required USDC
     * @param tokenAmount_ The token amount desired (in 1e18 scale)
     * @return usdcAmount The required USDC (in 1e6 scale)
     */
    function getTokenPurchasePrice(uint256 tokenAmount_) public view returns (uint256 usdcAmount) {
        if (tokenAmount_ == 0) return 0;

        LaunchpadStorage storage $ = _getLaunchpadStorage();
        if ($.isFinalized) return 0;

        uint256 newSupply = $.tokensSoldSoFar + tokenAmount_;
        if (newSupply > $.saleSupply) {
            revert ExceedsMaxSupply();
        }

        usdcAmount = _getPrice($, newSupply);
    }

    /**
     * @notice Purchase tokens by providing a USDC amount
     * @param usdcAmount The USDC amount provided (in 1e6 scale)
     * @return tokenAmount The amount of tokens purchased (in 1e18 scale)
     */
    function buyTokens(uint256 usdcAmount) external whenNotPaused nonReentrant returns (uint256 tokenAmount) {
        LaunchpadStorage storage $ = _getLaunchpadStorage();

        // Input validation
        if ($.isFinalized) revert AlreadyFinalized();
        if (usdcAmount == 0) revert InvalidAmount();

        // Calculate tokens to purchase
        tokenAmount = getTokenAmountForUSDC(usdcAmount);
        if (tokenAmount == 0) revert InsufficientTokenAmount();
        if ($.tokensSoldSoFar + tokenAmount > $.saleSupply) revert ExceedsMaxSupply();

        // Transfer USDC from sender
        $.USDC.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Update state
        $.tokensSoldSoFar += tokenAmount;
        $.reserveBalance += usdcAmount;
        $.purchases[msg.sender] += tokenAmount;

        emit TokensPurchased(msg.sender, usdcAmount, tokenAmount);
    }

    /**
     * @notice Purchase an exact token amount
     * @param tokenAmount The exact token amount the buyer wants
     * @return usdcAmount The USDC amount charged
     */
    function buyTokensForExactTokens(uint256 tokenAmount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 usdcAmount)
    {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        if ($.minimumTokenAmountPurchase > tokenAmount) revert AmountTooLess();
        if ($.isFinalized) revert AlreadyFinalized();
        if (tokenAmount == 0) revert InvalidAmount();
        if ($.tokensSoldSoFar + tokenAmount > $.saleSupply) revert ExceedsMaxSupply();

        // Calculate USDC price
        usdcAmount = getTokenPurchasePrice(tokenAmount);
        if (usdcAmount == 0) revert InsufficientUSDCAmount();
        $.USDC.safeTransferFrom(msg.sender, address(this), usdcAmount);
        // Effect
        $.tokensSoldSoFar += tokenAmount;
        $.reserveBalance += usdcAmount;
        $.purchases[msg.sender] += tokenAmount;

        emit TokensPurchased(msg.sender, usdcAmount, tokenAmount);
    }

    /**
     * @notice Finalize the token sale and distribute tokens
     * @dev Can only be called by the owner when target is reached or sale is paused
     */
    function finalize() external onlyOwner nonReentrant {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        if ($.isFinalized) revert AlreadyFinalized();
        if ($.tokensSoldSoFar < $.saleSupply && !paused()) {
            revert NeitherPausedNorSaleEnded();
        }
        _finalize();
    }

    /**
     * @notice Internal implementation of finalize function
     * @dev Distributes tokens and USDC according to the allocation rules
     */
    function _finalize() internal {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        uint256 beneficiaryTokens = Math.mulDiv(TOTAL_SUPPLY, BENEFICIARY_PERCENTAGE, 100);
        uint256 liquidityTokens = Math.mulDiv(TOTAL_SUPPLY, LIQUIDITY_PERCENTAGE, 100);

        // Calculate USDC distribution
        uint256 totalRaised = $.reserveBalance;
        uint256 beneficiaryUSDC = totalRaised / 2; // 50% to beneficiary or creator of the fund raise
        uint256 liquidityUSDC = totalRaised - beneficiaryUSDC; // Rest to the uniswap pool

        // 1. Transfer tokens to the beneficiary
        $.token.transfer($.beneficiary, beneficiaryTokens);
        // 2. Transfer USDC to the beneficiary
        $.USDC.transfer($.beneficiary, beneficiaryUSDC);
        // 3. Handle Uniswap liquidity
        // Approve tokens for Uniswap router
        $.token.approve($.uniswapRouter, liquidityTokens);
        $.USDC.approve($.uniswapRouter, liquidityUSDC);

        // TODO: Implement actual Uniswap pool creation

        // Mark as finalized
        $.isFinalized = true;

        // Emit finalization event
        emit SaleFinalized(totalRaised, beneficiaryTokens, beneficiaryUSDC, liquidityTokens, liquidityUSDC);
    }

    /**
     * @notice Collect the token fees from the contract
     * @dev Can only be called by the owner after the sale if `finalized()`
     * @param recipient The address to send the USDC to
     */
    function collectFee(address recipient) external onlyOwner {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        uint256 fee = Math.mulDiv(TOTAL_SUPPLY, PLATFORM_PERCENTAGE, 100);

        // Ensure the sale has finalized
        if (!$.isFinalized) revert NotFinalized();

        // Transfer fee share of tokens to the recipient
        $.USDC.safeTransfer(recipient, fee);

        emit FeeCollected(recipient, fee);
    }

    function claim(address recipient) public {
        LaunchpadStorage storage $ = _getLaunchpadStorage();

        if ($.purchases[msg.sender] == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidAddress();
        if (!$.isFinalized) revert NotFinalized();

        uint256 claimAmount = $.purchases[msg.sender];
        $.purchases[msg.sender] = 0;
        // Transfer tokens to the recipient
        $.token.safeTransfer(recipient, claimAmount);
        emit Claimed(recipient, claimAmount);
    }

    /**
     * @notice Pause the contract
     * @dev Can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Check if the sale has been finalized
     * @return True if the sale is finalized, false otherwise
     */
    function isFinalized() external view returns (bool) {
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        return $.isFinalized;
    }

    /**
     * @notice Internal function to retrieve the Launchpad storage
     * @return s The Launchpad storage struct
     */
    function _getLaunchpadStorage() private pure returns (LaunchpadStorage storage s) {
        assembly {
            s.slot := LAUNCHPAD_STORAGE_SLOT
        }
    }

    /**
     * @notice Authorize contract upgrades via UUPS pattern
     * @dev Can only be called by owner
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
