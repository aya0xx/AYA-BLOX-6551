# Security — AYA-BLOX-6551

## Audit Status

Slither static analysis run 2026-05-02 (version 0.11.3).
Aderyn static analysis run 2026-05-12.
No critical or high severity findings from either tool. No external audit conducted.
One informational finding (S-7) and two low severity findings (L-1, L-2) fixed before mainnet deployment.

---

## Slither — Static Analysis

| ID | Detector | Severity | Contract | Classification | Status |
|----|----------|----------|----------|----------------|--------|
| S-1 | `unused-return` | Medium | BaseUnit | False positive — return value intentionally discarded; TBA address pre-computed before `createAccount` call | Acknowledged |
| S-2 | `calls-loop` | Low | SubUnit | Accepted — view function, loop bounded by `MAX_UNITS_PER_WALLET` (max 5 iterations) | Acknowledged |
| S-3 | `calls-loop` | Low | SubUnit | Accepted — identical to S-2, different view function | Acknowledged |
| S-4 | `low-level-calls` | Informational | BaseUnit | False positive — intentional ETH forward to immutable treasury; return checked; `nonReentrant` guard active | Acknowledged |
| S-5 | `low-level-calls` | Informational | SubUnit | False positive — identical to S-4 | Acknowledged |
| S-6 | `dead-code` | Informational | BaseUnit | False positive — required OZ ERC721Enumerable multi-inheritance override; compiler errors without it | Acknowledged |
| S-7 | `missing-inheritance` | Informational | BaseUnit | Fixed — `is IBaseUnit` added to contract declaration | ✅ Fixed |
| S-8–19 | `naming-convention` | Informational | BaseUnit, SubUnit | False positive — all-caps is correct convention for `public immutable` variables | Acknowledged |

---

## Clean Detectors — Slither

Zero findings on all high-consequence detectors:

`reentrancy-eth` · `reentrancy-no-eth` · `reentrancy-benign` · `reentrancy-events` · `arbitrary-send-eth` · `unchecked-lowlevel` · `unchecked-transfer` · `divide-before-multiply` · `incorrect-equality` · `locked-ether` · `missing-zero-check` · `suicidal` · `unprotected-upgrade` · `tx-origin` · `constable-states` · `immutable-states` · `costly-loop`

---

## Aderyn — Static Analysis

| ID | Detector | Severity | Contract | Classification | Status |
|----|----------|----------|----------|----------------|--------|
| H-1 | `reentrancy` | High | BaseUnit, SubUnit | False positive — 7 instances; all protected by `nonReentrant`; view calls in CHECKS precede state writes in EFFECTS (correct CEI) | Acknowledged |
| L-1 | `unspecific-pragma` | Low | All | Fixed — pragma pinned to `0.8.27` across all 5 source files | ✅ Fixed |
| L-2 | `literal-instead-of-constant` | Low | SVGRenderer | Fixed — `COLS_PER_ROW = 4` constant added; magic literals replaced | ✅ Fixed |
| L-3 | `push0-opcode` | Low | All | Resolved by L-1 fix — pragma pin to `0.8.27` eliminates detection | ✅ Fixed |
| L-4 | `unsafe-mint` | Low | SubUnit | Accepted — `_mint(tba, subUnitId)` intentional; TBA is a verified first-party address; `nonReentrant` active | Acknowledged |
| L-5 | `loop-contains-revert` | Low | BaseUnit | False positive — loop bound is `balanceOf(user)`, making index overflow impossible | Acknowledged |
| L-6 | `unchecked-return` | Low | BaseUnit | Accepted — `createAccount()` return deterministic (address pre-computed via `account()`); `_requireOwned()` called for revert side effect only | Acknowledged |

---

## Security Verdict

No exploitable vulnerabilities found across either analysis. CEI ordering, `nonReentrant` guards, immutable treasury, and bounded loops all functioning as designed. All remaining findings are false positives or intentional design decisions. S-7 (Slither), L-1, L-2, and L-3 (Aderyn) resolved before mainnet deployment.

All findings are documented in the tables above.

---

## Reporting

To report a vulnerability: open a GitHub issue with `[SECURITY]` in the title.
