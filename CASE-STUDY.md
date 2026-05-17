# AYA-BLOX-6551 — Case Study
ERC-6551 Minimal Experiment · May 2026

## The Core Idea

This experiment shows that an NFT can own its own wallet. Using ERC-6551, minting a token automatically deploys a smart contract wallet bound to it — same address, permanent. Whatever you put inside that wallet travels with the NFT when it transfers. This implementation builds a scoring game on top of that: sub-units minted into the wallet earn points by position, and the accumulated score carries to whoever receives the NFT next.

## The Mechanic

Full mechanic diagram → [docs/game-loop.md](./docs/game-loop.md)

*The carry mechanic: transfer the NFT, transfer everything inside it.*

## How It Works

1. You mint a Base Unit. The moment it confirms, a wallet deploys at a fixed address for that token.

2. You mint Sub Units into your Base Unit's wallet. Each one occupies the next available slot. The Sub Unit is minted directly to the Token-Bound Account (TBA) — it lives in the TBA wallet, not at your EOA.

3. Each slot scores by its position. The first Sub Unit earns 1 point, the second earns 2, the eighth earns 8. The later you fill a slot, the more it's worth. Score accumulates on the Base Unit.

4. When every slot is filled, the Base Unit reaches Completed. The final score is fixed. A type-0 token maxes at 10 points across 4 slots, type-1 at 21 across 6, type-2 at 36 across 8.

5. When you transfer the Base Unit, its wallet — and every Sub Unit inside — moves with it. The new owner inherits the score and the contents. They can continue filling remaining slots (if any), or hold a Completed token as a finished artifact.

## Design Decisions

**Sub Units mint directly into the TBA wallet, not the player's address.**
The alternative was to mint Sub Units to the player's address and track parentage in a mapping — simpler to implement. It was rejected for one reason: the carry mechanic. If Sub Units live in the player's wallet, transferring a Base Unit leaves them behind. You'd need to transfer every Sub Unit separately, or add a bundle-transfer function. Minting directly to the TBA makes carry automatic and atomic.

**Score is position-based, not flat.**
One point per Sub Unit regardless of position was considered and rejected. A flat rate creates no incentive to complete a token — partial completion and full completion feel the same. Each slot scores higher than the one before it. Filling the final slot of a type-2 token earns 8 points alone. This rewards continued engagement and makes partially-filled tokens interesting to trade: the new owner inherits the existing score and decides whether the remaining slots are worth finishing.

**No admin surface.**
There is no owner, no pause function, no ability to adjust mint price or slot limits after deployment. This is a deliberate constraint. A reference implementation's value is that anyone can read it and know exactly what it does at any point in time. An admin surface introduces trust assumptions that are invisible to most readers. If you fork this and add ownership controls, the structure supports it — but the reference itself runs without them. This also makes it a more predictable primitive for Level 2 composition: builders layering on top inherit no trust assumptions from an upstream admin.

## Links

| | |
|---|---|
| Live UI | [https://aya-blox-ui.vercel.app](https://aya-blox-ui.vercel.app) |
| Repository | [https://github.com/aya0xx/AYA-BLOX-6551](https://github.com/aya0xx/AYA-BLOX-6551) |
| BaseUnit (Base) | [0x2DF6e5093103522aD87560B039B4f254b80C730E](https://basescan.org/address/0x2DF6e5093103522aD87560B039B4f254b80C730E) |
| SubUnit (Base) | [0x30375A96ab39162C3A1C3bFe9627BAda509D658b](https://basescan.org/address/0x30375A96ab39162C3A1C3bFe9627BAda509D658b) |
| ERC-6551 standard | [https://eips.ethereum.org/EIPS/eip-6551](https://eips.ethereum.org/EIPS/eip-6551) |
| Game loop diagram | [docs/game-loop.md](./docs/game-loop.md) |

