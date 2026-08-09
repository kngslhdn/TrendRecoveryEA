# Recovery Engine v1.28

## Baseline
`TrendRecoveryEA.mq5` v1.27 is preserved unchanged as the baseline.

## New EA
Use `TrendRecoveryEA_v1.28.mq5` for the v1.28 backtest.

The v1.28 wrapper includes the v1.27 core and replaces only the Recovery/position/tick management path. Entry logic, trend detection, reversal confirmation, initial SL, equity protection and the one-recovery-per-campaign rule remain unchanged.

## Recovery changes

1. **Recovery P/L is separated from Normal P/L.**
   - `RecoveryProfit_v128()` calculates only positions tagged `RECOVERY`.
   - Recovery exits no longer use the raw `BasketProfit()` as the recovery target trigger.

2. **RecoveryTargetUSD is now a campaign-result gate.**
   - Recovery must reach `RecoveryTargetUSD`.
   - Total campaign P/L must also reach `RecoveryMinProfitUSD`.
   - Example: recovery +$1 while original -$5 no longer closes the campaign at -$4.

3. **Recovery hard-loss logic is recovery-leg specific.**
   - `RecoveryMaxLossUSD` is checked against recovery P/L only.
   - The existing `RecoveryMaxLossPerTradeUSD` remains the entry SL/risk cap.

4. **Recovery profit lock.**
   - Default start: `$2`.
   - Default locked profit: `$1`.

5. **Recovery profit trailing.**
   - Default trail activation: `$5`.
   - Default giveback: `$2`.
   - This lets strong recovery winners continue instead of being closed immediately at `$1`.

6. **Recovery attempt limit remains unchanged.**
   - One recovery attempt per campaign.
   - No averaging/recovery loop is introduced.

## Default v1.28 recovery parameters

| Parameter | Default |
|---|---:|
| RecoveryTriggerUSD | 5.0 |
| RecoveryMaxLossPerTradeUSD | 8.0 |
| RecoveryTargetUSD | 1.0 |
| RecoveryMinProfitUSD | 0.0 |
| RecoveryLockStartUSD | 2.0 |
| RecoveryLockProfitUSD | 1.0 |
| RecoveryTrailStartUSD | 5.0 |
| RecoveryTrailGivebackUSD | 2.0 |

## Backtest

Run the same v1.27 test conditions first so the result is directly comparable. Do not optimize entry parameters yet. The objective of v1.28 is specifically to determine whether Recovery Exit improves net recovery contribution while keeping drawdown controlled.
