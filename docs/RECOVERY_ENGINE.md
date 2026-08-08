# Recovery Engine

## Objective

Recovery is an exception path, not a second entry strategy. It activates only after the original trend position is materially negative and a confirmed opposite trend exists.

## Safety rules

1. Recovery is limited by `MaxRecoveryPositions`.
2. Recovery volume is capped by `MaxRecoveryLot`.
3. Recovery must be disabled on non-hedging accounts when the EA requires hedging.
4. The complete campaign remains subject to equity DD, daily loss, campaign loss and campaign timeout protection.
5. A recovery basket has both a profit target and a maximum-loss exit.
6. A recovered positive basket can optionally use a basket trailing exit to protect recovered profit.
7. Recovery must never create an unlimited averaging loop.

## State flow

```text
TREND POSITION
      |
      | normal position loss >= RecoveryTriggerUSD
      v
REVERSAL CONFIRMED
      |
      +---- no recovery available ----> EXIT
      |
      v
RECOVERY POSITION
      |
      +---- basket target -----------> EXIT
      |
      +---- max loss ----------------> EXIT
      |
      +---- recovered profit trail --> EXIT
      |
      v
NEW CAMPAIGN
```

## Implementation

`modules/RecoveryEngine.mqh` contains the reusable recovery state manager. The production EA remains responsible for broker execution, position enumeration and hard risk controls.
