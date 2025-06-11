# Solving the Side Entrance Challenge – My Journey

## Overview

This challenge is both simple and fascinating, requiring multiple strategic calls to exploit the flash loan mechanism. Here's how I approached it:

1. **Key insight**: This is the line where all the magic is happenong:

```solidity
IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();
```

- The pool sends ETH to the receiver's contract via `execute()` while enforcing the `IFlashLoanEtherReceiver` interface.

2. Now they have just defined the interface with a `execute` function, rest of the story is for the player to figure out.

```solidity
function execute() external payable;
```

3. **Initial Observations**

   - **_Starting Balance_**: The player begins with 1 ETH.
   - This made me question why? Why the player needs to have balance in the account to call `flashLoan()`?
   - The receiver contract cannot directly call `flashLoan()` (not part of its interface).
   - Another thing, calling `flashLoan()` from `execute()` would create infinite recursion.
   - So, `flashLoan()` needs to be called from somewhere but not from `execute()`.

4. **The Breakthrough**
   - Flashloan should be called from the `receive()` directly, given the 1 ETH the player has.
5. Now I needed to do something inside execute which would change the balance of receiver contract in pool contract without removing the funds from pool contract. So I did this:

```solidity
 function execute() external payable {
    i_pool.deposit{value: msg.value}();
    (bool success,) = address(i_pool).call{value: msg.value}("");
    (success);
}
```

6.  But that's not the end. Now the receiver contract should be able to withdraw funds but if it does, the pool will call `receive()` function and hence the flashLoan causing the loop problem again. But wait, this won't be a problem, if I change the flow inside `receive()` based on who's sending money to receiver contract. Then I came up with this:

```solidity
 receive() external payable {
        if (msg.sender == i_owner) {
            i_pool.flashLoan(address(i_pool).balance);
            i_pool.withdraw();
        } else {
            (bool success,) = i_recoveryAddress.call{value: msg.value}("");
            (success);
        }
    }
```

7. Voila! this worked.
