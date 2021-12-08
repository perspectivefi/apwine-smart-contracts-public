// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/futureWallets/RewardsFutureWallet.sol";

/**
 * @title Rate Future Wallet abstraction
 * @notice Abstraction for the future wallets that works with an IBT whose value incorporates the fees (i.e. cTokens)
 * @dev Override future wallet abstraction with the particular functioning of rate based IBT
 */
abstract contract RateFutureWallet is RewardsFutureWallet {
    using SafeMathUpgradeable for uint256;

    uint256[] internal futureWallets;

    function _registerExpiredFuture(uint256 _amount) internal override {
        futureWallets.push(_amount);
    }

    /**
     * @notice return the yield that could be redeemed by an address for a particular period
     * @param _periodIndex the index of the corresponding period
     * @param _user the FYT holder
     * @return the yield that could be redeemed by the token holder for this period
     */
    function getRedeemableYield(uint256 _periodIndex, address _user) public view override returns (uint256) {
        IFutureYieldToken fyt = IFutureYieldToken(futureVault.getFYTofPeriod(_periodIndex));
        uint256 totalSupply = fyt.totalSupply();
        if (totalSupply == 0) return 0;
        uint256 senderTokenBalance = fyt.balanceOf(_user);
        return (senderTokenBalance.mul(futureWallets[_periodIndex])).div(totalSupply);
    }

    /**
     * @notice collect and update the yield balance of the sender
     * @param _periodIndex the index of the corresponding period
     * @param _userFYT the FYT holder balance
     * @param _totalFYT the total FYT supply
     * @return claimableYield the yield claimed
     */
    function _updateYieldBalances(
        uint256 _periodIndex,
        uint256 _userFYT,
        uint256 _totalFYT
    ) internal override returns (uint256 claimableYield) {
        claimableYield = (_userFYT.mul(futureWallets[_periodIndex])).div(_totalFYT);
        futureWallets[_periodIndex] = futureWallets[_periodIndex].sub(claimableYield);
    }
}
