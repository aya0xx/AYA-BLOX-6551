# UI Standard — AYA-BLOX-6551

Local development interface for the AYA-BLOX-6551 contract system.

## Requirements

- Foundry — `anvil`, `forge`
- Node.js — `npx serve`
- MetaMask — import Anvil account #0 private key

## Setup

1. Start a fresh Anvil instance
   ```
   anvil
   ```

2. Import Anvil account #0 into MetaMask

   Private key:
   ```
   0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```

   Chain ID:
   ```
   31337
   ```

   RPC URL:
   ```
   http://127.0.0.1:8545
   ```

3. Deploy contracts
   ```
   cp .env.example .env
   source .env
   forge script script/DeployAnvil.s.sol --rpc-url $ANVIL_RPC_URL \
     --private-key $ANVIL_PRIVATE_KEY --broadcast
   ```

4. Serve the UI
   ```
   cd ui
   npx serve .
   ```

5. Open `http://localhost:3000` and connect MetaMask

## Hardcoded Addresses

Deterministic from `DeployAnvil.s.sol` — account #0, nonces 0–3, fresh instance.

| Contract | Address |
|---|---|
| BaseUnit | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| SubUnit  | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |

If the UI shows no data, your Anvil instance is not fresh — restart `anvil`
and re-run the deploy script from step 3.

## File Map

```
ui/
├── index.html        — shell, splash screen, mint dialogs
├── css/styles.css    — custom design system, JetBrains Mono
├── js/state.js       — state singleton
├── js/api.js         — Anvil-only: chain 31337, hardcoded addresses
└── js/main.js        — UI logic and event handling
```

## Stack

ethers.js v6 · vanilla JS · custom CSS · JetBrains Mono · no build step

## Restart

Stop `anvil`, start a fresh instance, and re-run the deploy script from step 3.
Contracts redeploy to the same deterministic addresses — no MetaMask
reconfiguration needed.

## MetaMask Reset

After restarting Anvil, MetaMask's cached nonce data causes transaction failures.
Reset before continuing:

MetaMask → Settings → Developer Tools → Delete activity and nonce data
