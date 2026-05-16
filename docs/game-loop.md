# Game Loop — AYA-BLOX-6551

Player-facing mechanic diagram. ERC-6551 experiment.

## The Loop

```
  +----------------------------------------------------------------+
  |                    AYA-BLOX-6551 GAME LOOP                     |
  +----------------------------------------------------------------+

  [1] PLAYER MINTS A BASE UNIT NFT
       pays mint price · receives token type 0, 1, or 2
       |
       v
  [2] NFT WALLET DEPLOYS AUTOMATICALLY <-- ERC-6551 Registry
       the NFT now owns a smart contract wallet
       |
       v
  [3] PLAYER MINTS A SUB UNIT
       must own the Base Unit · sub unit lands inside the NFT wallet
       |
       v
  [4] SLOT SCORED BY POSITION
       slot 1 = 1 pt · slot 2 = 2 pt · slot N = N pt
       score accumulates on the Base Unit
       |
       +-- if slots remaining --> back to [3]
       |
       v  all slots filled
  [5] BASE UNIT REACHES COMPLETED STATE
       type 0 -> max 10 pts · type 1 -> max 21 pts · type 2 -> max 36 pts
       |
       v
  [6] PLAYER TRANSFERS THE BASE UNIT TO A NEW OWNER
       |
       v
  +----------------------------------------------------------------+
  |  the NFT wallet travels with the token <-- ERC-6551            |
  |  all Sub Units inside the wallet travel with it                |
  |  the accumulated score travels with it                         |
  +----------------------------------------------------------------+
       |
       +-----------------------------------------------> new owner at [3]
```

## What Transfers With the NFT

- The Base Unit NFT itself
- Its Token-Bound Account wallet (same address, new controller)
- Every Sub Unit minted inside that wallet

The new owner inherits the score and continues filling remaining slots from where the previous owner stopped.

## Why ERC-6551

ERC-721 alone gives an NFT an owner. ERC-6551 gives an NFT a wallet — a smart contract account with its own address, capable of holding assets. When the NFT transfers, the wallet's address does not change; only the controlling owner does. This is what makes the carry mechanic possible: the Sub Units live inside the wallet, not in the player's inventory, so they follow the NFT automatically.
