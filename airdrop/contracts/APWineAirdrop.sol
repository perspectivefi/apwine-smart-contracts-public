// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/cryptography/MerkleProofUpgradeable.sol";
import "./interfaces/IMerkleDistributor.sol";
import "./interfaces/IVotingEscrow.sol";
import "./MerkleDistributor.sol";

contract APWineAirdrop is MerkleDistributor, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    // Maximum reward rate
    uint256 private constant MAX_BPS = 10000;

    // Total unit available per claim
    uint256 private constant UNIT = 10**18;

    // Airdrop claim start time
    uint256 private claimsStart;

    // Time duration for a Grace
    uint256 public gracePeriod;

    // Time duration for one Epoch cycle
    uint256 public epochDuration;

    // The reduction reward rate per Epoch cycle
    uint256 public rewardReductionPerEpoch;

    // the starting rate at which rewards gets distributed
    uint256 public currentRewardRate;

    // the final Epoch number for the airdrop.
    uint256 public finalEpoch;

    // After hunt is complete extra funds gets transferred to rewardsEscrow address
    address public rewardsEscrow;

    IVotingEscrow public votingEscrow;

    // Lock Duration of Escrow
    uint256 public escrowLockDuration;

    // Fraction to get locked in Voting Escrow mechanism
    uint256 public fractionLocked;

    event Hunt(
        uint256 index,
        address indexed account,
        uint256 amount,
        uint256 userClaim,
        uint256 rewardsEscrowClaim
    );

    function initialize(
        address token_,
        bytes32 merkleRoot_,
        uint256 epochDuration_,
        uint256 rewardReductionPerEpoch_,
        uint256 claimsStart_,
        uint256 gracePeriod_,
        address rewardsEscrow_,
        address owner_,
        IVotingEscrow votingEscrow_,
        uint256 escrowLockDuration_,
        uint256 fractionLocked_
    ) external initializer {
        __MerkleDistributor_init(token_, merkleRoot_);

        __Ownable_init();
        transferOwnership(owner_);

        epochDuration = epochDuration_;
        rewardReductionPerEpoch = rewardReductionPerEpoch_;
        claimsStart = claimsStart_;
        gracePeriod = gracePeriod_;
        votingEscrow = votingEscrow_;
        escrowLockDuration = escrowLockDuration_;
        fractionLocked = fractionLocked_;

        rewardsEscrow = rewardsEscrow_;

        currentRewardRate = 10000;

        finalEpoch = (currentRewardRate / rewardReductionPerEpoch_) - 1;
    }

    /// ===== View Functions =====
    /// @dev Get grace period end timestamp
    function getGracePeriodEnd() public view returns (uint256) {
        return claimsStart.add(gracePeriod);
    }

    /// @dev Get claims start timestamp
    function getClaimsStartTime() external view returns (uint256) {
        return claimsStart;
    }

    /// @dev Get the next epoch start
    function getNextEpochStart() external view returns (uint256) {
        uint256 epoch = getCurrentEpoch();
        uint256 gracePeriodEnd = getGracePeriodEnd();
        return
            epoch == 0
                ? gracePeriodEnd
                : gracePeriodEnd.add(epochDuration.mul(epoch));
    }

    function getTimeUntilNextEpoch() external view returns (uint256) {
        uint256 epoch = getCurrentEpoch();
        uint256 gracePeriodEnd = getGracePeriodEnd();
        return
            epoch == 0
                ? gracePeriodEnd.sub(block.timestamp)
                : gracePeriodEnd.add(epochDuration.mul(epoch)).sub(
                    block.timestamp
                );
    }

    /// @dev Get the current epoch number
    function getCurrentEpoch() public view returns (uint256) {
        uint256 gracePeriodEnd = claimsStart.add(gracePeriod);

        if (block.timestamp < gracePeriodEnd) {
            return 0;
        }
        uint256 secondsPastGracePeriod = block.timestamp.sub(gracePeriodEnd);
        return (secondsPastGracePeriod / epochDuration).add(1);
    }

    /// @dev Get the rewards % of current epoch
    function getCurrentRewardsRate() public view returns (uint256) {
        uint256 epoch = getCurrentEpoch();
        if (epoch == 0) return MAX_BPS;
        return
            epoch > finalEpoch
                ? 0
                : MAX_BPS - (epoch.mul(rewardReductionPerEpoch));
    }

    /// @dev Get the rewards % of next epoch
    function getNextEpochRewardsRate() external view returns (uint256) {
        uint256 epoch = getCurrentEpoch().add(1);
        return
            epoch > finalEpoch
                ? 0
                : MAX_BPS - (epoch.mul(rewardReductionPerEpoch));
    }

    /// ===== Public Actions =====

    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external virtual override {
        require(
            block.timestamp >= claimsStart,
            "ApwineDistributor: Before claim start."
        );
        require(
            account == msg.sender,
            "ApwineDistributor: Can only claim for own account."
        );
        require(
            getCurrentRewardsRate() > 0,
            "ApwineDistributor: Past rewards claim period."
        );
        require(!isClaimed(index), "ApwineDistributor: Drop already claimed.");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(
            MerkleProofUpgradeable.verify(merkleProof, merkleRoot, node),
            "ApwineDistributor: Invalid proof."
        );

        // Mark it claimed and send the token.
        _setClaimed(index);

        uint256 claimable = amount.mul(getCurrentRewardsRate()) / MAX_BPS;

        uint256 transferableTokensFraction = UNIT - fractionLocked;
        uint256 transferableTokens =
            transferableTokensFraction.mul(claimable) / UNIT;
        uint256 tokensToLock = fractionLocked.mul(claimable) / UNIT;
        if (claimable > 0) {
            if (transferableTokensFraction > 0) {
                require(
                    IERC20Upgradeable(token).transfer(
                        account,
                        transferableTokens
                    ),
                    "APWineAirdrop: Transfer to user failed."
                );
            }
            if (tokensToLock > 0) {
                uint256 lock_end = votingEscrow.locked__end(account);
                require(
                    lock_end >= block.timestamp + escrowLockDuration,
                    "APWineAirdrop: Invalid lock end."
                );
                IERC20Upgradeable(token).approve(
                    address(votingEscrow),
                    tokensToLock
                );

                votingEscrow.deposit_for(account, tokensToLock);
            }
        }

        emit Hunt(index, account, amount, transferableTokens, tokensToLock);
    }

    /// ===== Gated Actions: Owner =====

    /// @notice After hunt is complete, transfer excess funds to rewardsEscrow
    function recycleExcess() external onlyOwner {
        require(
            getCurrentRewardsRate() == 0 && getCurrentEpoch() > finalEpoch,
            "Hunt period not finished"
        );
        uint256 remainingBalance =
            IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).transfer(rewardsEscrow, remainingBalance);
    }

    /// ===== set Grace Period =====
    function setGracePeriod(uint256 duration) external onlyOwner {
        gracePeriod = duration;
    }
}
