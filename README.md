# VRF Contracts

Example smart contracts demonstrating how to use the **VRF beacon precompile** on Epix Chain.

The VRF module produces a verifiable random beacon at every block. These contracts show how to consume that randomness from Solidity via a commit-reveal Over/Under game.

## Contracts

### `IVRF.sol` — VRF Precompile Interface

Solidity interface for the VRF precompile at `0x0000000000000000000000000000000000000901`.

| Method | Description |
|--------|-------------|
| `getBeacon(uint64 blockHeight)` | Get the random beacon at a specific block height |
| `latestBeacon()` | Get the most recent beacon and its block height |
| `getMultiBlockBeacon(uint64 endHeight, uint64 blocks)` | Get a combined beacon from N consecutive blocks |

### `VRFCoinFlip.sol` — Over/Under Game

A commit-reveal game that demonstrates on-chain VRF consumption:

1. **Commit** — Player calls `commit(guessOver, threshold)` to lock in their guess at the current block
2. **Wait** — 2 blocks must pass so the VRF beacon for the reveal block is produced after the commit
3. **Reveal** — Anyone calls `reveal(player)` — the contract reads the beacon from the precompile, derives a result (1-100), and determines the outcome

The 2-block delay ensures nobody can know the outcome when committing, since the beacon is produced by the chain's VRF module at the end of each block.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) (forge, cast)

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

1. Copy the environment example and fill in your private key:

```bash
cp .env.example .env
# Edit .env with your private key
```

2. Deploy to Epix Testnet:

```bash
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --chain-id 1917
```

### Verify on Blockscout

After deploying, verify the contract source on the block explorer:

```bash
./verify.sh <contract_address> VRFCoinFlip
```

The script reads `EXPLORER_URL` from `.env` and submits the standard JSON input to the Blockscout v2 API.

## Epix Testnet

| | |
|---|---|
| Chain ID | `1917` |
| EVM RPC | `https://evmrpc.testnet.epix.zone` |
| Explorer | `https://testscan.epix.zone` |
| VRF Precompile | `0x0000000000000000000000000000000000000901` |

## License

[MIT](LICENSE)
