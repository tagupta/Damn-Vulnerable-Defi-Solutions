# Solving the Flash Loan Challenge – My Journey

1. I figured out that the `flashLoan` function need to let the player take the funds out, but without actually withdrawing them until the function completes.
2. So, I added a low-level call `approve(player)` as the data parameter of `flashLoan` function.
3. Then, in the next step, the player should be able to transfer funds from the pool to the recovery address. Sweet!
4. I knew this is this soltuion.
5. The Next hurdle: how to make the player's nonce change to 1.
6. At first, I tried pranking/broadcasting as the **player** explicitly again, but the nonce stubbornly stayed at 0. I thought maybe I could just set it manually to pass the test.
7. But nope — that’s not how this stuff works.
8. I peeked a bit at the solution and saw that it used a single transaction, even though I was sure it needed two. The trick? Create a **new contract**. That honestly never occurred to me — I thought I could only work inside the test function. Turns out I was wrong.
9. So, I copy-pasted all the logic from the test case into the constructor of the new contract.

10. Ran the code — and boom, the nonce finally changed to 1. Felt like a win.
11. But then... `transferFrom()` started failing. What the heck?
12. Another lightbulb moment: the **new contract** needed approval, not the player. Of course! It's the contract that's calling `transferFrom()`, not the original sender.
13. And just like that — another challenge down. 😎
