// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface for an ERC20 token that supports minting.
 */
interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title HFRebtateToken
 * @dev A Solidity version of the HFRT project, enhanced for Ethereum.
 * Features include:
 *  - Global state & governance configuration (rebate rate, fee discount)
 *  - 24-hour rolling trade volume tracking with sybil resistance (trade cooldown)
 *  - Rebate claiming (both single and batch)
 *  - Staking/unstaking with dynamic penalty and flash loan resistance via stake lockup
 *  - Auto-compounding of staking rewards
 *  - DAO proposals with batch voting and time-lock for execution
 *  - Execution priority based on token holdings
 *  - A buy-back and burn mechanism
 */
contract HFRebtateToken is Ownable, ReentrancyGuard {
    // The mintable HFRT token
    IERC20Mintable public hfrtToken;

    // Global fee discount value (e.g., for trading fee discounts)
    uint8 public feeDiscount;

    // Governance configuration for rebate and fee parameters
    struct GovernanceConfig {
        address authority;
        uint8 rebateRate;       // e.g., 10 means a 1% rebate (scaled)
        uint8 maxFeeDiscount;   // Maximum allowed fee discount
    }
    GovernanceConfig public governanceConfig;

    // Trader state, tracking trade volume and staking info
    struct Trader {
        uint256 rollingVolume;   // 24-hour rolling trade volume
        uint256 lastTradeUpdate; // Last update timestamp for trade volume
        uint256 stakedAmount;    // Tokens staked by the trader
        uint256 stakeStartTime;  // When staking began (timestamp)
    }
    mapping(address => Trader) public traders;

    // Additional mappings for enforcing trade cooldowns and stake lockup (flash loan resistance)
    mapping(address => uint256) public lastTradeTime;
    mapping(address => uint256) public lastStakeTime;

    // DAO proposal structure with time lock features
    struct DAOProposal {
        uint256 proposalId;
        address proposer;
        uint8 newFeeDiscount;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votingDeadline; // End of voting period
        uint256 executionTime;  // When the proposal can be executed
        bool executed;
    }
    mapping(uint256 => DAOProposal) public daoProposals;

    // --- Events ---
    event TradeRecorded(address indexed trader, uint256 tradeAmount, uint256 rollingVolume);
    event RebateClaimed(address indexed trader, uint256 rebateAmount);
    event RebateIssued(address indexed trader, uint256 rebateAmount);
    event DAOProposalCreated(uint256 proposalId, address proposer, uint256 votingDeadline, uint256 executionTime);
    event DAOProposalExecuted(uint256 proposalId, uint8 newFeeDiscount);
    event TokensBurned(uint256 burnAmount);

    /**
     * @notice Constructor sets the token address and initial fee discount.
     * The Ownable constructor is called with msg.sender as the initial owner.
     */
    constructor(address _hfrtToken, uint8 _feeDiscount) Ownable(msg.sender) {
        hfrtToken = IERC20Mintable(_hfrtToken);
        feeDiscount = _feeDiscount;
    }

    // --- Governance Functions ---

    /**
     * @notice Initializes the governance configuration.
     * @param _rebateRate The rebate rate (e.g., 10 means 1% rebate).
     * @param _maxFeeDiscount The maximum allowed fee discount.
     */
    function initializeGovernance(uint8 _rebateRate, uint8 _maxFeeDiscount) external onlyOwner {
        governanceConfig = GovernanceConfig({
            authority: msg.sender,
            rebateRate: _rebateRate,
            maxFeeDiscount: _maxFeeDiscount
        });
    }

    /**
     * @notice Updates the rebate rate. Only callable by the owner (governance authority).
     * @param newRate The new rebate rate.
     */
    function updateRebateRate(uint8 newRate) external onlyOwner {
        require(newRate <= governanceConfig.maxFeeDiscount, "Invalid rebate rate");
        governanceConfig.rebateRate = newRate;
    }

    // --- Trade & Rebate Functions ---

    /**
     * @notice Records a trade by updating the trader’s 24‑hour rolling volume.
     * Applies a trade cooldown (minimum 5 seconds) and checks for potential wash trading.
     * @param tradeAmount The trade amount.
     */
    function recordTrade(uint256 tradeAmount) external {
        // Enforce a minimum of 5 seconds between trades.
        require(block.timestamp - lastTradeTime[msg.sender] >= 5, "Trades are too frequent");

        // Check for potential wash trading: high trade amount within 10 seconds.
        if (tradeAmount > 1_000_000 && block.timestamp - lastTradeTime[msg.sender] < 10) {
            revert("Potential wash trading detected");
        }
        lastTradeTime[msg.sender] = block.timestamp;

        Trader storage trader = traders[msg.sender];
        // Reset rolling volume if more than 24 hours have passed.
        if (block.timestamp - trader.lastTradeUpdate >= 24 hours) {
            trader.rollingVolume = tradeAmount;
        } else {
            trader.rollingVolume += tradeAmount;
        }
        trader.lastTradeUpdate = block.timestamp;

        emit TradeRecorded(msg.sender, tradeAmount, trader.rollingVolume);
    }

    /**
     * @notice Claims an HFRT rebate based on the recorded 24‑hour trading volume.
     * The rebate is computed using the governance rebate rate and a volume multiplier.
     */
    function claimRebate() external nonReentrant {
        Trader storage trader = traders[msg.sender];
        uint256 baseRebate = (trader.rollingVolume * governanceConfig.rebateRate) / 1000;
        uint8 multiplier = calculateRebateMultiplier(trader.rollingVolume);
        uint256 totalRebate = baseRebate * multiplier;
        trader.rollingVolume = 0;

        // Mint the rebate tokens directly to the trader.
        hfrtToken.mint(msg.sender, totalRebate);
        emit RebateClaimed(msg.sender, totalRebate);
    }

    /**
     * @notice Batch claim rebates for an array of trader addresses.
     * @param traderAddresses The list of trader addresses to process.
     */
    function batchClaimRebate(address[] calldata traderAddresses) external nonReentrant {
        for (uint256 i = 0; i < traderAddresses.length; i++) {
            address traderAddr = traderAddresses[i];
            Trader storage trader = traders[traderAddr];
            uint256 baseRebate = (trader.rollingVolume * governanceConfig.rebateRate) / 1000;
            uint8 multiplier = calculateRebateMultiplier(trader.rollingVolume);
            uint256 totalRebate = baseRebate * multiplier;
            trader.rollingVolume = 0;
            hfrtToken.mint(traderAddr, totalRebate);
            emit RebateIssued(traderAddr, totalRebate);
        }
    }

    // --- Staking Functions ---

    /**
     * @notice Stakes HFRT tokens by transferring them from the trader to this contract.
     * Uses a flash loan prevention mechanism (stake lockup of 1 day).
     * @param amount The amount of tokens to stake.
     */
    function stakeTokens(uint256 amount) external nonReentrant {
        // Enforce a stake lockup to help resist flash loan attacks.
        require(block.timestamp - lastStakeTime[msg.sender] >= 1 days, "Flash loan detected");
        require(hfrtToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        Trader storage trader = traders[msg.sender];
        trader.stakedAmount += amount;
        if (trader.stakeStartTime == 0) {
            trader.stakeStartTime = block.timestamp;
        }
        lastStakeTime[msg.sender] = block.timestamp;
    }

    /**
     * @notice Unstakes HFRT tokens and applies a dynamic unstake penalty based on staking duration.
     * @param amount The amount of tokens to unstake.
     */
    function unstakeTokens(uint256 amount) external nonReentrant {
        Trader storage trader = traders[msg.sender];
        require(trader.stakedAmount >= amount, "Insufficient staked tokens");

        uint256 penalty = calculateDynamicUnstakePenalty(trader.stakeStartTime, block.timestamp, amount);
        uint256 amountAfterPenalty = amount - penalty;
        trader.stakedAmount -= amount;
        if (trader.stakedAmount == 0) {
            trader.stakeStartTime = 0;
        }
        require(hfrtToken.transfer(msg.sender, amountAfterPenalty), "Token transfer failed");
    }

    /**
     * @notice Auto-compounds staking rewards by minting rebate tokens to the contract
     * and adding them to the trader's staked amount.
     */
    function autoCompound() external nonReentrant {
        Trader storage trader = traders[msg.sender];
        uint256 baseRebate = (trader.rollingVolume * governanceConfig.rebateRate) / 1000;
        uint8 multiplier = calculateRebateMultiplier(trader.rollingVolume);
        uint256 totalRebate = baseRebate * multiplier;
        trader.rollingVolume = 0;

        // Mint tokens to the contract (acting as the staking vault).
        hfrtToken.mint(address(this), totalRebate);
        trader.stakedAmount += totalRebate;
        if (trader.stakeStartTime == 0) {
            trader.stakeStartTime = block.timestamp;
        }
    }

    // --- DAO Proposal Functions ---

    /**
     * @notice Creates a new DAO proposal to update the fee discount.
     * @param proposalId The unique ID for the proposal.
     * @param newFeeDiscount The proposed new fee discount.
     * @param votingPeriod Duration (in seconds) during which voting is allowed.
     * @param timeLock Duration (in seconds) after voting ends before execution.
     */
    function createDAOProposal(
        uint256 proposalId,
        uint8 newFeeDiscount,
        uint256 votingPeriod,
        uint256 timeLock
    ) external {
        require(daoProposals[proposalId].proposalId == 0, "Proposal already exists");

        daoProposals[proposalId] = DAOProposal({
            proposalId: proposalId,
            proposer: msg.sender,
            newFeeDiscount: newFeeDiscount,
            votesFor: 0,
            votesAgainst: 0,
            votingDeadline: block.timestamp + votingPeriod,
            executionTime: block.timestamp + votingPeriod + timeLock,
            executed: false
        });
        emit DAOProposalCreated(proposalId, msg.sender, block.timestamp + votingPeriod, block.timestamp + votingPeriod + timeLock);
    }

    /**
     * @notice Votes on an existing DAO proposal.
     * @param proposalId The ID of the proposal.
     * @param voteFor True to vote in favor; false to vote against.
     */
    function voteDAOProposal(uint256 proposalId, bool voteFor) external {
        DAOProposal storage proposal = daoProposals[proposalId];
        require(block.timestamp <= proposal.votingDeadline, "Voting period over");

        if (voteFor) {
            proposal.votesFor += 1;
        } else {
            proposal.votesAgainst += 1;
        }
    }

    /**
     * @notice Batch votes on multiple DAO proposals.
     * @param proposalIds An array of proposal IDs.
     * @param votes An array of booleans indicating votes (true for for, false for against).
     */
    function batchVoteDAOProposal(uint256[] calldata proposalIds, bool[] calldata votes) external {
        require(proposalIds.length == votes.length, "Mismatched inputs");
        for (uint256 i = 0; i < proposalIds.length; i++) {
            DAOProposal storage proposal = daoProposals[proposalIds[i]];
            require(block.timestamp <= proposal.votingDeadline, "Voting period over for proposal");
            if (votes[i]) {
                proposal.votesFor += 1;
            } else {
                proposal.votesAgainst += 1;
            }
        }
    }

    /**
     * @notice Executes a DAO proposal if it has passed and the time lock has expired.
     * @param proposalId The ID of the proposal.
     */
    function executeDAOProposal(uint256 proposalId) external {
        DAOProposal storage proposal = daoProposals[proposalId];
        require(block.timestamp >= proposal.executionTime, "Time lock active");
        require(!proposal.executed, "Already executed");
        require(proposal.votesFor > proposal.votesAgainst, "DAO proposal rejected");

        feeDiscount = proposal.newFeeDiscount;
        proposal.executed = true;
        emit DAOProposalExecuted(proposalId, proposal.newFeeDiscount);
    }

    // --- Execution Priority Function ---

    /**
     * @notice Returns an execution priority based on the trader's HFRT token balance.
     * Lower numbers indicate higher priority.
     * @param trader The address of the trader.
     */
    function getExecutionPriority(address trader) external view returns (uint8) {
        uint256 balance = hfrtToken.balanceOf(trader);
        if (balance >= 1_000_000 * 1e18) return 1;
        else if (balance >= 500_000 * 1e18) return 2;
        else if (balance >= 100_000 * 1e18) return 3;
        else return 5;
    }

    // --- Buyback and Burn Mechanism ---

    /**
     * @notice Executes a buy-back and burn of 10% of the tokens held by this contract.
     * Only callable by the owner.
     */
    function buyBackAndBurn() external onlyOwner nonReentrant {
        uint256 balance = hfrtToken.balanceOf(address(this));
        require(balance > 0, "No tokens available");
        uint256 burnAmount = balance / 10; // 10% burn
        require(hfrtToken.transfer(address(0), burnAmount), "Burn transfer failed");
        emit TokensBurned(burnAmount);
    }

    // --- Helper Functions ---

    /**
     * @notice Calculates a multiplier for the rebate based on 24‑hour trading volume.
     * @param tradeVolume The trading volume.
     * @return A multiplier value.
     */
    function calculateRebateMultiplier(uint256 tradeVolume) public pure returns (uint8) {
        if (tradeVolume >= 100_000_000) {
            return 5;
        } else if (tradeVolume >= 50_000_000) {
            return 3;
        } else if (tradeVolume >= 10_000_000) {
            return 2;
        } else {
            return 1;
        }
    }

    /**
     * @notice Calculates a dynamic unstake penalty based on staking duration.
     * Penalty: 10% if staked less than 7 days, 5% if less than 14 days, 2% otherwise.
     * @param stakeStartTime The timestamp when staking started.
     * @param currentTime The current timestamp.
     * @param amount The unstaking amount.
     * @return The penalty amount.
     */
    function calculateDynamicUnstakePenalty(
        uint256 stakeStartTime,
        uint256 currentTime,
        uint256 amount
    ) public pure returns (uint256) {
        uint256 duration = currentTime - stakeStartTime;
        uint8 penaltyPercentage;
        if (duration < 7 days) {
            penaltyPercentage = 10;
        } else if (duration < 14 days) {
            penaltyPercentage = 5;
        } else {
            penaltyPercentage = 2;
        }
        return (amount * penaltyPercentage) / 100;
    }
}
