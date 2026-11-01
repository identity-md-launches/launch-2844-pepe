# Pepe test properties

The existing deployment and ERC-20 tests in `Pepe.t.sol` are retained. The
additional behavior tests and expanded invariant handler exercise the public ABI
of the actual `Pepe` contract. They need only the project's vendored dependencies.

## Property review

The five discovery passes from the supplied Pashov reference were applied locally,
with the Trail of Bits reference used to review input bounds, independence of the
accounting oracle, and failure classification. The table records their application
to this token; the properties are expected guarantees, not exploratory assumptions.

| Discovery pass | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor mints exactly `10^27` base units, once (`src/Pepe.sol:10-14`). The sum of all tracked balances must remain that amount. | Existing constructor tests; supply invariant; cumulative incoming/outgoing accounting for each actor. |
| State transitions | Approvals replace the caller's permission for one spender. Only successful delegated spends consume finite permission; unlimited permission remains unchanged. See vendored `ERC20.sol:132-158,284-314`. | All 16 actor allowance pairs are compared to independently tracked owner instructions after every handler call; replacement, revocation, exhaustion, self-spending, and retries have focused tests. |
| Round trips and rounding | With exact base-unit transfers, an outbound transfer and its reversal restore both balances. Splitting a transfer cannot change the amount received. See `ERC20.sol:188-215`. | Random round-trip handler; split-versus-single fuzz test; explicit one-base-unit cycle. There are no shares, conversions, fees, or rounding formulas in this contract. |
| Adversarial sequences | Insufficient balance/allowance and zero recipients must reject calls without changing balances or permissions. Valid transfers must remain possible after failed calls. See `ERC20.sol:171-178,193-199,284-314`. | Four failure handler selectors; state digests around focused failures; funding and retry fuzz test; full-balance transfers in `afterInvariant`. |
| Token properties | Self-transfers conserve balances, zero transfers emit events, approvals cannot lock funds, and holders cannot be frozen or seized. | Existing and added edge tests; exact error payloads; correctly typed administrative-call probes; self-transfers and owner/spender/recipient aliasing in random histories. |

## Stateful campaign

`Pepe.invariant.t.sol` uses four actors, nine targeted handler selectors, and inline
settings of 256 runs at depth 128 with `fail-on-revert = true`. Unexpected handler
reverts fail the campaign. Intended token reverts are checked with exact
`expectRevert` payloads and leave the accounting ghosts unchanged.

The initial supply belongs to actor 0. Every successful transfer adds its requested
amount to cumulative sent/received counters, including both sides of self-transfers.
For each actor, the invariant checks:

```
current balance + cumulative sent == initial allocation + cumulative received
```

Allowance ghosts record approval inputs and successful spending, without copying
post-call token state. Checking the complete actor matrix detects changes to
unrelated owners/spenders as well as missing decrements. Only the handler is
targeted, and its recipients stay inside the tracked actor set. Neither token
storage nor token balances are set with cheatcodes.

`approveAndSpend` finds a funded actor and spends a positive amount with either an
exact finite approval or unlimited approval, so delegated spending cannot become
an all-zero campaign. After every sequence, `afterInvariant` consolidates all
holdings and transfers the entire supply again, then rechecks every invariant.

## Reproduction

Run from the repository root. These commands put disposable output under scratch
and require no network:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x52f1e3c3dc13f5f5ed5242fea02aaf88243d27eb186dd6f1b5bc65482c3ebfd8 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The new stateless properties each run 1,024 cases. The supplied protected launch
checks were read as acceptance inputs; they depend on the network's separate
factory, pool, manifest, and deployment harness and are not claimed as local
integration tests. No production defect was identified by this local suite.
