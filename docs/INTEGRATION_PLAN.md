# TrendRecoveryEA Integration Plan

## Current baseline

`TrendRecoveryEA.mq5` remains the compile-safe baseline. The new modules are currently isolated from the production entry/management flow.

## Integration order

1. Include `ExitEngine.mqh` in the main EA.
2. Replace duplicated campaign exit checks with one exit decision path.
3. Include `RecoveryEngine.mqh` and move recovery state tracking into the module.
4. Add persistent state restoration for recovery/exit snapshots.
5. Compile in MetaEditor and verify zero errors/warnings.
6. Backtest before changing strategy parameters.

## Safety rule

Do not enable a new exit or recovery path merely by including the module. Every new path must be explicitly called from `OnTick()` and must preserve the existing hard equity and daily-loss protections.

## Exit priority

1. Hard equity drawdown
2. Daily loss protection
3. Campaign maximum loss
4. Recovery maximum loss
5. Campaign timeout
6. Recovery target/trailing exit
7. Profit protection
8. Normal trend management

## Recovery rule

Recovery is a controlled exit mechanism, not unlimited averaging. It must remain bounded by maximum recovery positions, maximum recovery lot, campaign loss, recovery loss and equity protection.
