# Security Policy

## Supported Versions

This repository contains a draft ERC specification and reference interfaces.
The specification is in active development and has not been finalized.

## Scope

Security reports are welcome for the following:

- **Ceremony lifecycle vulnerabilities** — state machine bugs, invalid transitions, griefing vectors
- **Destruction proof soundness** — ZK proof system weaknesses, false proof acceptance
- **Custodian collusion vectors** — threshold bypass, fake destruction attestations
- **VDF manipulation attacks** — time-lock bypass, VDF output forgery
- **Chain reorganization risks** — state inconsistency after reorg, premature share deletion

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately to:

**Email:** security@kairoslab.xyz
**PGP:** Available on request

Include in your report:
- Description of the vulnerability
- Affected component (interface, proof system, ceremony state)
- Proof of concept or reproduction steps
- Suggested mitigation (if any)

## Response Timeline

| Stage | Timeline |
|---|---|
| Acknowledgement | 48 hours |
| Initial assessment | 5 business days |
| Fix / mitigation | Coordinated with reporter |
| Public disclosure | After fix, coordinated |

## Attribution

Responsible disclosure is appreciated and will be credited in the EIP acknowledgements section.
