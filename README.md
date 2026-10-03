# EVM graph sources

Reproducible Solidity sources for a neutral Ethereum custom-hook graph.

The token and Uniswap v4 hook use separate standard transparent proxies. The hook proxy exposes all ten authenticated callbacks and retains all fourteen v4 permission bits. Implementations may be replaced through their original ProxyAdmins. Supporting claim contracts separate the initial project and platform allocations from liquidity principal.

The initial implementation selects a 2% project allocation and an additional 0.3% platform allocation on gross native-ETH volume. The project allocation is split equally between separate active and treasury destinations. Canonical platform credits and additional platform credits are accounted for separately. These are initial implementation choices.

## Build

Use Foundry 1.8.0 and Solidity 0.8.26+commit.8a97fa7a. Dependencies are vendored as source; their selected revisions are recorded in `foundry.lock`. Exact exported file digests are in `source-manifest.json`. Each dependency retains its license files and individual SPDX declarations.

```sh
forge build --use 0.8.26
forge test --use 0.8.26 --no-match-path 'test/*Fork.t.sol'
ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com ETHEREUM_FORK_BLOCK=26113108 forge test --use 0.8.26 --match-contract TestGraphFork
```

The fork tests use the canonical deployed Ethereum contracts. Fork-only funding and the exact platform-authority response are mocked for mechanical tests. They do not produce a real permit, authorize a wallet transaction, prove current tradeability, or provide a security audit. On-chain execution and platform admission require separate exact evidence.

This repository has a fresh history and contains only candidate sources, tests, dependency sources, licenses and build configuration. It contains no operating credentials or runtime state.

## Implementation evolution

Three independent implementations were authored after the initial graph:

- `NeutralBudgetHook`: configurable project allocation and an optional gross-ETH spending bound supplied by the caller
- `NeutralVoucherHook`: the spending bound plus an owner-queued public waiver of one swap's liquidity-provider fee
- `NeutralFlowHook`: the waiver plus cumulative directional volume accounting; the caller spending-bound rejection is removed

The project-rate and waiver storage namespaces survive replacement. Old earned claims remain in their original independent revenue contracts. A queued waiver can be consumed by any successful swap; it is not a private discount. Volume accounting does not establish unique users or genuine economic demand. These are tested examples of replacement code, not a list of permitted future features

Exact remappings are pinned in `foundry.toml`; automatic discovery is disabled to keep compiler metadata reproducible. The three selected release fork suites passed at blocks 26113926, 26113950 and 26113996 respectively. Use a fresh explicit Ethereum block when evaluating current state:

```sh
ETHEREUM_FORK_BLOCK=26113996 forge test --use 0.8.26 --match-contract NeutralBudgetForkTest
ETHEREUM_FORK_BLOCK=26113996 forge test --use 0.8.26 --match-contract NeutralVoucherForkTest
ETHEREUM_FORK_BLOCK=26113996 forge test --use 0.8.26 --match-contract NeutralFlowForkTest
```

Fork evidence and verified source do not prove that every future implementation will be safe, indexed, routable or compatible with every interface
