// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Launchpad } from "../src/Launchpad.sol";
import { LaunchpadErrors } from "../src/LaunchpadErrors.sol";

contract LaunchpadTest is Test {
    Launchpad public launchpad;
    MockERC20 public usdc;
    IERC20 public token;

    address public beneficiary = makeAddr("beneficiary");
    address public platform = makeAddr("platform");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public mockUniswapRouter = makeAddr("uniswapRouter");
    uint256 public targetRaise = 50_000 * 1e6;
    uint256 public targetSupply = 500_000_000 * 1e18;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        Launchpad launchpadImpl = new Launchpad();
        bytes memory initData = abi.encodeWithSelector(
            Launchpad.initialize.selector,
            "Project Token",
            "PROJ",
            beneficiary,
            mockUniswapRouter,
            IERC20(address(usdc)),
            targetRaise
        );
        address proxy = address(new ERC1967Proxy(address(launchpadImpl), initData));
        launchpad = Launchpad(proxy);

        token = IERC20(launchpad.getToken());
        usdc.mint(buyer1, 100_000 * 1e6);
        usdc.mint(buyer2, 100_000 * 1e6);
    }

    function testFuzzIncrementalPurchases(uint256 n) public {
        n = bound(n, 1, 1000);
        uint256 iterations = n;
        uint256 usdcAmt = targetRaise / iterations;

        for (uint256 i = 0; i < iterations; i++) {
            vm.startPrank(buyer1);
            usdc.approve(address(launchpad), usdcAmt);
            launchpad.buyTokens(usdcAmt);
            vm.stopPrank();
        }

        uint256 userPurchase = launchpad.getUserPurchase(buyer1);
        assertGt(userPurchase, 0, "User purchase should be tracked");

        (, uint256 tokensSoldSoFar, uint256 reserveBalance, bool finalized) = launchpad.getState();
        vm.assertApproxEqAbs(tokensSoldSoFar, 500 * 1e6 * 1e18, 10 * 1e18, "Should have sold 500 million tokens so far");
        vm.assertApproxEqAbs(reserveBalance, targetRaise, 1e3, "Should have gotten the raise amount equal to target");
        assertFalse(finalized, "Sale should not be automatically finalized");
    }

    function testFuzzIncrementalExactTokenPurchases(uint256 n) public {
        n = bound(n, 1, 1000); // Limit the number of iterations to a reasonable range.
        uint256 iterations = n;
        uint256 increment = 500_000_000 * 1e18 / n;
        uint256 previousCost;

        for (uint256 i = 0; i < iterations; i++) {
            uint256 usdcAmount = launchpad.getTokenPurchasePrice(increment);
            vm.startPrank(buyer1);
            usdc.approve(address(launchpad), usdcAmount);
            assertGt(usdcAmount, previousCost, "USDC amount should be increasing");
            previousCost = usdcAmount;
            launchpad.buyTokensForExactTokens(increment);
            vm.stopPrank();
        }

        // Verify final state
        (, uint256 tokensSoldSoFar, uint256 reserveBalance,) = launchpad.getState();
        vm.assertApproxEqAbs(tokensSoldSoFar, 500 * 1e6 * 1e18, 1e4, "Should have sold 500 million tokens so far");
        vm.assertApproxEqAbs(reserveBalance, targetRaise, 1e4, "Should have gotten the raise amount equal to target");
        vm.assertApproxEqAbs(
            usdc.balanceOf(address(launchpad)),
            targetRaise,
            1e4,
            "Launchpad should hold the target raise amount in USDC"
        );
        vm.assertApproxEqAbs(launchpad.getUserPurchase(buyer1), 500_000_000 * 1e18, 1e5, "User purchase is 500M tokens");
    }

    function testBuyAllAtOnceExactToken() public {
        uint256 usdcAmount = launchpad.getTokenPurchasePrice(targetSupply);
        assertEq(usdcAmount, targetRaise, "Complete purchase should cost exactly targetRaise");

        vm.startPrank(buyer1);
        usdc.approve(address(launchpad), usdcAmount);
        launchpad.buyTokensForExactTokens(targetSupply);
        vm.stopPrank();

        uint256 userPurchase = launchpad.getUserPurchase(buyer1);
        assertEq(userPurchase, targetSupply, "User purchase should equal target supply");

        (, uint256 tokensSoldSoFar, uint256 reserveBalance,) = launchpad.getState();
        assertEq(tokensSoldSoFar, targetSupply, "Should have sold all tokens");
        assertEq(reserveBalance, targetRaise, "Should have raised target amount");
        vm.assertApproxEqAbs(launchpad.getUserPurchase(buyer1), 500_000_000 * 1e18, 1e5, "User purchase is 500M tokens");
    }

    function testBuyAllAtOnceViaUSDCInput() public {
        uint256 initialUSDCBalance = usdc.balanceOf(buyer1);

        vm.startPrank(buyer1);
        usdc.approve(address(launchpad), targetRaise);
        uint256 tokensReceived = launchpad.buyTokens(targetRaise);
        vm.stopPrank();

        uint256 userPurchase = launchpad.getUserPurchase(buyer1);
        assertEq(userPurchase, tokensReceived, "User purchase should equal tokens received");
        assertEq(tokensReceived, targetSupply, "Should receive entire token supply");

        (, uint256 tokensSoldSoFar, uint256 reserveBalance,) = launchpad.getState();
        assertEq(tokensSoldSoFar, targetSupply, "All tokens should be sold");
        assertEq(reserveBalance, targetRaise, "Should have raised target amount");
        assertEq(
            usdc.balanceOf(buyer1), initialUSDCBalance - targetRaise, "Buyer should have spent target amount of USDC"
        );
        assertEq(usdc.balanceOf(address(launchpad)), targetRaise, "Launchpad should have received all USDC");
    }

    function testFinalization() public { }

    function testClaim() public {
        // Buy tokens first
        uint256 purchaseAmount = launchpad.minTokenAmountPurchase();
        uint256 usdcCost = launchpad.getTokenPurchasePrice(purchaseAmount);

        vm.startPrank(buyer1);
        usdc.approve(address(launchpad), usdcCost);
        launchpad.buyTokensForExactTokens(purchaseAmount);
        // Check purchase is recorded
        uint256 userPurchase = launchpad.getUserPurchase(buyer1);
        assertEq(userPurchase, purchaseAmount, "User purchase should be recorded correctly");
        // Attempt to claim tokens to another address (e.g., a wallet)
        address recipient = makeAddr("recipient");
        vm.expectRevert(LaunchpadErrors.NotFinalized.selector); // Should revert when finalized=false
        launchpad.claim(recipient);
        vm.stopPrank();

        launchpad.pause();
        launchpad.finalize();

        // Claim now
        vm.startPrank(buyer1);
        launchpad.claim(buyer1);
    }

    function testCollectFee() public { }
}

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimalsValue) ERC20(name, symbol) {
        _decimals = decimalsValue;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
