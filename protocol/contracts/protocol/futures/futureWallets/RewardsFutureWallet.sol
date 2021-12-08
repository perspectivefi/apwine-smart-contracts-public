// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/futureWallets/FutureWallet.sol";

/**
 * @title Rewards future wallet abstraction
 * @notice Abstractions for rewards-specific logic
 */
abstract contract RewardsFutureWallet is FutureWallet {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20;

    /* External contracts */
    address internal rewardsRecipient;

    /* Events */
    event RewardsHarvested();
    event RewardTokenRedeemed(IERC20 _token, uint256 _amount);
    event RewardsRecipientUpdated(address _recipient);

    /* Public */

    /**
     * @notice Harvest all rewards from the future wallet
     */
    function harvestRewards() public virtual {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "ERR_CALLER");
        _harvestRewards();
        emit RewardsHarvested();
    }

    /**
     * @notice Should be overridden and implemented by the future depending on platform-specific details
     */
    function _harvestRewards() internal virtual {}

    /**
     * @notice Transfer all the redeemable rewards to set defined recipient
     */
    function redeemAllWalletRewards() external virtual onlyController {
        require(rewardsRecipient != address(0), "RewardsFutureWallets: ERR_RECIPIENT");

        for (uint256 i; i < futureVault.getRewardTokensCount(); i++) {
            IERC20 rewardToken = IERC20(futureVault.getRewardTokenAt(i));
            uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
            rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
            emit RewardTokenRedeemed(rewardToken, rewardTokenBalance);
        }
    }

    /**
     * @notice Transfer the specified token reward balance tot the defined recipient
     * @param _rewardToken the reward token to redeem the balance of
     */
    function redeemWalletRewards(IERC20 _rewardToken) external virtual onlyController {
        require(futureVault.isRewardToken(address(_rewardToken)), "RewardsFutureWallets: ERR_TOKEN_ADDRESS");
        require(rewardsRecipient != address(0), "RewardsFutureWallets: ERR_RECIPIENT");
        uint256 rewardTokenBalance = _rewardToken.balanceOf(address(this));
        _rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
        emit RewardTokenRedeemed(_rewardToken, rewardTokenBalance);
    }

    /**
     * @notice Setter for the address of the rewards recipient
     */
    function setRewardRecipient(address _recipient) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        rewardsRecipient = _recipient;
        emit RewardsRecipientUpdated(_recipient);
    }

    /**
     * @notice Getter for the address of the rewards recipient
     * @return the address of the rewards recipient
     */
    function getRewardsRecipient() external view returns (address) {
        return rewardsRecipient;
    }
}
