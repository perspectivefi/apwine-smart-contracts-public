// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/futureWallets/RewardsFutureWallet.sol";

/**
 * @title Strean Future Wallet abstraction
 * @notice Abstraction for the future wallets that works with an IBT for which its holder gets the interest directly in its wallet progressively (i.e aTokens)
 * @dev Override future wallet abstraction with the particular functioning of stream-based IBT
 */
abstract contract StreamFutureWallet is RewardsFutureWallet {
    using SafeMathUpgradeable for uint256;
    uint256 private scaledTotal;
    uint256[] private scaledFutureWallets;

    function _registerExpiredFuture(uint256 _amount) internal override {
        uint256 currentTotal = ibt.balanceOf(address(this));
        uint256 scaledInput = APWineMaths.getScaledInput(_amount, scaledTotal, currentTotal);
        scaledFutureWallets.push(scaledInput);
        scaledTotal = scaledTotal.add(scaledInput);
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
        uint256 scaledOutput = (senderTokenBalance.mul(scaledFutureWallets[_periodIndex]));
        return APWineMaths.getActualOutput(scaledOutput, scaledTotal, ibt.balanceOf(address(this))).div(totalSupply);
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
        uint256 scaledOutput = (_userFYT.mul(scaledFutureWallets[_periodIndex])).div(_totalFYT);
        claimableYield = APWineMaths.getActualOutput(scaledOutput, scaledTotal, ibt.balanceOf(address(this)));
        scaledFutureWallets[_periodIndex] = scaledFutureWallets[_periodIndex].sub(scaledOutput);
        scaledTotal = scaledTotal.sub(scaledOutput);
    }
}
