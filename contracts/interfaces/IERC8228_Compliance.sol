// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;

import "./IERC8228.sol";

/// @title ERC-8228 Compliance Extension
/// @author Valisthea (@Valisthea)
/// @notice Provides audit trail and compliance metadata for amnesia events.
///         For regulatory compliance use cases (GDPR, HIPAA, MiCA).
interface IERC8228_Compliance is IERC8228 {

    /// @notice Returns a compliance receipt for a completed ceremony.
    /// @dev    Contains all information a regulator needs to verify
    ///         that data was properly erased: ceremony timestamps,
    ///         custodian proof hashes, VDF parameters, attempt number.
    ///         MUST revert if the session has not reached COMPLETED state.
    /// @param  sessionId  The forgotten session.
    /// @return receipt    ABI-encoded compliance receipt.
    function complianceReceipt(bytes32 sessionId)
        external
        view
        returns (bytes memory receipt);

    /// @notice Returns the data category of a session.
    /// @dev    Used by regulators to apply category-specific retention rules.
    ///         Example values: "GDPR_PERSONAL", "MEDICAL_PHI",
    ///         "GOVERNANCE_VOTE", "SEALED_BID", "CONFIDENTIAL_BUSINESS"
    /// @param  sessionId  The session.
    /// @return category   Category identifier string.
    function dataCategory(bytes32 sessionId)
        external
        view
        returns (string memory category);

    /// @notice Returns the legal retention period for a session.
    /// @dev    A ceremony MUST NOT be initiated before this timestamp.
    ///         initiateOblivion MUST revert with SessionNotForgoable if
    ///         block.timestamp < retentionPeriod(sessionId).
    ///         Returns 0 if no retention requirement exists.
    /// @param  sessionId    The session.
    /// @return retainUntil  Timestamp until which amnesia is blocked.
    function retentionPeriod(bytes32 sessionId)
        external
        view
        returns (uint256 retainUntil);
}
