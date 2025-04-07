// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILaunchpad
 * @notice Interface for a Launchpad contract implementing a bonding curve token sale.
 */
interface ILaunchpad {
    /**
     * @notice Emitted when the Launchpad is initialized.
     * @param token Address of the token created for the launch.
     * @param beneficiary Address of the beneficiary of the token sale.
     * @param uniswapRouter Address of the Uniswap router for liquidity provision.
     * @param targetRaise Target amount to raise in USDC (6 decimals).
     * @param saleSupply Total tokens available for sale.
     */
    event LaunchpadInitialized(
        address indexed token,
        address indexed beneficiary,
        address uniswapRouter,
        uint256 targetRaise,
        uint256 saleSupply
    );

    /**
     * @notice Emitted when tokens are purchased.
     * @param buyer Address of the purchaser.
     * @param reserveAmount Amount of USDC used in the purchase (6 decimals).
     * @param tokenAmount Amount of tokens purchased (18 decimals).
     */
    event TokensPurchased(address indexed buyer, uint256 reserveAmount, uint256 tokenAmount);

    /**
     * @notice Emitted when the token sale is finalized.
     * @param totalRaised Total USDC raised during the sale.
     * @param beneficiaryTokens Number of tokens allocated to the beneficiary.
     * @param beneficiaryUSDC Amount of USDC transferred to the beneficiary.
     * @param liquidityTokens Number of tokens allocated for liquidity.
     * @param liquidityUSDC Amount of USDC allocated for liquidity.
     */
    event SaleFinalized(
        uint256 totalRaised,
        uint256 beneficiaryTokens,
        uint256 beneficiaryUSDC,
        uint256 liquidityTokens,
        uint256 liquidityUSDC
    );

    /**
     * @notice Emitted when platform fees are collected.
     * @param recipient Address receiving the fee.
     * @param feeAmount Amount of fee collected in USDC.
     */
    event FeeCollected(address indexed recipient, uint256 feeAmount);

    /**
     * @notice Emitted when a purchase claim is processed.
     * @param recipient Address receiving the claimed tokens.
     * @param amount Amount of tokens claimed.
     */
    event Claimed(address indexed recipient, uint256 amount);

    /**
     * @notice Initializes the Launchpad contract.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param beneficiary_ Address of the fundraise beneficiary.
     * @param uniswapFactory Address of the Uniswap factory for creating pairs.
     * @param uniswapRouter_ Uniswap router address for liquidity provision.
     * @param usdc_ USDC token contract address.
     * @param targetRaise_ Target USDC raise amount (6 decimals).
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address beneficiary_,
        address uniswapFactory,
        address uniswapRouter_,
        IERC20 usdc_,
        uint256 targetRaise_
    )
        external;

    /**
     * @notice Retrieves the current state of the token sale.
     * @return saleSupply Total tokens allocated for sale.
     * @return currentSupply Tokens sold so far.
     * @return currentReserve USDC reserve balance.
     * @return finalized Whether the sale has been finalized.
     */
    function getState()
        external
        view
        returns (uint256 saleSupply, uint256 currentSupply, uint256 currentReserve, bool finalized);

    /**
     * @notice Gets the address of the token being sold.
     * @return The token's address.
     */
    function getToken() external view returns (address);

    /**
     * @notice Returns the number of tokens purchased by a specific user.
     * @param user Address of the user.
     * @return amount Amount of tokens purchased.
     */
    function getUserPurchase(address user) external view returns (uint256 amount);

    /**
     * @notice Calculates the amount of tokens that can be bought for a given USDC amount.
     * @param usdcAmount_ The USDC amount provided (6 decimals).
     * @return tokenAmount The corresponding token amount (18 decimals).
     */
    function getTokenAmountForUSDC(uint256 usdcAmount_) external view returns (uint256 tokenAmount);

    /**
     * @notice Calculates the USDC cost for purchasing a specific token amount.
     * @param tokenAmount_ The desired token amount (18 decimals).
     * @return usdcAmount The required USDC amount (6 decimals).
     */
    function getTokenPurchasePrice(uint256 tokenAmount_) external view returns (uint256 usdcAmount);

    /**
     * @notice Purchases tokens by providing a specified USDC amount.
     * @param usdcAmount Amount of USDC to spend (6 decimals).
     * @return tokenAmount Amount of tokens purchased (18 decimals).
     */
    function buyTokens(uint256 usdcAmount) external returns (uint256 tokenAmount);

    /**
     * @notice Purchases an exact token amount.
     * @param tokenAmount The exact token amount to purchase (18 decimals).
     * @return usdcAmount The USDC amount charged (6 decimals).
     */
    function buyTokensForExactTokens(uint256 tokenAmount) external returns (uint256 usdcAmount);

    /**
     * @notice Finalizes the token sale and distributes tokens and USDC per allocation rules.
     */
    function finalize() external;

    /**
     * @notice Collects the platform fee after sale finalization.
     * @param recipient Address to receive the fee.
     */
    function collectFee(address recipient) external;

    /**
     * @notice Claims tokens purchased by the caller.
     * @param recipient Address to receive the claimed tokens.
     */
    function claim(address recipient) external;

    /**
     * @notice Pauses the contract.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external;

    /**
     * @notice Checks whether the token sale has been finalized.
     * @return True if finalized, false otherwise.
     */
    function isFinalized() external view returns (bool);
}
