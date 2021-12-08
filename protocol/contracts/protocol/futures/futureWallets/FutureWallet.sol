// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/apwine/tokens/IFutureYieldToken.sol";
import "contracts/interfaces/apwine/IFutureVault.sol";
import "contracts/interfaces/apwine/IController.sol";
import "contracts/interfaces/apwine/IRegistry.sol";

import "contracts/utils/RoleCheckable.sol";
import "contracts/utils/APWineMaths.sol";

/**
 * @title Future Wallet abstraction
 * @notice Main abstraction for the future wallets contract
 * @dev The future wallets stores the yield after each expiration of the future period
 */
abstract contract FutureWallet is Initializable, RoleCheckable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20;

    IFutureVault internal futureVault;
    IERC20 internal ibt;

    bool public WITHRAWALS_PAUSED;

    event YieldRedeemed(address _user, uint256 _periodIndex);
    event WithdrawalsPauseChanged(bool _withdrawalPaused);

    modifier withdrawalsEnabled() {
        require(!WITHRAWALS_PAUSED, "FutureWallets: WITHDRAWALS_DISABLED");
        _;
    }

    /**
     * @notice Intializer
     * @param _futureVault the interface of the corresponding futureVault
     * @param _admin the address of the admin
     */
    function initialize(IFutureVault _futureVault, address _admin) public virtual initializer {
        futureVault = _futureVault;
        ibt = IERC20(futureVault.getIBTAddress());
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(FUTURE_ROLE, address(_futureVault));
        _setupRole(CONTROLLER_ROLE, futureVault.getControllerAddress());
    }

    /**
     * @notice register the yield of an expired period
     * @param _amount the amount of yield to be registered
     */
    function registerExpiredFuture(uint256 _amount) public virtual {
        require(hasRole(FUTURE_ROLE, msg.sender), "ERR_CALLER");
        _registerExpiredFuture(_amount);
    }

    function _registerExpiredFuture(uint256 _amount) internal virtual;

    /**
     * @notice redeem the yield of the underlying yield of the FYT held by the sender
     * @param _periodIndex the index of the period to redeem the yield from
     */
    function redeemYield(uint256 _periodIndex) external virtual nonReentrant withdrawalsEnabled {
        require(_periodIndex < futureVault.getNextPeriodIndex() - 1, "FutureWallets: ERR_PERIOD_ID");
        IFutureYieldToken fyt = IFutureYieldToken(futureVault.getFYTofPeriod(_periodIndex));
        uint256 senderTokenBalance = fyt.balanceOf(msg.sender);
        require(senderTokenBalance > 0, "FutureWallets: ERR_FYT_BALANCE_NULL");

        uint256 claimableYield = _updateYieldBalances(_periodIndex, senderTokenBalance, fyt.totalSupply());

        fyt.burnFrom(msg.sender, senderTokenBalance);
        ibt.safeTransfer(msg.sender, claimableYield);
        emit YieldRedeemed(msg.sender, _periodIndex);
    }

    /**
     * @notice return the yield that could be redeemed by an address for a particular period
     * @param _periodIndex the index of the corresponding period
     * @param _user the FYT holder
     * @return the yield that could be redeemed by the token holder for this period
     */
    function getRedeemableYield(uint256 _periodIndex, address _user) public view virtual returns (uint256);

    /**
     * @notice collect and update the yield balance of the sender
     * @param _periodIndex the index of the corresponding period
     * @param _userFYT the FYT holder balance
     * @param _totalFYT the total FYT supply
     * @return the yield that could be redeemed by the token holder for this period
     */
    function _updateYieldBalances(
        uint256 _periodIndex,
        uint256 _userFYT,
        uint256 _totalFYT
    ) internal virtual returns (uint256);

    /**
     * @notice getter for the address of the futureVault corresponding to this future wallet
     * @return the address of the futureVault
     */
    function getFutureAddress() public view virtual returns (address) {
        return address(futureVault);
    }

    /**
     * @notice getter for the address of the IBT corresponding to this future wallet
     * @return the address of the IBT
     */
    function getIBTAddress() public view virtual returns (address) {
        return address(ibt);
    }

    /**
     * @notice Toggle withdrawals
     */
    function toggleWithdrawalPause() external onlyAdmin {
        WITHRAWALS_PAUSED = !WITHRAWALS_PAUSED;
        emit WithdrawalsPauseChanged(WITHRAWALS_PAUSED);
    }
}
