# Cyfrin Advanced Foundry Cross-chain Rebase Token

This is a section of the [Cyfrin Foundry Solidity Course](https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#advanced-foundry-section-4-foundry-cross-chain-rebase-token).

1. A protocol that allows users to deposit into a vault and in return, receive rebase tokens that represent their underlying balance.
2. Rebase token -> `balanceOf` function is dynamic to show the changing balance over time.
    1. Balance increases linearly over time.
    2. Mint tokens to our users every time every time they perform an action (mint, burn, transfer, bridge).
3. Interest rate
    1. Individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault.
    2. This global interest rate can only decrease to incetivise/reward early adopters.

![alt text](img/protocol.png)
