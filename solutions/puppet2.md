# Solving the Puppet 2 – My Journey

## My Thoughts

Another challenge conquered! Here's the thing about this particular challenge – though the solution is straightforward, I found myself nearly tumbling down a rabbit hole of overthinking and getting lost in the complexity of the code. The key lesson? Trust your instincts and follow that hunch. Otherwise, you'll find yourself trapped in code for hours.

## Steps to solve:

1. I saw I needed to manipulate the token reserves to control how much WETH was required to borrow those DVT tokens. The path seemed clear enough.
2. Here's where things got interesting – simply transferring tokens to the pair contract wouldn't actually manipulate the reserves.
3. After digging through the `UniswapV2Pair` contract, I discovered that the `swap` function was my ticket to manipulating those reserves.
4. Based on the `quote` calculation, I needed to reduce WETH from the reserve while increasing the quantity of DVT tokens.

   ```solidity
   function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
           require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
           require(reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
           amountB = amountA * reserveB / reserveA;
       }
   ```

5. This is where things got weird. The `swap` function asks users to specify **how much of either token they want to extract**. I initially thought I'd need complex function calls to calculate the exact WETH amount to extract.
   - But here's the light – that's exactly where Uniswap missed a crucial security check.
6. Turns out, you can extract any amount from the pool as long as you don't completely drain the reserves. The system then calculates reserve values based on whatever **tokens remain in the contract**.
7. So they are calculating the reserves amount based off the contract balance. Nice!!
8. Before making my move, I transferred all the DVT tokens I owned as a user. This was my setup phase.
9. Since I needed exactly `29702970297029702970 WETH` to borrow all pool tokens, I executed a swap of `9.9 WETH and 0 DVT`. This boosted my WETH balance to exactly `29.9e18` – perfect!
10. All that remained was approving the `lending pool` for the WETH token and transferring those borrowed DVT tokens to the recovery address. Challenge complete!

## Key Takeaway

Sometimes the most elegant solutions come from understanding the system's assumptions rather than fighting against its complexity. This challenge reminded me that security vulnerabilities often hide in plain sight.
