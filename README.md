# AYA-BLOX-6551

ERC-6551 game loop: mint an NFT to deploy its Token-Bound Account wallet,
fill it with scored Sub Units, and transfer everything to a new owner in one transaction.

[![CI](https://github.com/aya0xx/AYA-BLOX-6551/actions/workflows/ci.yml/badge.svg)](https://github.com/aya0xx/AYA-BLOX-6551/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-363636?logo=solidity)](https://soliditylang.org)
[![Network](https://img.shields.io/badge/Network-Base%20Mainnet-0052FF)](https://base.org)
[![Version](https://img.shields.io/github/tag/aya0xx/AYA-BLOX-6551.svg)](https://github.com/aya0xx/AYA-BLOX-6551/releases)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C)](https://getfoundry.sh)
[![ERC-6551](https://img.shields.io/badge/ERC--6551-Token%20Bound%20Accounts-blue)](https://eips.ethereum.org/EIPS/eip-6551)
[![Live Demo](https://img.shields.io/badge/Live%20Demo-%E2%86%92-green)](https://aya-blox-ui.vercel.app)


## What This Is

AYA-BLOX-6551 is a minimal ERC-6551 experiment. Mint a Base Unit NFT
and a smart contract wallet deploys bound to it — fixed address, permanent.
Mint Sub Units into that wallet, earn points by position — everything
follows the NFT when it transfers.
Deployed and verified on Base mainnet.

## The Mechanic

```
  [1] MINT BASE UNIT NFT
       |
       v
  [2] TBA WALLET DEPLOYS  <-- ERC-6551 Registry
       |
       v
  [3] MINT SUB UNIT INTO TBA
       |
       v
  [4] SLOT SCORED (slot N = N pts)
       +-- if slots remaining --> back to [3]
       |
       v  all slots filled
  [5] BASE UNIT COMPLETED
       |
       v
  [6] TRANSFER BASE UNIT TO NEW OWNER
       |
       v
  +-------------------------------------------------------+
  |  TBA + all Sub Units move with the NFT  <-- ERC-6551  |
  +-------------------------------------------------------+
       |
       +-----------------------------------------> new owner at [3]
```

Full diagram → [docs/game-loop.md](./docs/game-loop.md)


## Live Demo

Try it → [https://aya-blox-ui.vercel.app](https://aya-blox-ui.vercel.app)


## Deployed Contracts

| Network | Contract | Address | Explorer |
|---|---|---|---|
| Base Mainnet | BaseUnit | `0x2DF6e5093103522aD87560B039B4f254b80C730E` | [Basescan](https://basescan.org/address/0x2DF6e5093103522aD87560B039B4f254b80C730E) |
| Base Mainnet | SubUnit | `0x30375A96ab39162C3A1C3bFe9627BAda509D658b` | [Basescan](https://basescan.org/address/0x30375A96ab39162C3A1C3bFe9627BAda509D658b) |


## Run Locally

### Contracts

```bash
git clone https://github.com/aya0xx/AYA-BLOX-6551
cd AYA-BLOX-6551
forge install
forge test
```

### UI

Full setup → [docs/ui-standard.md](./docs/ui-standard.md)


## Documentation

| | |
|---|---|
| Case Study | [CASE-STUDY.md](./CASE-STUDY.md) |
| Game Loop | [docs/game-loop.md](./docs/game-loop.md) |
| UI Standard | [docs/ui-standard.md](./docs/ui-standard.md) |
| Security | [SECURITY.md](./SECURITY.md) |
| Changelog | [CHANGELOG.md](./CHANGELOG.md) |
| Contributing | [CONTRIBUTING.md](./CONTRIBUTING.md) |


## License

MIT © 2026 AYA0X.ETH
