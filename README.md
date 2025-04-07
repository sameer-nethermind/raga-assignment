# Raga Assignment

## Overview
This contract manages a token sale for a new ERC-20 token (the Token). The sale is governed by a quadratic bonding curve that gradually increases the token price as more tokens are sold. It also reserves portions of the total token supply for different allocations (beneficiary, liquidity, platform fee).
> NOTE: There is another branch that has the uniswap pool creation code, that is not in the main branch because that was causing test errors that I did not fix.

After the sale is complete (or paused), the owner can finalize the sale. This triggers token and USDC distributions:
1. Beneficiary receives its designated portion of tokens and some USDC.
2. Liquidity is added to Uniswap V4.
3. Platform can collect a fee.

Users who bought tokens during the sale can then call `claim()` to receive their purchased tokens.

## Bonding Curve Math
A quadratic bonding curve is used here to smoothly increase the price of tokens as more tokens are bought. The contract tracks:

* `tokensSoldSoFar`: the number of tokens already sold to investors.
* `targetRaise`: the total amount of USDC intended to be raised across the entire bonding curve (when the entire sale supply is sold).
* `saleSupply`: the total number of tokens available for sale.

### Purchase Price Calculation: `_getPrice()`
When a user buys tokens, we compute the cost (in USDC) for the system to move from `tokensSoldSoFar → newSupply` (where `newSupply = tokensSoldSoFar + tokensBeingPurchased`). The formula is:
```
cost = (targetRaise) * (newSupply^2 - tokensSoldSoFar^2) / (saleSupply^2)
```

* `newSupply^2 - tokensSoldSoFar^2` is effectively the difference between squares (e.g. (n^2 - m^2) = (n+m)(n-m)), capturing the "area" under the quadratic curve.

* `targetRaise / saleSupply^2` sets the scale so that if `saleSupply` tokens are sold, it matches targetRaise in total.

### Tokens for Given USDC (getTokenAmountForUSDC)
A user may want to spend a certain amount of USDC and see how many tokens that yields. Solving the equation inversely:

```
newSupply^2 = tokensSoldSoFar^2 + (usdcAmount * saleSupply^2 / targetRaise)
```
This becomes:
```
newSupply = sqrt( tokensSoldSoFar^2 + (usdcAmount * saleSupply^2 / targetRaise) )
```
The numer of tokens user gets:
```
tokenAmount = newSupply - tokensSoldSoFar
```

### USDC for Given Tokens (getTokenPurchasePrice)
Alternatively, the user may specify exactly how many tokens they want. If `tokenAmount = newSupply - tokensSoldSoFar`, we plug this `newSupply` into `_getPrice()`. The result is the cost in USDC.

### Important external functions
#### `buyTokens()`
A user calls buyTokens(uint256 usdcAmount), specifying the amount of USDC they wish to spend. Internally, we compute how many tokens (tokenAmount) that USDC can buy using the quadratic bonding curve. Then:

1. Transfer the USDC from the user into the contract
2. Increase tokensSoldSoFar by the corresponding tokenAmount.
3. Increase the reserveBalance by the USDC just received.
4. Record the purchase in purchases[msg.sender].

#### `buyTokensForExactTokens()` - Recommended
Alternatively, the user can call `buyTokensForExactTokens(uint256 tokenAmount)`, specifying exactly how many tokens they want. The contract calculates how much USDC that requires. This approach is MEV resistant because there is no manipulation in which user ends up getting lesser tokens than expected due to front-running. This approach is also more accurate because there is no dust residue in the calculation this way.

> NOTE: When a user is purchasing the tokens, they must buy a minimum amount that is calculated for them. This is needed so that we don't get the amount out as 0 due to the calculation in `getPrice()` function where:
```
cost = targetRaise * (newSupply^2 / saleSupply^2)
```
> I had to ensure that `targetRaise * newSupply^2` > `saleSupply^2`. This was a simple fix but not the best one, considering the time I had to do this. 

## Claiming Purchased Tokens
Once the sale is finalized, users must call claim(address recipient)` to receive their purchased tokens. Instead of giving users the tokens right away we use this method in order to safeguard the protocol from token dumping and premature market creation.

* We check `purchases[msg.sender]` to see how many tokens the user has purchased.
* If the sale is finalized, we transfer that token amount out to the specified recipient.
* This design requires an explicit claim so that tokens are only released after the sale is confirmed to be complete. This avoids distributing tokens prematurely, giving the launchpad contract direct control over the supply until finalization.

## Upgradeable Pattern (UUPS)
Used the namespaced storage pattern to ensure there is absolutely no chance of storage collisions.

## Deployments
Launchpad: https://sepolia.etherscan.io/address/0xA576805A32ff1D2f157d91C5E01Aad6eaFc5DcbF

