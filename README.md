# APWine smart contracts

This repository contains the public smart contracts of the APWine protocol and its governance. The documentation is available [here](https://docs.apwine.fi/). By default addresses are the same accross different networks.

## Governance

- APW: [0x4104b135dbc9609fc1a9490e61369036497660c8](https://etherscan.io/address/0x4104b135dbc9609fc1a9490e61369036497660c8)
- VotingEscrow: [0xc5ca1ebf6e912e49a6a70bb0385ea065061a4f09](https://etherscan.io/address/0xc5ca1ebf6e912e49a6a70bb0385ea065061a4f09)
- Treasury: [0xd49d2076B627Ae613CDDa07225febE95b0dE3841](https://etherscan.io/address/0xd49d2076B627Ae613CDDa07225febE95b0dE3841)
- APWineAirdrop: [0x8Dd1Bb800Cc57fbF61560B53b8A1a46867C2Ce17](https://etherscan.io/address/0x8dd1bb800cc57fbf61560b53b8a1a46867c2ce17)

## Core

- Registry: [0x72d15EAE2Cd729D8F2e41B1328311f3e275612B9](https://etherscan.io/address/0x72d15EAE2Cd729D8F2e41B1328311f3e275612B9)
- Controller: [0x4bA30FA240047c17FC557b8628799068d4396790](https://etherscan.io/address/0x4bA30FA240047c17FC557b8628799068d4396790)
- TokenFactory: [0x8e60C994B40aB199FC795754c4E0c4304DeF4536](https://etherscan.io/address/0x8e60C994B40aB199FC795754c4E0c4304DeF4536)
- PT Implementation: [0x66E5d8022876a3cE95281F2E14092a35F2b87a11](https://etherscan.io/address/0x66E5d8022876a3cE95281F2E14092a35F2b87a11)
- FYT Implementation: [0x5B1a479E5D96E28161049900e6F2Dc03485cEdFE](https://etherscan.io/address/0x5B1a479E5D96E28161049900e6F2Dc03485cEdFE)

## Exchange

- AMM Registry: [0x6646A35e74e35585B0B02e5190445A324E5D4D01](https://etherscan.io/address/0x6646A35e74e35585B0B02e5190445A324E5D4D01)
- AMM Router: [0xf5ba2E5DdED276fc0f7a7637A61157a4be79C626](https://etherscan.io/address/0xf5ba2E5DdED276fc0f7a7637A61157a4be79C626) (mainnet) | [0x790a0cA839DC5E4690C8c58cb57fD2beCA419AFc](https://etherscan.io/address/0x790a0cA839DC5E4690C8c58cb57fD2beCA419AFc) (polygon)
- LP Token: [0xab1cAB9C059b627dE5add93834b70e5048923f81](https://etherscan.io/address/0xab1cAB9C059b627dE5add93834b70e5048923f81)

# Pools

- To get the list of FutureVault: `getFutureVaultAt()` on `Registry` (you can obtain the count with `futureVaultCount()` on `Registry`)
- To get the address of an AMM: `getFutureAMMPool(address _futureVaultAddress)` on `AMMRegistry`
- To get address a FutureWallet: `getFutureWalletAddress()` on `FutureVault`
