# Pepe (PEPE)

`src/Pepe.sol:Pepe` is a standard ERC-20 using the vendored OpenZeppelin Contracts v5.0.2 implementation. Its constructor mints the entire supply to the immediate deployer exactly once.

| Parameter | Value |
| --- | --- |
| Solidity contract | `Pepe` |
| Token name | `Pepe` |
| Token symbol | `PEPE` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial recipient | Constructor `msg.sender` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun (supported by Ethereum, chain ID 1) |
| Optimizer | Enabled, 200 runs |
| Metadata hash | `none` |

## Behavior and assumptions

- All ERC-20 amounts use base units: one PEPE is `10^18` units. `INITIAL_SUPPLY` is a public constant.
- Transfers deliver the exact requested amount. There are no taxes, transfer fees, rebases, exclusions, or transfer limits.
- There is no owner, administrator, public mint or burn function, pause, blacklist, confiscation, upgrade, or initialization function. Supply cannot change after construction.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert on failure using OpenZeppelin's ERC-6093 custom errors. Transfers to the zero address and approvals to the zero spender revert. Zero-amount transfers between valid addresses succeed and emit `Transfer`.
- Finite allowances decrease on `transferFrom`. An allowance of `type(uint256).max` does not decrease. `approve` replaces the existing allowance; setting it to zero revokes it. `Approval` is emitted on `approve`; this library version does not emit it when `transferFrom` consumes allowance.
- Self-transfers preserve balances. `transferFrom` still requires the caller's allowance even when the caller is the holder or deployer.
- There are no external calls, oracles, signatures, scheduled actions, or dependencies on other deployed contracts. Transfers to contracts do not invoke receiver callbacks.
- The contract rejects ordinary ETH transfers and unknown calls. It has no asset recovery function; tokens sent to the token contract itself, unsupported recipient contracts, or inaccessible addresses may be irretrievable.

## Build and test

Foundry and Solidity 0.8.26 must be available. All Solidity dependencies are included under `lib/` as ordinary files with their licenses; no `forge install`, submodules, RPC, or network access is needed once the compiler is installed. See [DEPENDENCIES.md](DEPENDENCIES.md) for pinned versions and archive hashes.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x52f1e3c3dc13f5f5ed5242fea02aaf88243d27eb186dd6f1b5bc65482c3ebfd8 forge test
forge fmt --check
```

The suite covers metadata, the sole constructor mint event, direct and CREATE2 factory deployment, exact launch distribution and claim transfers, ordinary transfers in both directions, allowance isolation and revocation, self/zero transfers, invalid recipients, insufficient balances and allowances, rollback on failure, and rejection of privileged calls. Fuzz tests check accounting and rejection boundaries with 1,024 cases each. A stateful invariant checks conservation across 256 sequences of 64 mixed transfers, approvals, and delegated transfers among four holders.

Tests use isolated local deployments and synthetic test actors. They read no environment variables or external state. The factory/pool/distributor actors in the local tests check ERC-20 accounting; they do not emulate Uniswap settlement. The supplied protected tests require the network's separate launch harness and manifest and are not standalone tests of this repository.

## Deployment and operational responsibilities

Deploy the creation bytecode built from `src/Pepe.sol:Pepe`, with no appended constructor arguments and zero ETH. There are no linked libraries. The artifact is `out/Pepe.sol/Pepe.json`.

The account or contract that executes CREATE/CREATE2 receives all `10^27` units. During the IdentityMD launch this is the launch factory, which distributes them under the launch policy. Direct deployment by a wallet instead credits that wallet. No recipient address, key, or chain address is embedded in the token. It does not use `tx.origin`, preallocate any supply, or distribute tokens in its constructor.

The launch operator supplies the separate launch manifest after acceptance, deploys on Ethereum (chain ID 1), checks the build settings and resulting bytecode, verifies source on the explorer, and confirms `name`, `symbol`, `decimals`, `totalSupply`, and the initial deployer balance. The operator/factory is responsible for the specified 10% distributor allocation, 80% pool allocation, and 10% remainder and for pool configuration. Those are external distribution responsibilities, not additional token contracts or minting paths. This repository contains no launch manifest or broadcasting script.

After launch there are no settings to configure, admin keys to maintain, or periodic operations to run on the token. Holders control their transfers and approvals. Wallets should review spenders, prefer bounded approvals, and revoke an existing allowance before replacing it when needed to mitigate the standard ERC-20 approval transaction-ordering race. Indexers should read `allowance()` when they need the current value.

Foundry unit, fuzz, and stateful invariant checks are local validation, not an independent security audit. Before release, the launch process remains responsible for independent adversarial review and its protected integration checks. Slither and Mythril are not part of the local checks reported here. No live deployment or transaction is performed by this project.
