# `RewardHook` Implementation

The reward tracking and distribution system in the `RewardHook` contract tracks rewards for users based on their share of liabilities borrowed. Rewards are streamed over a defined duration, and for each reward token, the system tracks:

- **Emission rate**
- **Last update time**
- **Period end time**
- **Accumulated reward per unit of total liability**

When a user borrows or repays, the contract updates both the **global** and **user-specific** reward state using the `beforeBorrow` and `beforeRepay` hooks. These hooks trigger an index calculation that:

1. **Divides total accrued rewards since the last update by total liability**
2. **Calculates how much of those rewards is due to the user** by:
   - Finding the difference between the **global reward index** and the user’s **personal reward index** (`userRewardPerLiabilityPaid`) for that reward token
   - Multiplying that difference by their **liability balance** (ideally the original borrow amount, rather than the total borrow with interest included)

---

## Broader Use of Hooks

Beyond rewards, these `before` and `after` hooks enable broader modularity in lending systems. They can be used to:

- Enforce safety checks (e.g. validating collateralization or supply caps before allowing an action)
- Track market usage
- Calculate or distribute rewards
- Revert actions if the protocol is paused

### `after` Hooks

The `after` hooks can be used to:

- Update accounting
- Emit events
- Trigger follow-up processes after state changes are finalized

### Data Flow Between Hooks

Data can be passed from a `before` hook to an `after` hook. This allows:

- The `after` hook to know the reward or liability state prior to the borrow operation
- Logic like:
  - Comparing the liability **before** and **after**
  - Detecting whether the user has **completely closed out their position** and removing the asset from their borrowed list
  - Taking actions such as **emitting an event**

---

## Summary

By using this lifecycle hook pattern (`before`/`after`), protocols can remain:

- **Flexible**
- **Modular**
