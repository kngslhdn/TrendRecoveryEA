# TrendRecoveryEA v1.28 — Optimization A

## Baseline

Backtest supplied for v1.28:
- Net Profit: +564.82
- Profit Factor: 1.18
- Equity Drawdown: 10.16%
- Win Rate: 77.48%
- Average winning trade: +6.61
- Average losing trade: -19.34

## Optimization target

The priority is **not** to increase entry frequency or lot size. The priority is to reduce false recovery and reduce the size/frequency of avoidable losses while preserving the existing trend-entry engine.

## Changes

| Parameter | v1.28 | OPT-A | Reason |
|---|---:|---:|---|
| RecoveryTriggerUSD | 5.0 | 8.0 | Avoid triggering recovery on normal XAUUSD retracements |
| RecoveryConfirmationBars | 3 | 4 | Require stronger reversal confirmation |
| RecoverySL_ATR | 1.50 | 1.75 | Give confirmed recovery more room |
| RecoveryMaxLossPerTradeUSD | 8.0 | 6.0 | Hard-cap recovery loss lower |
| ProfitLockStartUSD | 12.0 | 10.0 | Lock profitable positions earlier |
| ATRTrailingStartUSD | 15.0 | 12.0 | Protect larger open profit earlier |
| InitialLot | 0.01 | 0.01 | No leverage increase |
| RecoveryMultiplier | 1.0 | 1.0 | No martingale increase |
| MaxRecoveryPositions | 1 | 1 | Keep recovery exposure capped |

## Backtest protocol

Run the exact same test conditions as the baseline:
- Symbol: XAUUSDm
- Timeframe: M15
- Period: 2026.01.01–2026.08.05
- Same deposit and broker/tester conditions
- Prefer 100% real ticks

## Pass criteria

OPT-A is considered an improvement only if it materially improves Profit Factor and/or average loss **without pushing maximum equity drawdown materially above the 10.16% baseline**.

Do not change entry logic, lot size, or recovery multiplier during this comparison.
