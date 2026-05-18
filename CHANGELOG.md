# Changelog
All notable changes to this project will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [1.0.0] - 2026-05-15

First complete implementation. Deployed on Base mainnet. All contracts,
tests, and documentation present. Contracts verified on Basescan.

### Added

**Contracts**
- `src/BaseUnit.sol` — ERC-721 + ERC-721Enumerable with ERC-6551 TBA
  deployment on every mint. Three token types (0/1/2) with slot limits
  4/6/8. Hard supply cap, per-wallet cap, burn prevention,
  TBA-nesting prevention. Fully on-chain SVG metadata via `tokenURI()`.
- `src/SubUnit.sol` — Mint-only ERC-721 permanently bound to one BaseUnit
  TBA. Position-based scoring (slot N = N points). Score accumulates per
  BaseUnit. Approvals and transfers permanently disabled.
- `src/interfaces/IBaseUnit.sol` — Interface for cross-contract calls from
  SubUnit to BaseUnit. Inherits IERC721Enumerable for compile-time safety.
- `src/errors/Errors.sol` — Shared custom errors used by both contracts.
- `src/lib/SVGRenderer.sol` — On-chain SVG helper: slot grid renderer and
  type color mapping. Used by both `tokenURI()` implementations.

**Tests**
- `test/BaseUnit.t.sol` — Full unit test suite. Happy path, edge cases,
  events, revert conditions, TBA nesting prevention, wallet cap
  enforcement, burn prevention.
- `test/SubUnit.t.sol` — Full unit test suite. Mint path, slot filling,
  score accumulation, completion event, transfer consequences, global
  score correctness after ownership changes.
- `test/invariant/SubUnitInvariant.t.sol` — Invariant suite. Score
  monotonicity, slot count bounds, completion state consistency.
- `test/mocks/MockRegistry.sol` — Injectable ERC-6551 registry mock for
  deterministic test environments.

**Scripts**
- `script/DeployAnvil.s.sol` — Local Anvil deployment script. Deploys
  full stack to deterministic addresses on a fresh Anvil instance.

**UI**
- `ui/` — Anvil-optimized developer UI. Custom CSS design system,
  JetBrains Mono, ethers.js v6. Serve locally with `npx serve ui`.
- Live demo (Base mainnet): https://aya-blox-ui.vercel.app

**Configuration**
- `foundry.toml` — Foundry project configuration with optimizer settings.
- `.gitignore` — Excludes `.env`, `out/`, `cache/`, `broadcast/`, `lcov.info`.
- `.env.example` — Documents all required deployment environment variables.
- `.gitmodules` — Submodule references for forge-std and dependencies.
- `.slither.config.json` — Filters `lib/` from static analysis scope.

**CI**
- `.github/workflows/ci.yml` — GitHub Actions workflow: `forge build`,
  `forge test -vvv`, Slither static analysis (fail-on: high).

**Documentation**
- `docs/game-loop.md` — Player-facing ASCII game loop diagram. 6 steps,
  closed loop, ERC-6551 role labeled.
- `docs/ui-standard.md` — UI architecture rationale and local dev setup.
- `CASE-STUDY.md` — 5-section reference implementation documentation.
- `SECURITY.md` — Slither and Aderyn findings tables with security verdict.
- `CONTRIBUTING.md` — Contribution policy for a fixed-scope reference
  implementation.
- `CHANGELOG.md` — This file.
- `LICENSE` — MIT license, 2026, AYA0X.ETH.

### Deployed

- BaseUnit (Base Mainnet): `0x2DF6e5093103522aD87560B039B4f254b80C730E`
- SubUnit (Base Mainnet): `0x30375A96ab39162C3A1C3bFe9627BAda509D658b`
- Verified on Basescan (Standard JSON Input method).

### Security

- S-7 (Slither, `missing-inheritance`) — fixed. Added `is IBaseUnit` to
  BaseUnit contract declaration.
- L-1 (Aderyn, `unspecific-pragma`) — fixed. Pragma pinned to `0.8.27`
  across all source files.
- L-2 (Aderyn, `literal-instead-of-constant`) — fixed. `COLS_PER_ROW = 4`
  constant added to SVGRenderer.
- L-3 (Aderyn, `push0-opcode`) — resolved by L-1 pragma fix.

---

[1.0.0]: https://github.com/aya0xx/AYA-BLOX-6551/releases/tag/v1.0.0
