// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;

/// @title ERC-8228 Hooks Extension
/// @author Valisthea (@Valisthea)
/// @notice Interface that hook contracts MUST implement to receive
///         amnesia event callbacks from an IERC8228-compliant contract.
///
/// @dev    Hooks are called AFTER the state transitions to COMPLETED,
///         with a gas stipend of 50,000. If the hook reverts, the amnesia
///         is still achieved — ceremony completion is irreversible.
///         Hook failures are logged but do not revert the ceremony.
///
///         Registration is done on the amnesia contract via:
///           IERC8228.registerAmnesiaHook(sessionId, hookContract)
///           IERC8228.removeAmnesiaHook(sessionId, hookContract)
interface IERC8228_Hooks {

    /// @notice Called on a registered hook contract when amnesia is achieved.
    /// @dev    Called AFTER the amnesia contract has transitioned to COMPLETED.
    ///         Gas stipend: 50,000 — hooks MUST be gas-efficient.
    ///         The hook MUST return the correct selector to confirm receipt.
    ///         If the hook reverts or runs out of gas, the ceremony completion
    ///         is unaffected. The amnesia contract SHOULD emit a hook failure
    ///         event for observability.
    /// @param  sessionId  The session that was forgotten.
    /// @return selector   Must return `IERC8228_Hooks.onAmnesiaAchieved.selector`
    function onAmnesiaAchieved(bytes32 sessionId)
        external
        returns (bytes4 selector);
}
