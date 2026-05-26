# Security Policy

Nexus is a local-first desktop application. It reads local workspace metadata, Markdown documents, and git state from paths configured by the user.

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.1.x alpha | Security fixes when practical |

## Reporting A Vulnerability

Please open a private security advisory on GitHub or contact the maintainers directly if advisory access is unavailable.

Do not include private workspace documents, tokens, proprietary service names, or sensitive local paths in public issues.

## Security Boundaries

Nexus should keep these boundaries:

- Local workspace data stays on the user's machine.
- Workspace scanning should be read-only.
- File writes should be limited to explicit user actions, such as creating a workspace or writing the widget snapshot.
- Dangerous git or filesystem operations must require explicit confirmation.
- Remote integrations must document what data is sent, where it is sent, and how users can disable it.

## Sensitive Data

Do not commit:

- Real workspace contents.
- Private local paths.
- Tokens, API keys, certificates, signing passwords, or `.env` files.
- Customer, merchant, payment, order, or production incident data.
- Generated app bundles or build caches.

## macOS Distribution

Public distribution should use:

- Apple Developer ID signing.
- Apple notarization.
- Signed update manifests when automatic updates are enabled.
- A clear changelog for every released build.
