# Solving the Selfie – My Journey

## Overview

This challenge was deceptively simple once I connected the dots. Here's how I pulled it off:

1. Since the pool only lends to `IERC3156FlashBorrower`-compatible contracts,

   - I built a receiver contract to request the loan.
   - Made sure onFlashLoan would return the borrowed tokens (to avoid reverts).
   - And do the real work in between.

2. Next step was to figure out what to write inside `onFlashLoan` such that all the transferred tokens will be tranferred back to pool as it is.
   - Borrowed a ton of tokens via flashloan.
   - Delegated them to my contract (temporary voting power).
   - Queued a malicious action to drain the pool:

```solidity
bytes memory functionCall = abi.encodeCall(SelfiePool.emergencyExit, (i_recover));
SimpleGovernance(i_governance).queueAction(i_pool, 0, functionCall);
```

3. Time travel and execution:
   - Fast-forwarded past the governance delay
   - Executed the action

```solidity
vm.warp(block.timestamp + governance.getActionDelay());
governance.executeAction(actionId);
```

4. That's how, it's **DONE**.
