## Approach I used to solve this Challenge

### 1. Understanding Flash Loans

Before diving into the problem, I looked into the core concepts of flashloan and associated ERC standards:

- Flash loans are uncollateralized loans that must be borrowed and repaid in the same transaction.
- Key standards:
  - ERC-3156: Standardizes flash loan interfaces [EIP-3156](URL "https://eips.ethereum.org/EIPS/eip-3156").
  - ERC-4626: Governs tokenized vaults (relevant for accounting).

### 2. Analyzing the Contracts

- Vault contract

  - Implements `IERC3156FlashLender`.
  - Allows flash loans only from the `monitorContract`.
  - Enforces the invariant:

    ```solidity
    if (convertToShares(totalSupply) != totalAssets()) revert InvalidBalance();
    ```

- Monitor contract
  - The sole caller of the `flashLoan()`.
  - Implements `IERC3156FlashBorrower`.
- Initial Observations:
  - Only the `monitorContract` can call `flashLoan`, limiting direct reentrancy attacks.
  - The vault uses ERC-4626-style accounting (`shares ↔ assets`).

### 3. Attempted Attack Vectors

a. Reentrancy Attack

- **Goal:** Drain funds by reentering `flashLoan` during repayment.
- **Problem:** The `initiator` must be the `monitorContract`, and the player cannot impersonate it.
  ```solidity
  if (initiator != address(monitorContract)) revert UnexpectedFlashLoan();
  ```

b. Inflation Attack

- **Goal:** Manipulate `totalShares` and `totalAssets` to mint `0 shares` for new deposits.
- **Problem:** The vault’s initial deposit is too large (`10^6 tokens`), and the player’s `10 tokens` are insufficient to skew the ratio meaningfully.

c. Breaking the Invariant

- **Key Insight:** The vault’s critical check
  ```solidity
  if (convertToShares(totalSupply) != totalAssets()) revert InvalidBalance();
  ```
  - This ensures shares and assets are always pegged 1:1.
- **Exploit:** Transfer tokens **directly to the vault** (bypassing `deposit`), which increases `totalAssets` without minting shares.
  - Steps:
  1. Transfer 10 tokens directly to the vault → totalAssets = 10M + 10 tokens, totalSupply = 10M
  2. Now
  ```solidity
  convertToShares(totalSupply) = 10M shares
  totalAssets() = 10M + 10 tokens
  ```
  The check fails, reverting `flashLoan`.

### 4. Why convertToShares(totalSupply) == totalAssets()?

Mathematical Explanation

- The formula for `convertToShares(assets)` is:
  ```solidity
  shares = (assets * totalSupply) / totalAssets;
  ```
- When you pass `totalSupply` as input:
  ```solidity
  convertToShares(totalSupply) = (totalSupply * totalSupply) / totalAssets;
  ```
- The invariant simplifies to:

```solidity
    (totalSupply²) / totalAssets == totalAssets
    → totalSupply² == totalAssets²
    → totalSupply == totalAssets
```

_This approach elegantly halts the vault without needing inflation or reentrancy! 🎯_
