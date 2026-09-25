# Ceremony Lifecycle

Complete state machine for the ERC-8228 Cryptographic Amnesia ceremony.

## State Diagram

```
    ┌─────────┐     VDF delay      ┌───────────┐
    │  IDLE   │ ──────────────────► │  PENDING  │
    └─────────┘  initiateOblivion() └───────────┘
                                         │
                              block.timestamp >= vdfUnlockTime
                              (implicit — no transaction needed)
                                         │
                                         ▼
                                   ┌───────────┐
                                   │  ACTIVE   │ ◄─── submitDestructionProof()
                                   └───────────┘      (one per custodian)
                                         │
                              threshold reached (n-k+1 proofs)
                                         │
                                         ▼
                                   ┌───────────┐
                                   │ COMPLETED │  ← Amnesia achieved
                                   └───────────┘
                                   (hooks called AFTER transition,
                                    50,000 gas stipend each)

    ─────────────────────────────────────────────────────────────

    Before COMPLETED — early termination paths:

    ┌──────────┐  cancelOblivion()  ┌───────────┐
    │ PENDING  │ ──────────────────►│           │
    │    or    │  vetoCeremony()    │  FAILED   │
    │  ACTIVE  │ ──────────────────►│           │
    └──────────┘  deadline elapsed  └───────────┘
                  maxAttempts reached      │
                                           ▼
                                    (keys NOT destroyed)
                                    (new ceremony possible
                                     after ceremonyCooldown())
```

## State Descriptions

| State | Description | Entry | Exit |
|---|---|---|---|
| `IDLE` | No ceremony in progress | Initial / after FAILED | `initiateOblivion()` |
| `PENDING` | VDF time-lock counting down | `initiateOblivion()` | Implicit when `block.timestamp >= vdfUnlockTime` |
| `ACTIVE` | Accepting destruction proofs | Implicit (no tx needed) | Threshold reached → COMPLETED; deadline → FAILED |
| `COMPLETED` | Amnesia achieved, permanent | Threshold of proofs submitted | Never — irreversible |
| `FAILED` | Ceremony aborted | Timeout / cancel / veto / max attempts | `initiateOblivion()` after cooldown |

## Key Transition Notes

### PENDING → ACTIVE (implicit)

The transition from PENDING to ACTIVE is **implicit** — no transaction is required.
It takes effect automatically when `block.timestamp >= vdfUnlockTime`.

Callers MUST check `vdfUnlockTime` directly rather than relying on the stored `state` field,
which may still read as `PENDING` even when the effective state is `ACTIVE`.

```solidity
// Correct: check vdfUnlockTime
bool isEffectivelyActive = (
    info.state == CeremonyState.PENDING &&
    block.timestamp >= info.vdfUnlockTime
) || info.state == CeremonyState.ACTIVE;

// Incorrect: relying only on stored state
bool isActive = info.state == CeremonyState.ACTIVE; // may miss implicit ACTIVE
```

### COMPLETED (irreversible)

Once `isForgotten(sessionId)` returns `true`, it MUST never return `false`.
Amnesia is a one-way function. No function call, upgrade, or governance action
can reverse a completed ceremony.

### FAILED (retriable with limits)

After a FAILED ceremony:
- A cooldown of `ceremonyCooldown()` seconds MUST elapse before retry
- Each retry increments `ceremonyAttemptCount(sessionId)`
- When `ceremonyAttemptCount() >= maxCeremonyAttempts()`, no further ceremonies can be initiated

## Failure Reasons

| `FailureReason` | Cause | Retriable? |
|---|---|---|
| `TIMEOUT` | Deadline elapsed with insufficient proofs | Yes (after cooldown) |
| `INSUFFICIENT_PROOFS` | Not enough custodians participated | Yes (after cooldown) |
| `VETOED` | Authorized veto during PENDING phase | Yes (after cooldown) |
| `CANCELLED` | Initiator cancelled | Yes (after cooldown) |
| `MAX_ATTEMPTS` | Session exhausted maximum attempts | No |

## Hook Execution

When a ceremony reaches COMPLETED, registered hooks are called:

1. State transitions to COMPLETED
2. `AmnesiaAchieved` event emitted
3. For each registered hook contract: `onAmnesiaAchieved(sessionId)` called with **50,000 gas stipend**
4. Hook reverts do NOT revert the ceremony — amnesia is already achieved
5. Hook failures are logged for observability

Register/remove hooks via:
```solidity
IERC8228.registerAmnesiaHook(sessionId, hookContract);
IERC8228.removeAmnesiaHook(sessionId, hookContract);
```
