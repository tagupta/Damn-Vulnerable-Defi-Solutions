# Meta-Transaction Attack: Impersonating Deployer via Multicall

## Approach I used to solve this Challenge

### Overview

This document analyzes a successful attack where I was able to call the `withdraw()` function while impersonating the deployer address, despite the transaction being sent through a trusted forwarder that appends the real sender's address.

### The Attack Construction : Draining `NaiveReceiverPool` via `_msgSender()` Spoofing

1. Vulnerability Overview

   - The `NaiveReceiverPool` contract contains a critical vulnerability in its withdraw function due to:

     - Enabling users to take flash loans of `amount 0` and by not having any check over the caller of the `flashLoan` function.
     - Trust in `_msgSender()`: Relies on `msg.data`.
     - Improper Calldata Validation: Allows arbitrary data injection in `msg.data`.

   - By crafting a malicious `msg.data`, player can:
     - Manipulate `_msgSender()` to return a privileged address (`deployer`).
     - **Bypass deposit checks** to withdraw funds illegitimately.

2. Attack Steps

   - Draining the Receiver Contract
     - The player repeatedly calls `flashLoan(amount = 0)` **10 times**, forcing the `receiver` to pay a 1 WETH fee per call.
     - This moves **10 WETH** from the `receiver` to the pool’s `feeReceiver` balance (increasing the pool’s total funds).
   - Spoofing the Deployer to Withdraw
     - The attacker crafts a malicious payload to trick `_msgSender()` into returning the deployer address during a `withdraw()` call.
     - By manipulating `msg.data`, the attacker bypasses authorization checks, allowing them to **withdraw the pool’s entire balance** (including the 10 WETH fees) to the `recovery` address.

3. Data flow analysis

- Forwarder processing:

  - Input to forwarder:
    - request.data = `[multicall_function_call_with_calldatas]`
    - request.from = attackerAddress (20 bytes)
  - Forwarder creates:
    - payload = [multicall_function_call_with_calldatas][attackerAddress]

- Multicall Execution

  - Multicall receives msg.data => [multicall_function_call_with_calldatas][attackerAddress]
  - Mutlicall extract from calldata[0 - 9] => [flash_loan_call] \* 10 times
  - Multicall extracts from calldatas[10] => [withdraw_call][deployer] (88 bytes)
  - DelegateCall to `withdraw()` with: `msg.data` => [withdraw_call][deployer]

- Withdraw function Execution
  - `withdraw()` receives msg.data => [function_selector][amount][receiver][deployer]
  - `_msgSender()` extracts last 20 bytes => `msg.data[msg.data.length - 20:]` = deployer address

4. The critical misunderstanding

- Initial confusion:
  I initially couldn't understand why `_msgSender()` was returning the `deployer` address instead of the `player` address, despite the forwarder appending `request.from` (player address) to the payload.

- Key Insight: Multiple msg.data Contexts
  The confusion arose from not understanding that **each function call creates its own `msg.data` context**:
  1. **Forwarder's msg.data**: Contains the original transaction data
  2. **Multicall's msg.data**: Contains multicall function call + appended player address
  3. **Withdraw's msg.data**: Contains individual withdraw call + appended deployer address
- Why request.from Doesn't Affect withdraw()
  - Forwarder appends request.from to the ENTIRE multicall payload:
    [multicall_call][attacker_address] → sent to multicall()
  - Multicall processes individual calldatas via delegateCall:
    [withdraw_call][deployer] → becomes msg.data for withdraw()
  - The attacker_address appended by forwarder is NOT passed to withdraw()!

### Conclusion:

The attack succeeded because the forwarder's security mechanism (appending request.from) only applies to the direct target of the forwarder call. When using multicall as an intermediary, the individual function calls within the batch can have their own crafted msg.data, allowing for address impersonation.
