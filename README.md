# CCPC public CI sandbox

This is a **public-safe test-only repository**, not the CCPC private ERPNext application or deployment repository.

## Automatic tests

`.github/workflows/public-runner-smoke.yml` automatically runs on pushes to `main` and pull requests targeting `main`. It can also be manually dispatched.

| Job | What is tested |
| --- | --- |
| Public standard runner / Python smoke | Two Python standard-library checks |
| Disposable MariaDB / synthetic SQL transactions | Real database rollback and rejection of duplicate references |
| Disposable public Frappe/ERPNext v16 / real SQL | Creates a brand-new site from the public `frappe/erpnext:v16.60.0` image, confirms both apps are installed, and queries the real `Stock Entry` and `Sales Invoice` DocTypes in MariaDB |

The Frappe job is intentionally CLI-only and uses ephemeral Docker named volumes with no host-published ports. Its network is internal to its containers, and the script refuses to run outside a GitHub-hosted Actions runner. It has an 18-minute job timeout and a cleanup trap. PRs from fork repositories do not start the heavy Frappe job. CI-only passwords are known, public, and disposable; **never reuse them anywhere else**.

## Boundaries

- No private `ccpcerp/ccpcerp` source or private deployment code.
- No real CCPC business data, access tokens, SSH keys, ERPNext credentials, or other secrets.
- No connection to DEVELOPMENT, UAT, or PRODUCTION.
- No permanent GitHub runner or self-hosted agent, and no paid infrastructure configured here.
- No claims that these public generic tests exercise CCPC's Withdrawal Slip, stock/GL accounting, concurrency, permissions, or intercompany rules.

The upstream image and package versions are intentionally fixed to specific public version tags for reproducibility. Public container tags are not immutable digest pins; future supply-chain hardening may pin digests after verification.

## Next meaningful gate

Once the public Frappe installation smoke test passes, separately review how to test the *actual private CCPC application* using private-repository-safe CI, synthetic data, reviewed credentials/scopes, and bounded execution. Making this public repository private later would **not** undo any earlier publication of private source or logs.
