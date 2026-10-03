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
