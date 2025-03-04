# HFRebtateToken

## **Overview**
**HFRebtateToken** is a Solidity-based Ethereum smart contract that implements a **High-Frequency Trading Rebate Token (HFRT)** system. This contract incentivizes traders, liquidity providers, and market makers by offering:
- **Rebates** based on 24-hour rolling trade volume.
- **Fee Discounts** for stakers.
- **Execution Priority** based on HFRT holdings.
- **Liquidity Provider Rewards** for maintaining low-slippage pools.
- **Auto-Compounding Rewards** for staking.
- **Governance & DAO** to vote on protocol changes.
- **Sybil Resistance** to prevent wash trading and flash-loan-based fake volume.
- **Buy-Back and Burn Mechanism** to maintain token value.

---

## **Key Features & Functions**
| Function                 | Description |
|--------------------------|-------------|
| `recordTrade(uint256)`   | Records 24-hour rolling trade volume with sybil resistance. |
| `claimRebate()`         | Claims HFRT tokens based on recorded volume. |
| `stakeTokens(uint256)`   | Stakes HFRT tokens to earn rewards. |
| `unstakeTokens(uint256)` | Unstakes HFRT tokens with a dynamic penalty. |
| `autoCompound()`        | Auto-compounds staking rewards by reinvesting rebates. |
| `createDAOProposal(...)` | Creates a new DAO proposal to update fees. |
| `voteDAOProposal(uint256, bool)` | Votes on a DAO proposal. |
| `executeDAOProposal(uint256)` | Executes a successful DAO proposal. |
| `buyBackAndBurn()`      | Burns 10% of the contract’s token balance to stabilize price. |

---

## **Security Considerations**
- Uses **ReentrancyGuard** to prevent reentrancy attacks.
- Implements **Ownable** to restrict admin functions.
- Uses **Flash Loan Resistance** for staking by enforcing time locks.
- **Sybil Resistance** prevents wash trading and excessive trade frequency.

---

## **License**
This project is licensed under the MIT License.

---
