// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/FutureVault.sol";

/**
 * @title Rewards future abstraction
 * @notice Handles all future mechanisms along with reward-specific functionality
 * @dev Allows for better decoupling of rewards logic with core future logic
 */
abstract contract RewardsFutureVault is FutureVault {
    using SafeERC20Upgradeable for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /* Rewards mecanisms */
    EnumerableSetUpgradeable.AddressSet internal rewardTokens;

    /* External contracts */
    address internal rewardsRecipient;

    /* Events */
    event RewardsHarvested();
    event RewardTokenAdded(address _token);
    event RewardTokenRedeemed(IERC20 _token, uint256 _amount);
    event RewardsRecipientUpdated(address _recipient);

    /* Public */

    /**
     * @notice Harvest all rewards from the vault
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
    function redeemAllVaultRewards() external virtual onlyController {
        require(rewardsRecipient != address(0), "RewardsFutureVault: ERR_RECIPIENT");
        uint256 numberOfRewardTokens = rewardTokens.length();
        for (uint256 i; i < numberOfRewardTokens; i++) {
            IERC20 rewardToken = IERC20(rewardTokens.at(i));
            uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
            rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
            emit RewardTokenRedeemed(rewardToken, rewardTokenBalance);
        }
    }

    /**
     * @notice Transfer the specified token reward balance tot the defined recipient
     * @param _rewardToken the reward token to redeem the balance of
     */
    function redeemVaultRewards(IERC20 _rewardToken) external virtual onlyController {
        require(rewardsRecipient != address(0), "RewardsFutureVault: ERR_RECIPIENT");
        require(rewardTokens.contains(address(_rewardToken)), "RewardsFutureVault: ERR_TOKEN_ADDRESS");
        uint256 rewardTokenBalance = _rewardToken.balanceOf(address(this));
        _rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
        emit RewardTokenRedeemed(_rewardToken, rewardTokenBalance);
    }

    /**
     * @notice Add a token to the list of reward tokens
     * @param _token the reward token to add to the list
     * @dev the token must be different than the ibt
     */
    function addRewardsToken(address _token) external onlyAdmin {
        require(_token != address(ibt), "RewardsFutureVault: ERR_TOKEN_ADDRESS");
        rewardTokens.add(_token);
        emit RewardTokenAdded(_token);
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
     * @notice Getter to check if a token is in the reward tokens list
     * @param _token the token to check if it is in the list
     * @return true if the token is a reward token
     */
    function isRewardToken(IERC20 _token) external view returns (bool) {
        return rewardTokens.contains(address(_token));
    }

    /**
     * @notice Getter for the reward token at an index
     * @param _index the index of the reward token in the list
     * @return the address of the token at this index
     */
    function getRewardTokenAt(uint256 _index) external view returns (address) {
        return rewardTokens.at(_index);
    }

    /**
     * @notice Getter for the size of the list of reward tokens
     * @return the number of token in the list
     */
    function getRewardTokensCount() external view returns (uint256) {
        return rewardTokens.length();
    }

    /**
     * @notice Getter for the address of the rewards recipient
     * @return the address of the rewards recipient
     */
    function getRewardsRecipient() external view returns (address) {
        return rewardsRecipient;
    }
}
