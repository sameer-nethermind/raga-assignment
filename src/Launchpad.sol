// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Token} from "./Token.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@prb/math/SD59x18.sol";

contract Launchpad is UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("Launchpad.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LAUNCHPAD_STORAGE_SLOT = 0xa44d8294f0e4adb9d0865948bd1fdf37d2de32fe309eb032411521430025c400;

    /// @custom:storage-location erc7201:Launchpad.storage
    struct LaunchpadStorage {
        uint256 targetRaise;
        IERC20 token;
        IERC20 USDC;
        mapping(address => uint256) purchased;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contracts storage variables
     * @param owner_ The owner of the contract instance
     * @param usdc_ The payment token is USDC
     */
    function initialize(string memory name_, string memory symbol_, address owner_, IERC20 usdc_, uint256 targetRaise_) public initializer {
        __Ownable_init(owner_);
        __Pausable_init();

        // Deploy the ERC20 token contract that we're selling
        LaunchpadStorage storage $ = _getLaunchpadStorage();
        $.token = IERC20(new Token(name_, symbol_));
        $.USDC = usdc_;
        $.targetRaise = targetRaise_;
    }

    function _computeCRR(
        uint256 initialReserve,
        uint256 initialSupply,
        uint256 tokensToSell
    )
        internal
        view
        returns (uint256 c)
    {
        LaunchpadStorage storage $ = _getLaunchpadStorage();

        int256 lnNumerator = unwrap(ln(sd(int256(($.targetRaise + initialReserve) * 1e18 / initialReserve))));
        int256 lnDenominator = unwrap(ln(sd(int256((initialSupply + tokensToSell) * 1e18 / initialSupply))));
        return uint256(lnNumerator * 1e18 * 1e18 / lnDenominator);
    }

    /**
     * @dev Uses bancor's bonding curve to figure out price of the tokens user wants to purchase
     * @param amount_ The amount of tokens user wants to purchase
     * @return paid The total USDC user paid for the `amount_`
     */
    function getPrice(uint256 amount_) public view returns (uint256 paid) {
        // TODO: Implement the bonding curve
    }

    function purchase(uint256) public { }

    function startSale() public onlyOwner whenNotPaused { }

    function stopSale() public onlyOwner whenNotPaused {
        _createPoolOnUniswap();
    }

    function _createPoolOnUniswap() internal { }

    /**
     * @notice Retrieves the storage slot for the `LAUNCHPAD_STORAGE_SLOT` structure.
     * @dev Uses inline assembly to map the predefined storage slot to the `LAUNCHPAD_STORAGE_SLOT` structure.
     * This function is used internally to access the settlement token's specific storage layout.
     * @return $ reference to the `LaunchpadStorage` located at the predefined storage slot.
     */
    function _getLaunchpadStorage() private pure returns (LaunchpadStorage storage $) {
        assembly {
            $.slot := LAUNCHPAD_STORAGE_SLOT
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override { }
}
