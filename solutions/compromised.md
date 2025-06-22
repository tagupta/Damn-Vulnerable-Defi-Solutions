# Solving "The Compromised" - My Journey 🕵️‍♂️

## Thoughts

- This challenge taught me that solving CTFs is like detective work - you need to pay attention to every tiny detail, even the stuff that seems completely irrelevant. Those encoded strings looked like gibberish at first, but they were literally the keys to the kingdom.

- Also, oracle manipulation attacks are no joke in the real world. This challenge was a great reminder of why decentralized oracles and proper security measures are so important

## Steps I followed

- The whole thing started when I looked at the `Exchange` contract and thought "hmm, these `buyOne` and `sellOne` functions look pretty solid." No obvious bugs, no weird edge cases jumping out at me.
- Here's where it hit me - I need to buy this **NFT**, but it costs `999 ETH`. Like, as a player I've not been given this much of money? But I do have `0.1 Ether` lying around.
- So I'm sitting there, scratching my head, when it clicks: What if I could mess with the **price**?
- I realized the only way to change the price was through the oracle system. But here's the kicker - it's using a median of 3 sources, which means _I need to compromise at least 2 oracles_.
- At this point I knew, I've cracked the logic. But now I need to somehow get private keys for these oracles which was tricky.
- I read the challenge/contracts again and again to see what am I missing.
- And there they were, just staring at me: **two weird encoded strings**.

```text
Wait a minute... I need 2 oracles compromised... there are 2 encoded strings... Could it be?
```

- This part was honestly the most time consuming. I tried everything:
  - Direct hex decoding ❌
  - Base64 first ❌
  - ASCII conversion ❌
  - Random combinations that made no sense ❌
- After probably 3 hours of trial and error, I finally cracked it:

```text
Hex → ASCII → Base64 → BOOM! Private keys!
```

```solidity
function keySearch(bytes memory key) internal view returns (bytes memory base64Decoded) {
        string memory hexBytes = string(key);

        base64Decoded = Base64.decode(hexBytes);//private key

        // Derive address
        address derivedAddr = vm.addr(vm.parseUint(string(base64Decoded)));
        //get the address and return its respective key if derived address matches the any three of the oracle addresses
        for(uint i = 0 ; i < sources.length; ){
            if(derivedAddr == sources[i]){
                return base64Decoded;
            }
            unchecked {
                i++;
            }
        }
    }
```

- Once I had those private keys, it was game over:
  - Step 1: Use the compromised oracles to tank the NFT price
  - Step 2: Buy the NFT for basically nothing like 0
  - Step 3: Bump the price back up to `999 Ether`
  - Step 4: Sell it back to the exchange for full price
  - Step 5: Profit! 💰

## What I Learned

### _The Technical Stuff_

- Oracle manipulation is scary powerful when you control enough sources
- Never ignore weird strings in challenge descriptions - they're usually there for a reason
- Sometimes the solution requires multiple decoding steps (who knew?)

### _The Life Lessons_

- When stuck, re-read everything. Then re-read it again.
- Those "random" details in challenges? They're never actually random.
- Persistence beats intelligence sometimes
