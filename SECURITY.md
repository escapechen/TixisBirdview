# Security policy

## Reporting a vulnerability

Please do not disclose a suspected vulnerability in a public issue or
discussion. Use GitHub's private vulnerability-reporting form:

<https://github.com/escapechen/TixisBirdview/security/advisories/new>

Include the affected version, macOS version, impact, reproduction steps, and
any suggested mitigation. Do not include real Frigate or MQTT credentials,
session cookies, private server addresses, camera images, or other household
data.

You should receive an acknowledgement within seven days. We will investigate,
coordinate a fix and disclosure date with you, and credit you unless you prefer
to remain anonymous. Please allow a reasonable remediation period before public
disclosure.

If GitHub says private reporting is unavailable, contact repository owner
[@escapechen](https://github.com/escapechen) privately before sharing details.

## Supported versions

Security fixes are made on the current `main` branch and the latest published
release. Older builds may be asked to upgrade before a report is investigated.

## Scope

Relevant reports include credential or Keychain exposure, authentication or
TLS bypasses, unsafe redirects, unauthorized camera/event access, update-channel
spoofing, sandbox escapes, and sensitive information written to logs.

The configured Frigate server, MQTT broker, camera firmware, and home network
are separate projects and should be reported to their respective maintainers.
