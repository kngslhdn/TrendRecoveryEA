# Exit Engine

## Objective

Protect realized and floating campaign profit while ensuring every campaign has deterministic exit conditions.

## Exit hierarchy

1. Hard equity protection
2. Daily loss protection
3. Campaign maximum loss
4. Recovery maximum loss
5. Campaign timeout
6. Recovery basket target
7. Profit target / profit lock
8. Trailing exit from the campaign profit peak

## Important behavior

- Exit management must remain active 24/7.
- Trading session controls new entries only.
- A close request must block new entries until all EA positions are confirmed closed.
- Profit trailing must never move the protected level backwards.
- Recovery must not be allowed to create an unlimited averaging loop.
- On a strong reversal, the EA must either execute the controlled recovery path or close the campaign when recovery is unavailable.

## Integration rule

`modules/ExitEngine.mqh` contains pure exit-state helpers. The main EA remains responsible for collecting live position data and executing `CTrade` close requests.

This separation keeps exit calculations testable and prevents execution code from being duplicated across the EA.
