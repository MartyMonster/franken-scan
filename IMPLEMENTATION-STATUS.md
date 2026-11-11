# Portability implementation checkpoint

Work in progress; not a release. Version remains 1.0.1 until the release gate passes.

Completed locally:
- Preserve failed APT/pacman query status rather than awarding a clean pass.
- Remove unsupported security-origin inference from APT display text.
- Distinguish Tumbleweed update advice from Leap.
- Allow sourcing definitions for isolated regression tests.
- Replace unconditional CI smoke-test success with status/output assertions.
- Syntax, ShellCheck and tests/portability.sh pass.

Remaining before v1.1.0:
- Validate caches and offline behaviour, DNF4/DNF5 and zypper parsing.
- Verify SSH/firewall/automatic-update advice and missing-service-manager handling.
- Expand fixtures and run the agreed isolated distro and ARM64 matrix.
- Test report safety and side effects; document verified versus inferred support.
- Add contribution/release documentation, publish artifacts and verify downloads.
- Update and deploy matching martymonster.dev support claims.

Then implement the separate Node/SQLite AI chatbot prototype with Ollama and
optional OpenAI, a single-owner FAQ editor, local site demo, and annotated guide.
No chatbot implementation, publication or deployment has occurred at this point.
