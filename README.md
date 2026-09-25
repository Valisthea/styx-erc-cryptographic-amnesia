# ERC-8228: Cryptographic Amnesia

**Canonical proposal:** [ethereum/ERCs#1681](https://github.com/ethereum/ERCs/pull/1681) · **Discussion:** [Ethereum Magicians](https://ethereum-magicians.org/t/erc-8228-cryptographic-amnesia/28215)

The authoritative text is the one in the pull request; this repository is a working mirror.

> Provable, irreversible encryption key destruction on append-only ledgers.

**Status:** Draft
**Author:** [@Valisthea](https://github.com/Valisthea)
**Created:** 2026-04-17
**Requires:** ERC-165

---

## Abstract

The first standard to enable a credible **right to be forgotten** on an immutable blockchain.

This standard defines a **destruction ceremony** protocol: a master decryption key, split via Shamir Secret Sharing across independent custodians, is provably destroyed share by share. Each destruction is attested by a ZK proof. A VDF time-lock prevents coerced destruction. Once complete, encrypted on-chain data becomes permanent noise.

## Ceremony Lifecycle

```
IDLE → PENDING (VDF countdown) → ACTIVE (accepting proofs) → COMPLETED (amnesia)
                                                            → FAILED (timeout / vetoed / cancelled)
```

The PENDING→ACTIVE transition is **implicit** — no transaction needed. It occurs automatically when `block.timestamp >= vdfUnlockTime`.

## Key Innovation

| Property | Traditional Blockchain | With This Standard |
|---|---|---|
| Data persistence | Forever | Provably forgettable |
| GDPR compliance | Impossible | Achievable |
| Key compromise recovery | None | Proactive destruction |
| Governance privacy | Permanent record | Votes forgotten after tally |
| Sealed auctions | Bids recoverable forever | Bids permanently sealed |

## Core Interface

```solidity
interface IERC8228 {
    // Session setup
    function createSession(bytes32 sessionId, address[] calldata custodians, uint256 k, bool forgoable) external;

    // Ceremony lifecycle
    function initiateOblivion(bytes32 sessionId) external returns (uint256 vdfUnlockTime, uint256 deadline);
    function submitDestructionProof(bytes32 sessionId, uint256 custodianIndex, bytes calldata proof) external returns (bool ceremonyComplete);
    function cancelOblivion(bytes32 sessionId) external;
    function vetoCeremony(bytes32 sessionId, bytes calldata vetoProof) external;
    function abortExpiredCeremony(bytes32 sessionId) external;

    // Queries
    function isForgotten(bytes32 sessionId) external view returns (bool);
    function isForgoable(bytes32 sessionId) external view returns (bool);
    function ceremonyInfo(bytes32 sessionId) external view returns (CeremonyInfo memory);
    function isCustodian(bytes32 sessionId, address account) external view returns (bool);
    function custodianAddress(bytes32 sessionId, uint256 index) external view returns (address);

    // Rate limiting
    function ceremonyCooldown() external view returns (uint256);
    function ceremonyAttemptCount(bytes32 sessionId) external view returns (uint256);
    function maxCeremonyAttempts() external view returns (uint256);

    // Events
    event SessionCreated(bytes32 indexed sessionId, address[] custodians, uint256 k, bool forgoable);
    event OblivionInitiated(bytes32 indexed sessionId, address indexed initiator, uint256 vdfUnlockTime, uint256 deadline);
    event ShareDestroyed(bytes32 indexed sessionId, uint256 indexed custodianIndex, bytes32 proofHash, uint256 proofsTotal, uint256 thresholdNeeded);
    event AmnesiaAchieved(bytes32 indexed sessionId, uint256 completedAt);
    event OblivionFailed(bytes32 indexed sessionId, FailureReason reason);
    event OblivionCancelled(bytes32 indexed sessionId, address indexed cancelledBy);
    event OblivionVetoed(bytes32 indexed sessionId, address indexed vetoedBy);
}
```

## Extensions

- **Compliance** (`IERC8228_Compliance`) — `complianceReceipt()`, `dataCategory()`, `retentionPeriod()` for regulated environments
- **Hooks** (`IERC8228_Hooks`) — `onAmnesiaAchieved()` callback for dependent contracts, called AFTER state transition with 50,000 gas stipend

## Repository Structure

```
styx-erc-cryptographic-amnesia/
├── eip/
│   └── eip-yyyy.md                    # Official EIP draft
├── contracts/
│   └── interfaces/
│       ├── IERC8228.sol               # Core interface
│       ├── IERC8228_Compliance.sol    # Compliance extension
│       └── IERC8228_Hooks.sol        # Hook callback interface
├── docs/
│   └── ceremony-lifecycle.md          # Lifecycle diagram
├── test/
│   └── .gitkeep
└── SECURITY.md
```

## Part of STYX Protocol

This is Layer 3 (Oblivion) of STYX Protocol:

| Layer | Codename | ERC |
|---|---|---|
| L1 | Veil | [ERC-1680](https://github.com/Valisthea/styx-erc-encrypted-token) — Encrypted Token Interface |
| L2 | Prism | ZK Recursive Verification (planned) |
| **L3** | **Oblivion** | **This standard** |

## License

[CC0-1.0](./LICENSE)

---

**Kairos Lab** · Security Research & Infrastructure
[@Valisthea](https://github.com/Valisthea)
