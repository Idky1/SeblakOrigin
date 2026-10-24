# Seblak Origin ($SBLor)

On-chain mining game on **Robinhood Chain** (chain id 4663), born in Bandung, West Java, Indonesia, taking *seblak*, a much-loved Indonesian street food, to the world.

- Burn **1,000 SBLor** to mint a miner NFT. Tier is rolled at mint: Kerupuk 1x (80%), Level Pedas 3x (16%), Sultan 9x (4%). Max 10,000, 10 per wallet.
- Minting is gated to wallets holding an **ERC-8004 Agent ID**.
- **SeblakMine** releases 2% of its pool per hour to miners, pro rata to hashpower. Fully on-chain, no oracle, no backend.
- **SeblakMarket**: fixed-price NFT market in SBLor; 3% buyer + 3% seller tax goes to the Mine.
- **v2 (tested, not yet deployed)**: `SeblakEthVault` + `SeblakMarketEth`, an ETH market where 5% of every sale is shared on-chain with all miner holders by hashpower. No admin key, no Merkle roots, no expiry.

## Mainnet contracts (Robinhood Chain)
| Contract | Address |
|---|---|
| SeblakOrigin (SBLor, 1B fixed supply) | `0x3085510A066Fde9F60B5F732814d38D3cAccEAa3` |
| SeblakAgents (miner NFT) | `0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9` |
| SeblakMine | `0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52` |
| SeblakMarket | `0xf3A5E8B8e6Cb6d8aA303e4C194A2B998cFd27ACf` |

All four are exact-match verified on Sourcify.

## Build and test
```
npm install          # OpenZeppelin
forge install foundry-rs/forge-std --no-git
forge test
```

The mint page lives in `docs/` (served by GitHub Pages).

X: [@SeblakOrigins](https://x.com/SeblakOrigins)
