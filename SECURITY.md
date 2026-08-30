# Security policy

Do not disclose API keys, access codes, vault content, screenshots containing private data, or potential vulnerabilities in a public issue.

For a security report, contact the maintainer privately through the contact channel listed on the repository profile. Include a minimal reproduction, affected version, and any mitigation already tested. The maintainer should acknowledge a report and coordinate a fix before public disclosure where practical.

## Local security model

- Boujoy is intended for a trusted local macOS account.
- The optional LAN phone view is protected by a locally generated access code.
- The local gateway rejects cross-origin browser writes and validates vault paths before file operations.
- A running Agent can use the capabilities granted to the upstream Harness. Review approvals and do not expose the phone view to untrusted networks.
