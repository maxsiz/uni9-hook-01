# Uniswap V4 Hook — Delta-neutral Rebalancing

## Sequence Diagram

```mermaid
sequenceDiagram
    participant EOA
    participant SW as SmartWallet<br/>(+ Hook option A)
    participant MP as Main Pool<br/>(ETH/USDT)
    participant SP as Signal Pool<br/>(ETH/USDT)
    participant HK as Hook<br/>(option B)
    participant TM as ThresholdModule
    participant UD as Uniswap dApp

    %% ── SETUP PHASE ──
    rect rgb(240, 240, 240)
        Note over EOA,UD: Setup phase

        EOA->>SW: owns SmartWallet
        SW->>MP: mint LP position (main range)
        EOA->>SP: create SignalPool + attach Hook
        EOA->>SP: mint small position (SignalPool)
        Note over SP,HK: ThresholdModule initialized<br/>(delta%, TWAP window, cooldown)
    end

    %% ── PRICE DRIFT ──
    rect rgb(240, 240, 240)
        Note over EOA,UD: Price drift — out-of-range

        UD->>MP: heavy swap volume
        MP->>MP: price exits LP range
        Note over SW,MP: LP fees stop accruing<br/>Rebalancing required
    end

    %% ── SIGNAL DETECTION ──
    rect rgb(240, 240, 240)
        Note over EOA,UD: Signal detection

        Note over UD: price gap detected<br/>between MainPool and SignalPool<br/>→ route swap to SignalPool
        UD->>SP: swap (signal trigger)
        SP->>HK: afterSwap() callback
    end

    %% ── HOOK INTERNALS ──
    rect rgb(240, 240, 240)
        Note over EOA,UD: Hook internals — threshold check + flash accounting batch

        HK->>TM: checkCondition()
        Note over TM: compares:<br/>MainPool price vs SignalPool price<br/>checks delta% >= threshold<br/>checks cooldown elapsed

        TM-->>HK: [condition met]

        Note over SW,SP: flash accounting batch — single tx, atomic

        HK->>SW: 1. burn old MainPool position
        SW->>MP: 2. swap to rebalance token ratio
        SW->>MP: 3. mint new MainPool range
        HK-->>SP: 4. rebalance SignalPool [if needed]

        Note over SW,MP: net token settlement only<br/>(flash accounting)

        HK-->>SW: batch complete — balances settled
        HK-->>EOA: emit RebalanceExecuted(newRange, txHash)
    end
```

---

## Architecture Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A** | SmartWallet + Hook as single contract | No trust issue, simpler auth, smaller attack surface | Less modular, harder to upgrade Hook independently |
| **B** | Hook as separate contract | Modular, upgradeable Hook | SmartWallet must grant allowance to Hook address |

---

## ThresholdModule Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `delta%` | Min price gap between MainPool and SignalPool | 0.5% |
| `twapWindow` | TWAP averaging window (manipulation protection) | 1800s (30 min) |
| `cooldown` | Min interval between rebalances | 3600s (1 hour) |

---

## Flash Accounting Batch (single atomic tx)

```
1. burn old MainPool position
2. swap to rebalance token ratio
3. mint new MainPool range (new tick range)
4. rebalance SignalPool [optional, if needed]
── net token settlement (flash accounting) ──
```

---

## Key Contracts

- **SmartWallet** — holds LP position in MainPool, trusted by Hook (Option A: merged, Option B: grants allowance)
- **SignalPool** — ETH/USDT pool with small liquidity, Hook attached, acts as price sensor
- **Hook** — implements `afterSwap()`, calls ThresholdModule, initiates rebalancing batch
- **ThresholdModule** — configurable module with rebalancing conditions (delta%, TWAP, cooldown)