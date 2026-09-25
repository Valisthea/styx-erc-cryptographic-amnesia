// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;

/// @title ERC-8228 Cryptographic Amnesia Interface
/// @author Valisthea (@Valisthea)
/// @notice Standard interface for provable, irreversible encryption
///         key destruction on append-only ledgers.

interface IERC8228 {

    // ─── Types ───────────────────────────────────────

    enum CeremonyState {
        IDLE,       // No ceremony in progress for this session
        PENDING,    // Ceremony initiated, VDF time-lock counting down
        ACTIVE,     // VDF elapsed, accepting destruction proofs
        COMPLETED,  // Threshold reached — amnesia achieved
        FAILED      // Timeout — insufficient proofs, ceremony aborted
    }

    /// @dev Encodes why a ceremony transitioned to FAILED.
    enum FailureReason {
        TIMEOUT,             // Ceremony deadline elapsed before threshold reached
        INSUFFICIENT_PROOFS, // Not enough custodians participated in time
        VETOED,              // Ceremony was blocked by an authorized veto
        CANCELLED,           // Ceremony was explicitly cancelled by the initiator
        MAX_ATTEMPTS         // Session has exhausted its maximum ceremony attempts
    }

    /// @notice Full ceremony state for a session.
    /// @dev    The PENDING→ACTIVE transition is implicit: it occurs automatically
    ///         when block.timestamp >= vdfUnlockTime. No explicit transaction is
    ///         required to enter ACTIVE — callers MUST check block.timestamp
    ///         against vdfUnlockTime to determine effective state.
    struct CeremonyInfo {
        bytes32 sessionId;             // Unique session identifier
        CeremonyState state;           // Stored state (PENDING may be effectively ACTIVE)
        uint256 initiatedAt;           // Block timestamp of initiation
        uint256 vdfUnlockTime;         // Timestamp at which ACTIVE begins (implicit transition)
        uint256 activeSince;           // Block timestamp of first proof accepted (0 if not yet)
        uint256 deadline;              // Timestamp after which ceremony fails
        uint256 totalCustodians;       // n in (k, n) Shamir scheme
        uint256 reconstructionThreshold; // k — minimum shares needed to reconstruct the key
        uint256 threshold;             // Destruction threshold: (n - k + 1) proofs needed
        uint256 proofsReceived;        // Destruction proofs submitted so far
        address initiator;             // Who started the ceremony
        uint256 attemptNumber;         // Which attempt this is (1-indexed, incremented on retry)
    }

    // ─── Custom Errors ───────────────────────────────

    error CeremonyNotIdle(bytes32 sessionId, CeremonyState currentState);
    error CeremonyNotActive(bytes32 sessionId, CeremonyState currentState);
    error VDFNotElapsed(bytes32 sessionId, uint256 remaining);
    error CeremonyExpired(bytes32 sessionId);
    error InvalidDestructionProof(bytes32 sessionId, uint256 custodianIndex);
    error CustodianAlreadyDestroyed(bytes32 sessionId, uint256 custodianIndex);
    error SessionNotForgoable(bytes32 sessionId);
    error InvalidCustodianIndex(uint256 index, uint256 max);
    error UnauthorizedInitiator(address caller);
    error CooldownNotElapsed(bytes32 sessionId, uint256 remaining);
    error MaxAttemptsReached(bytes32 sessionId, uint256 maxAttempts);

    // ─── Events ──────────────────────────────────────

    /// @notice Emitted when a new session is registered on-chain.
    /// @param sessionId   Unique identifier for the session.
    /// @param custodians  Array of custodian addresses (n custodians).
    /// @param k           Reconstruction threshold.
    /// @param forgoable   Whether this session is eligible for amnesia.
    event SessionCreated(
        bytes32 indexed sessionId,
        address[] custodians,
        uint256 k,
        bool forgoable
    );

    /// @notice Emitted when a destruction ceremony is initiated.
    /// @param sessionId      Unique identifier for the data session.
    /// @param initiator      Address that started the ceremony.
    /// @param vdfUnlockTime  Timestamp when ACTIVE state begins (implicit).
    /// @param deadline       Timestamp after which the ceremony fails.
    event OblivionInitiated(
        bytes32 indexed sessionId,
        address indexed initiator,
        uint256 vdfUnlockTime,
        uint256 deadline
    );

    /// @notice Emitted when a custodian proves participation in the ceremony.
    /// @param sessionId       Session being forgotten.
    /// @param custodianIndex  Index of the custodian (0-based).
    /// @param proofHash       Hash of the destruction proof.
    /// @param proofsTotal     Total proofs received so far.
    /// @param thresholdNeeded Number of proofs needed for completion.
    event ShareDestroyed(
        bytes32 indexed sessionId,
        uint256 indexed custodianIndex,
        bytes32 proofHash,
        uint256 proofsTotal,
        uint256 thresholdNeeded
    );

    /// @notice Emitted when the ceremony completes — amnesia achieved.
    /// @dev    After this event, the session data is permanently unrecoverable.
    ///         The ciphertext remains on-chain as noise.
    /// @param sessionId   Session that has been forgotten.
    /// @param completedAt Block timestamp of completion.
    event AmnesiaAchieved(
        bytes32 indexed sessionId,
        uint256 completedAt
    );

    /// @notice Emitted when a ceremony fails.
    /// @param sessionId Session whose ceremony failed.
    /// @param reason    Encoded reason for failure.
    event OblivionFailed(
        bytes32 indexed sessionId,
        FailureReason reason
    );

    /// @notice Emitted when a ceremony is explicitly cancelled by the initiator.
    /// @param sessionId   Session whose ceremony was cancelled.
    /// @param cancelledBy Address that triggered the cancellation.
    event OblivionCancelled(
        bytes32 indexed sessionId,
        address indexed cancelledBy
    );

    /// @notice Emitted when a ceremony is blocked by an authorized veto.
    /// @param sessionId Session whose ceremony was vetoed.
    /// @param vetoedBy  Address that submitted the veto proof.
    event OblivionVetoed(
        bytes32 indexed sessionId,
        address indexed vetoedBy
    );

    // ─── Session Management ──────────────────────────

    /// @notice Register a new session on-chain with its custodians and parameters.
    /// @dev    MUST be called before any ceremony can be initiated.
    ///         Custodians form the (k, n) Shamir scheme:
    ///           n = custodians.length (total custodians)
    ///           k = reconstruction threshold (minimum shares to reconstruct key)
    ///           Destruction threshold = n - k + 1
    ///         The session MUST NOT already exist.
    ///         Emits SessionCreated.
    /// @param  sessionId   Unique identifier for the session.
    /// @param  custodians  Array of custodian addresses. Length MUST be >= minCustodians().
    /// @param  k           Reconstruction threshold. MUST satisfy k >= ceil(n/2)+1.
    /// @param  forgoable   Whether this session is eligible for amnesia ceremonies.
    function createSession(
        bytes32 sessionId,
        address[] calldata custodians,
        uint256 k,
        bool forgoable
    ) external;

    // ─── Ceremony Lifecycle ──────────────────────────

    /// @notice Initiate a destruction ceremony for a session.
    /// @dev    Transitions stored state from IDLE → PENDING.
    ///         Starts the VDF time-lock countdown.
    ///         The PENDING→ACTIVE transition is implicit — no transaction needed.
    ///         Effective ACTIVE state begins when block.timestamp >= vdfUnlockTime.
    ///         Only authorized initiators can call this (governance,
    ///         session owner, or designated operator).
    ///         Reverts with CooldownNotElapsed if a previous ceremony failed
    ///         and the cooldown period has not elapsed.
    ///         Reverts with MaxAttemptsReached if ceremonyAttemptCount()
    ///         has reached maxCeremonyAttempts().
    ///         Emits OblivionInitiated.
    /// @param  sessionId     Unique identifier of the data session to forget.
    /// @return vdfUnlockTime Timestamp when ACTIVE state begins.
    /// @return deadline      Timestamp after which the ceremony fails.
    function initiateOblivion(bytes32 sessionId)
        external
        returns (uint256 vdfUnlockTime, uint256 deadline);

    /// @notice Submit a destruction proof from a custodian.
    /// @dev    Only callable when ceremony is effectively ACTIVE
    ///         (block.timestamp >= vdfUnlockTime).
    ///         Each custodian can only submit once per ceremony.
    ///         The proof MUST attest:
    ///           1. The custodian possessed a valid Shamir share (knowledge proof)
    ///           2. The share was a valid point on the Shamir polynomial for this session
    ///           3. The prover PARTICIPATED in the ceremony — was present and active
    ///              during the ACTIVE phase at the time of proof generation
    ///           4. The VDF output is valid for the elapsed time since ceremony initiation
    ///         When proofsReceived reaches threshold → state becomes COMPLETED.
    ///         Emits ShareDestroyed, and AmnesiaAchieved if threshold is reached.
    ///         Hooks registered via registerAmnesiaHook() are called AFTER the state
    ///         transition to COMPLETED, with a gas stipend of 50,000.
    /// @param  sessionId       Session being forgotten.
    /// @param  custodianIndex  Index of the submitting custodian (0-based).
    /// @param  proof           ZK destruction proof.
    /// @return ceremonyComplete  True if this proof triggered completion.
    function submitDestructionProof(
        bytes32 sessionId,
        uint256 custodianIndex,
        bytes calldata proof
    ) external returns (bool ceremonyComplete);

    /// @notice Abort a ceremony that has timed out.
    /// @dev    Callable by anyone after block.timestamp >= deadline.
    ///         Transitions state to FAILED with reason TIMEOUT.
    ///         Keys are NOT destroyed — a new ceremony MAY be initiated
    ///         after ceremonyCooldown() seconds have elapsed.
    ///         Emits OblivionFailed(sessionId, FailureReason.TIMEOUT).
    /// @param  sessionId  Session whose ceremony timed out.
    function abortExpiredCeremony(bytes32 sessionId) external;

    /// @notice Cancel an in-progress ceremony before completion.
    /// @dev    Only callable by the ceremony initiator or an authorized
    ///         governance address during PENDING or ACTIVE state.
    ///         Transitions state to FAILED with reason CANCELLED.
    ///         Keys are NOT destroyed.
    ///         Emits OblivionCancelled and OblivionFailed.
    /// @param  sessionId  Session whose ceremony to cancel.
    function cancelOblivion(bytes32 sessionId) external;

    /// @notice Veto a ceremony during the PENDING phase.
    /// @dev    Allows an authorized party to block destruction before
    ///         the ceremony becomes ACTIVE (before vdfUnlockTime).
    ///         The vetoProof attests that the veto is authorized
    ///         (e.g., governance vote, legal hold, multi-sig threshold).
    ///         Transitions state to FAILED with reason VETOED.
    ///         Keys are NOT destroyed.
    ///         Emits OblivionVetoed and OblivionFailed.
    /// @param  sessionId  Session whose ceremony to veto.
    /// @param  vetoProof  Proof of veto authorization.
    function vetoCeremony(bytes32 sessionId, bytes calldata vetoProof) external;

    // ─── Hook Registration ───────────────────────────

    /// @notice Register a contract to receive callbacks when amnesia is achieved.
    /// @dev    Hooks are called AFTER the state transitions to COMPLETED,
    ///         with a gas stipend of 50,000 per hook.
    ///         Hook reverts do NOT revert the ceremony — amnesia is irreversible
    ///         once COMPLETED. Hook failures are logged but do not block completion.
    ///         The hook contract MUST implement IERC8228_Hooks.
    ///         Implementations SHOULD limit the number of registered hooks
    ///         per session to prevent unbounded gas usage.
    /// @param  sessionId    Session to watch for amnesia completion.
    /// @param  hookContract Contract to notify when amnesia is achieved.
    function registerAmnesiaHook(bytes32 sessionId, address hookContract) external;

    /// @notice Remove a previously registered amnesia hook.
    /// @dev    Silently succeeds if the hook was not registered.
    ///         No effect if the session is already COMPLETED.
    /// @param  sessionId    The session.
    /// @param  hookContract The hook contract to remove.
    function removeAmnesiaHook(bytes32 sessionId, address hookContract) external;

    // ─── Queries ─────────────────────────────────────

    /// @notice Returns the full ceremony info for a session.
    /// @dev    Note: state may read as PENDING but be effectively ACTIVE
    ///         if block.timestamp >= vdfUnlockTime. Always check vdfUnlockTime.
    /// @param  sessionId  The session to query.
    /// @return Full CeremonyInfo struct.
    function ceremonyInfo(bytes32 sessionId)
        external
        view
        returns (CeremonyInfo memory);

    /// @notice Returns whether a session's data has achieved amnesia.
    /// @dev    Returns true if and only if the ceremony reached COMPLETED.
    ///         Once true, this value MUST never return false.
    /// @param  sessionId  The session to query.
    /// @return True if the data is permanently unrecoverable.
    function isForgotten(bytes32 sessionId)
        external
        view
        returns (bool);

    /// @notice Returns whether a session is eligible for amnesia.
    /// @dev    Non-forgoable sessions (e.g., with active retention requirements)
    ///         return false. initiateOblivion MUST revert with
    ///         SessionNotForgoable for such sessions.
    /// @param  sessionId  The session to query.
    /// @return True if a ceremony can be initiated for this session.
    function isForgoable(bytes32 sessionId)
        external
        view
        returns (bool);

    /// @notice Returns whether a specific custodian has submitted
    ///         their destruction proof in the current ceremony.
    /// @param  sessionId       The session.
    /// @param  custodianIndex  The custodian index (0-based).
    /// @return True if this custodian's proof has been accepted.
    function isCustodianDestroyed(
        bytes32 sessionId,
        uint256 custodianIndex
    ) external view returns (bool);

    /// @notice Returns the on-chain address of a custodian for a session.
    /// @param  sessionId       The session.
    /// @param  custodianIndex  The custodian index (0-based).
    /// @return The custodian's registered address.
    function custodianAddress(bytes32 sessionId, uint256 custodianIndex)
        external
        view
        returns (address);

    /// @notice Returns whether an account is a registered custodian for a session.
    /// @param  sessionId  The session.
    /// @param  account    The address to check.
    /// @return True if the account is a registered custodian for this session.
    function isCustodian(bytes32 sessionId, address account)
        external
        view
        returns (bool);

    /// @notice Returns the total number of custodians for a session.
    /// @param  sessionId  The session.
    /// @return n  Total custodians in the (k, n) scheme.
    function custodianCount(bytes32 sessionId)
        external
        view
        returns (uint256 n);

    /// @notice Returns the destruction threshold for a session.
    /// @dev    Equal to (n - k + 1) where n = totalCustodians and
    ///         k = reconstructionThreshold.
    /// @param  sessionId  The session.
    /// @return Number of destruction proofs needed for amnesia.
    function destructionThreshold(bytes32 sessionId)
        external
        view
        returns (uint256);

    // ─── Configuration ───────────────────────────────

    /// @notice Returns the minimum VDF delay in seconds.
    /// @dev    Enforced minimum time between initiation (PENDING)
    ///         and effective ACTIVE state. Prevents coerced rush-destruction.
    /// @return Minimum delay in seconds.
    function minVDFDelay() external view returns (uint256);

    /// @notice Returns the maximum ceremony duration in seconds.
    /// @dev    Time window from vdfUnlockTime to deadline.
    ///         If threshold is not reached by deadline → FAILED.
    /// @return Maximum ceremony duration in seconds.
    function maxCeremonyDuration() external view returns (uint256);

    /// @notice Returns the minimum custodian count allowed per session.
    /// @dev    Implementations MUST enforce this minimum.
    ///         RECOMMENDED minimum: 5.
    /// @return Minimum number of custodians per session.
    function minCustodians() external view returns (uint256);

    /// @notice Returns the cooldown period between ceremony attempts in seconds.
    /// @dev    After a FAILED ceremony, a new ceremony cannot be initiated
    ///         until this many seconds have elapsed since the failure.
    ///         Reverts with CooldownNotElapsed if initiateOblivion is called too soon.
    /// @return Cooldown duration in seconds.
    function ceremonyCooldown() external view returns (uint256);

    /// @notice Returns the number of ceremony attempts made for a session.
    /// @dev    Incremented each time initiateOblivion is successfully called.
    ///         Includes both successful and failed attempts.
    /// @param  sessionId  The session to query.
    /// @return Number of ceremony attempts (0 if never initiated).
    function ceremonyAttemptCount(bytes32 sessionId) external view returns (uint256);

    /// @notice Returns the maximum number of ceremony attempts allowed per session.
    /// @dev    Once reached, initiateOblivion MUST revert with MaxAttemptsReached.
    ///         Prevents indefinite retry loops on stubbornly uncooperative custodians.
    /// @return Maximum allowed attempts per session.
    function maxCeremonyAttempts() external view returns (uint256);
}
