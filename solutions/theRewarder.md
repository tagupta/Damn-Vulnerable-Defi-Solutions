# Solving The Rewarder Challenge – My Journey

This challenge proved to be particularly intriguing, requiring multiple attempts before identifying the core vulnerability. Here's my systematic exploration:

## Initial Attempts (That didn't work)

1. ### Batch Number Manipulation

   Tried to see if it is possible to set `batchnumber` to any random value. No hope.

2. ### Merkle Tree Tampering:

   Then I thought maybe if I could make some modifications in the tree leaves, i might be able to bypass the proofs. No where close. That's now how merkle proofs work with the given root.

3. ### New Distribution Creation:
   What if I try to create a new distribution, would it help me in any way? Nope. This will revert even if I try to.

```solidity
if (distributions[token].remaining != 0) revert StillDistributing();
```

## Narrowing the Attack Surface

After eliminating other options, I focused on `claimRewards` as the only viable function, but faced with other new constraints:

1. Sender Restriction:
   - Attempted to see if other beneficiaries can call the `claimRewards` function while `msg.sender` value remains the **player** address.
   - Nope the above approach can't work, as `claimRewards` is computing leaf using `msg.sender` value strictly.
   - Hence, making impersonation attempts fail the proof verification.

```solidity
bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
```

2. Single Claim Limitation: Attempted to claim multiple times via mutiple calls failed due to the anti-replay protection.

## The Breakthrough

This was the only code left to exploit:

```solidity
   if (token != inputTokens[inputClaim.tokenIndex]) {
       if (address(token) != address(0)) {
           if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
       }

       token = inputTokens[inputClaim.tokenIndex];
       bitsSet = 1 << bitPosition; // set bit at given position
       amount = inputClaim.amount;
   } else {
       bitsSet = bitsSet | 1 << bitPosition;
       amount += inputClaim.amount;
   }
```

```solidity
if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
```

- What if I can falsify this above condition, something can be done about this. Right? I just need to make sure `_setClaimed` must returns `true`.
- What if I don't let these value change `wordPosition, bitsSet` and try to claim the same token mutiple times, would it work? Indeed it did.
- Similarly, can I try to claim other token more than once? Yes, I can.
- Okay, at this point everything made sense. Player can claim mutiple tokens mutiple times in a single call.
- Now next thing to figure out is how many times to run the loop for each token.
- Seemed easy.
  - Player amount of DVT tokens to claim = `11524763827831882`
  - Distributor remaining balance = `TOTAL_DVT_DISTRIBUTION_AMOUNT - ALICE_DVT_CLAIM_AMOUNT`
  - Dust of DVT tokens to leave behind = `1e16`
  - So, the no. of times player can claim DVT tokens = `(TOTAL_DVT_DISTRIBUTION_AMOUNT - ALICE_DVT_CLAIM_AMOUNT - 1e16) / 11524763827831882 = 866.6119431873`
  - So I ran the loop for DVT tokens for 866 times. Similarly, I ran the loop for WETH for 853 times. Hence the `inputClaims` array length is 1720.

Then transferred all the tokens to recovery address. Then it's DONE.
