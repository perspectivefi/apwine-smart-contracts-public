// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "contracts/interfaces/apwine/tokens/IFutureYieldToken.sol";

import "contracts/interfaces/apwine/tokens/IPT.sol";
import "contracts/interfaces/apwine/IFutureWallet.sol";

import "contracts/interfaces/apwine/IController.sol";
import "contracts/interfaces/apwine/IRegistry.sol";
import "contracts/interfaces/apwine/ITokensFactory.sol";

import "contracts/utils/APWineMaths.sol";
import "contracts/utils/RegistryStorage.sol";

/**
 * @title Main future abstraction contract
 * @notice Handles the future mechanisms
 * @dev Basis of all mecanisms for futures (registrations, period switch)
 */
abstract contract FutureVault is Initializable, RegistryStorage, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20;

    /* State variables */
    mapping(uint256 => uint256) internal collectedFYTSByPeriod;
    mapping(uint256 => uint256) internal premiumsTotal;

    mapping(address => uint256) internal lastPeriodClaimed;
    mapping(address => uint256) internal premiumToBeRedeemed;
    mapping(address => uint256) internal FYTsOfUserPremium;

    mapping(address => uint256) internal claimableFYTByUser;
    mapping(uint256 => uint256) internal yieldOfPeriod;
    uint256 internal totalUnderlyingDeposited;

    bool private terminated;
    uint256 internal performanceFeeFactor;

    IFutureYieldToken[] internal fyts;
    /* Delegation */
    struct Delegation {
        address receiver;
        uint256 delegatedAmount;
    }

    mapping(address => Delegation[]) internal delegationsByDelegator;
    mapping(address => uint256) internal totalDelegationsReceived;

    /* External contracts */
    IFutureWallet internal futureWallet;
    IERC20 internal ibt;
    IPT internal pt;
    IController internal controller;

    /* Settings */
    uint256 public PERIOD_DURATION;
    string public PLATFORM_NAME;

    /* Constants */
    uint256 internal IBT_UNIT;
    uint256 internal IBT_UNITS_MULTIPLIED_VALUE;
    uint256 constant UNIT = 10**18;

    /* Events */
    event NewPeriodStarted(uint256 _newPeriodIndex);
    event FutureWalletSet(IFutureWallet _futureWallet);
    event FundsDeposited(address _user, uint256 _amount);
    event FundsWithdrawn(address _user, uint256 _amount);
    event PTSet(IPT _pt);
    event LiquidityTransfersPaused();
    event LiquidityTransfersResumed();
    event DelegationCreated(address _delegator, address _receiver, uint256 _amount);
    event DelegationRemoved(address _delegator, address _receiver, uint256 _amount);
    /* Modifiers */
    modifier nextPeriodAvailable() {
        uint256 controllerDelay = controller.STARTING_DELAY();
        require(
            controller.getNextPeriodStart(PERIOD_DURATION) < block.timestamp.add(controllerDelay),
            "FutureVault: ERR_PERIOD_RANGE"
        );
        _;
    }

    modifier periodsActive() {
        require(!terminated, "PERIOD_TERMINATED");
        _;
    }

    modifier withdrawalsEnabled() {
        require(!controller.isWithdrawalsPaused(address(this)), "FutureVault: WITHDRAWALS_DISABLED");
        _;
    }

    modifier depositsEnabled() {
        require(
            !controller.isDepositsPaused(address(this)) && getCurrentPeriodIndex() != 0,
            "FutureVault: DEPOSITS_DISABLED"
        );
        _;
    }

    /* Initializer */
    /**
     * @notice Intializer
     * @param _controller the address of the controller
     * @param _ibt the address of the corresponding IBT
     * @param _periodDuration the length of the period (in seconds)
     * @param _platformName the name of the platform and tools
     * @param _admin the address of the ACR admin
     */
    function initialize(
        IController _controller,
        IERC20 _ibt,
        uint256 _periodDuration,
        string memory _platformName,
        address _admin
    ) public virtual initializer {
        controller = _controller;
        ibt = _ibt;
        IBT_UNIT = 10**ibt.decimals();
        IBT_UNITS_MULTIPLIED_VALUE = UNIT * IBT_UNIT;
        PERIOD_DURATION = _periodDuration;
        PLATFORM_NAME = _platformName;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(CONTROLLER_ROLE, address(_controller));

        fyts.push();

        registry = IRegistry(controller.getRegistryAddress());

        pt = IPT(
            ITokensFactory(IRegistry(controller.getRegistryAddress()).getTokensFactoryAddress()).deployPT(
                ibt.symbol(),
                ibt.decimals(),
                PLATFORM_NAME,
                PERIOD_DURATION
            )
        );

        emit PTSet(pt);
    }

    /* Period functions */

    /**
     * @notice Start a new period
     * @dev needs corresponding permissions for sender
     */
    function startNewPeriod() public virtual;

    function _switchPeriod() internal periodsActive {
        uint256 nextPeriodID = getNextPeriodIndex();
        uint256 yield = getUnrealisedYieldPerPT().mul(totalUnderlyingDeposited) / IBT_UNIT;

        uint256 reinvestedYield;
        if (yield > 0) {
            uint256 currentPeriodIndex = getCurrentPeriodIndex();
            uint256 premiums = convertUnderlyingtoIBT(premiumsTotal[currentPeriodIndex]);
            uint256 performanceFee = (yield.mul(performanceFeeFactor) / UNIT).sub(premiums);
            uint256 remainingYield = yield.sub(performanceFee);
            yieldOfPeriod[currentPeriodIndex] = convertIBTToUnderlying(
                remainingYield.mul(IBT_UNIT).div(totalUnderlyingDeposited)
            );
            uint256 collectedYield = remainingYield.mul(fyts[currentPeriodIndex].totalSupply()).div(
                totalUnderlyingDeposited
            );
            reinvestedYield = remainingYield.sub(collectedYield);
            futureWallet.registerExpiredFuture(collectedYield); // Yield deposit in the futureWallet contract

            if (performanceFee > 0) ibt.safeTransfer(registry.getTreasuryAddress(), performanceFee);
            if (remainingYield > 0) ibt.safeTransfer(address(futureWallet), collectedYield);
        } else {
            futureWallet.registerExpiredFuture(0);
        }

        /* Period Switch*/
        totalUnderlyingDeposited = totalUnderlyingDeposited.add(convertIBTToUnderlying(reinvestedYield)); // Add newly reinvested yield as underlying
        if (!controller.isFutureSetToBeTerminated(address(this))) {
            _deployNewFutureYieldToken(nextPeriodID);
            emit NewPeriodStarted(nextPeriodID);
        } else {
            terminated = true;
        }

        uint256 nextPerformanceFeeFactor = controller.getNextPerformanceFeeFactor(address(this));
        if (nextPerformanceFeeFactor != performanceFeeFactor) performanceFeeFactor = nextPerformanceFeeFactor;
    }

    /* User state */

    /**
     * @notice Update the state of the user and mint claimable pt
     * @param _user user adress
     */
    function updateUserState(address _user) public {
        require(_user != address(0) , "ERR: Address can't be zero");
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        uint256 lastPeriodClaimedOfUser = lastPeriodClaimed[_user];
        if (lastPeriodClaimedOfUser < currentPeriodIndex && lastPeriodClaimedOfUser != 0) {
            pt.mint(_user, _preparePTClaim(_user));
        }
        if (lastPeriodClaimedOfUser != currentPeriodIndex) lastPeriodClaimed[_user] = currentPeriodIndex;
    }

    function _preparePTClaim(address _user) internal virtual returns (uint256 claimablePT) {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        if (lastPeriodClaimed[_user] < currentPeriodIndex) {
            claimablePT = getClaimablePT(_user);
            delete premiumToBeRedeemed[_user];
            delete FYTsOfUserPremium[_user];
            claimableFYTByUser[_user] = pt.balanceOf(_user).add(totalDelegationsReceived[_user]).sub(
                getTotalDelegated(_user)
            );
            lastPeriodClaimed[_user] = currentPeriodIndex;
        }
    }

    /**
     * @notice Deposit funds into ongoing period
     * @param _user user adress
     * @param _amount amount of funds to unlock
     * @dev part of the amount deposited will be used to buy back the yield already generated proportionally to the amount deposited
     */
    function deposit(address _user, uint256 _amount) external virtual periodsActive depositsEnabled onlyController {
        require((_amount > 0) && (_amount <= ibt.balanceOf(_user)), "FutureVault: ERR_AMOUNT");
        _deposit(_user, _amount);
        emit FundsDeposited(_user, _amount);
    }

    function _deposit(address _user, uint256 _amount) internal {
        uint256 underlyingDeposited = getPTPerAmountDeposited(_amount);
        uint256 ptToMint = _preparePTClaim(_user).add(underlyingDeposited);
        uint256 currentPeriodIndex = getCurrentPeriodIndex();

        /* Update premium */
        uint256 redeemable = getPremiumPerUnderlyingDeposited(underlyingDeposited);
        premiumToBeRedeemed[_user] = premiumToBeRedeemed[_user].add(redeemable);
        FYTsOfUserPremium[_user] = FYTsOfUserPremium[_user].add(ptToMint);
        premiumsTotal[currentPeriodIndex] = premiumsTotal[currentPeriodIndex].add(redeemable);

        /* Update State and mint pt*/
        totalUnderlyingDeposited = totalUnderlyingDeposited.add(underlyingDeposited);
        claimableFYTByUser[_user] = claimableFYTByUser[_user].add(ptToMint);

        pt.mint(_user, ptToMint);
    }

    /**
     * @notice Sender unlocks the locked funds corresponding to their pt holding
     * @param _user user adress
     * @param _amount amount of funds to unlock
     * @dev will require a transfer of FYT of the ongoing period corresponding to the funds unlocked
     */
    function withdraw(address _user, uint256 _amount) external virtual nonReentrant withdrawalsEnabled onlyController {
        require((_amount > 0) && (_amount <= pt.balanceOf(_user)), "FutureVault: ERR_AMOUNT");
        require(_amount <= fyts[getCurrentPeriodIndex()].balanceOf(_user), "FutureVault: ERR_FYT_AMOUNT");
        _withdraw(_user, _amount);

        uint256 FYTsToBurn;
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        uint256 FYTSMinted = fyts[currentPeriodIndex].recordedBalanceOf(_user);
        if (_amount > FYTSMinted) {
            FYTsToBurn = FYTSMinted;
            uint256 ClaimableFYTsToBurn = _amount - FYTsToBurn;
            claimableFYTByUser[_user] = claimableFYTByUser[_user].sub(
                ClaimableFYTsToBurn,
                "FutureVault: ClaimableFYTsToBurn > claimableFYTByUser"
            );
        } else {
            FYTsToBurn = _amount;
        }
        if (FYTsToBurn > 0) fyts[currentPeriodIndex].burnFrom(_user, FYTsToBurn);

        emit FundsWithdrawn(_user, _amount);
    }

    /**
     * @notice Internal function for withdrawing funds corresponding to the pt holding of an address
     * @param _user user adress
     * @param _amount amount of funds to unlock
     * @dev handle the logic of withdraw but does not burn fyts
     */
    function _withdraw(address _user, uint256 _amount) internal virtual {
        updateUserState(_user);
        uint256 fundsToBeUnlocked = _amount.mul(getUnlockableFunds(_user)).div(pt.balanceOf(_user));
        uint256 yieldToBeUnlocked = _amount.mul(getUnrealisedYieldPerPT()) / IBT_UNIT;

        uint256 premiumToBeUnlocked = _prepareUserEarlyPremiumUnlock(_user, _amount);

        require(
            pt.balanceOf(_user) >= _amount.add(getTotalDelegated(_user)),
            "FutureVault: transfer amount exceeds transferrable balance"
        );

        uint256 treasuryFee = (yieldToBeUnlocked.mul(performanceFeeFactor) / UNIT).sub(premiumToBeUnlocked);
        uint256 yieldToBeRedeemed = yieldToBeUnlocked - treasuryFee;
        ibt.safeTransfer(_user, fundsToBeUnlocked.add(yieldToBeRedeemed).add(premiumToBeUnlocked));

        if (treasuryFee > 0) {
            ibt.safeTransfer(registry.getTreasuryAddress(), treasuryFee);
        }
        totalUnderlyingDeposited = totalUnderlyingDeposited.sub(_amount);
        pt.burnFrom(_user, _amount);
    }

    function _prepareUserEarlyPremiumUnlock(address _user, uint256 _ptShares)
        internal
        returns (uint256 premiumToBeUnlocked)
    {
        uint256 unlockablePremium = premiumToBeRedeemed[_user];
        uint256 userFYTsInPremium = FYTsOfUserPremium[_user];
        if (unlockablePremium > 0) {
            if (_ptShares > userFYTsInPremium) {
                premiumToBeUnlocked = convertUnderlyingtoIBT(unlockablePremium);
                delete premiumToBeRedeemed[_user];
                delete FYTsOfUserPremium[_user];
            } else {
                uint256 premiumForAmount = unlockablePremium.mul(_ptShares).div(userFYTsInPremium);
                premiumToBeUnlocked = convertUnderlyingtoIBT(premiumForAmount);
                premiumToBeRedeemed[_user] = unlockablePremium - premiumForAmount;
                FYTsOfUserPremium[_user] = userFYTsInPremium - _ptShares;
            }
            premiumsTotal[getCurrentPeriodIndex()] = premiumsTotal[getCurrentPeriodIndex()].sub(premiumToBeUnlocked);
        }
    }

    /**
     * @notice Getter for the amount (in underlying) of premium redeemable with the corresponding amount of fyt/pt to be burned
     * @param _user user adress
     * @return premiumLocked the premium amount unlockage at this period (in underlying), amountRequired the amount of pt/fyt required for that operation
     */
    function getUserEarlyUnlockablePremium(address _user)
        public
        view
        returns (uint256 premiumLocked, uint256 amountRequired)
    {
        premiumLocked = premiumToBeRedeemed[_user];
        amountRequired = FYTsOfUserPremium[_user];
    }

    /* Delegation */

    /**
     * @notice Create a delegation from one address to another
     * @param _delegator the address delegating its future FYTs
     * @param _receiver the address receiving the future FYTs
     * @param _amount the of future FYTs to delegate
     */
    function createFYTDelegationTo(
        address _delegator,
        address _receiver,
        uint256 _amount
    ) public nonReentrant periodsActive {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "ERR_CALLER");
        updateUserState(_delegator);
        updateUserState(_receiver);
        uint256 totalDelegated = getTotalDelegated(_delegator);
        uint256 numberOfDelegations = delegationsByDelegator[_delegator].length;
        require(_amount > 0 && _amount <= pt.balanceOf(_delegator).sub(totalDelegated), "FutureVault: ERR_AMOUNT");

        bool delegated;
        for (uint256 i = 0; i < numberOfDelegations; i++) {
            if (delegationsByDelegator[_delegator][i].receiver == _receiver) {
                delegationsByDelegator[_delegator][i].delegatedAmount = delegationsByDelegator[_delegator][i]
                    .delegatedAmount
                    .add(_amount);
                delegated = true;
                break;
            }
        }
        if (!delegated) {
            delegationsByDelegator[_delegator].push(Delegation({ receiver: _receiver, delegatedAmount: _amount }));
        }
        totalDelegationsReceived[_receiver] = totalDelegationsReceived[_receiver].add(_amount);
        emit DelegationCreated(_delegator, _receiver, _amount);
    }

    /**
     * @notice Remove a delegation from one address to another
     * @param _delegator the address delegating its future FYTs
     * @param _receiver the address receiving the future FYTs
     * @param _amount the of future FYTs to remove from the delegation
     */
    function withdrawFYTDelegationFrom(
        address _delegator,
        address _receiver,
        uint256 _amount
    ) public {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "ERR_CALLER");
        updateUserState(_delegator);
        updateUserState(_receiver);

        uint256 numberOfDelegations = delegationsByDelegator[_delegator].length;
        bool removed;
        for (uint256 i = 0; i < numberOfDelegations; i++) {
            if (delegationsByDelegator[_delegator][i].receiver == _receiver) {
                delegationsByDelegator[_delegator][i].delegatedAmount = delegationsByDelegator[_delegator][i]
                    .delegatedAmount
                    .sub(_amount, "ERR_AMOUNT");
                removed = true;
                break;
            }
        }
        require(_amount > 0 && removed, "FutureVault: ERR_AMOUNT");
        totalDelegationsReceived[_receiver] = totalDelegationsReceived[_receiver].sub(_amount);
        emit DelegationRemoved(_delegator, _receiver, _amount);
    }

    /**
     * @notice Getter the total number of FYTs on address is delegating
     * @param _delegator the delegating address
     * @return totalDelegated the number of FYTs delegated
     */
    function getTotalDelegated(address _delegator) public view returns (uint256 totalDelegated) {
        uint256 numberOfDelegations = delegationsByDelegator[_delegator].length;
        for (uint256 i = 0; i < numberOfDelegations; i++) {
            totalDelegated = totalDelegated.add(delegationsByDelegator[_delegator][i].delegatedAmount);
        }
    }

    /* Claim functions */

    /**
     * @notice Send the user their owed FYT (and pt if there are some claimable)
     * @param _user address of the user to send the FYT to
     */
    function claimFYT(address _user, uint256 _amount) external virtual nonReentrant {
        require(msg.sender == address(fyts[getCurrentPeriodIndex()]), "FutureVault: ERR_CALLER");
        updateUserState(_user);
        _claimFYT(_user, _amount);
    }

    function _claimFYT(address _user, uint256 _amount) internal virtual {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();
        claimableFYTByUser[_user] = claimableFYTByUser[_user].sub(_amount, "FutureVault: ERR_CLAIMED_FYT_AMOUNT");
        fyts[currentPeriodIndex].mint(_user, _amount);
    }

    /* Termination of the pool */

    /**
     * @notice Exit a terminated pool
     * @param _user the user to exit from the pool
     * @dev only pt are required as there  aren't any new FYTs
     */
    function exitTerminatedFuture(address _user) external nonReentrant onlyController {
        require(terminated, "FutureVault: ERR_NOT_TERMINATED");
        uint256 amount = pt.balanceOf(_user);
        require(amount > 0, "FutureVault: ERR_PT_BALANCE");
        _withdraw(_user, amount);
        emit FundsWithdrawn(_user, amount);
    }

    /* Utilitary functions */

    function convertIBTToUnderlying(uint256 _amount) public view virtual returns (uint256);

    function convertUnderlyingtoIBT(uint256 _amount) public view virtual returns (uint256);

    function _deployNewFutureYieldToken(uint256 newPeriodIndex) internal {
        IFutureYieldToken newToken = IFutureYieldToken(
            ITokensFactory(registry.getTokensFactoryAddress()).deployNextFutureYieldToken(newPeriodIndex)
        );
        fyts.push(newToken);
    }

    /* Getters */
    /**
     * @notice Getter for the amount of pt that the user can claim
     * @param _user user to check the check the claimable pt of
     * @return the amount of pt claimable by the user
     */
    function getClaimablePT(address _user) public view virtual returns (uint256) {
        require(_user != address(0) , "ERR: Address can't be zero");
        uint256 currentPeriodIndex = getCurrentPeriodIndex();

        if (lastPeriodClaimed[_user] < currentPeriodIndex) {
            uint256 recordedBalance = pt.recordedBalanceOf(_user);
            uint256 mintablePT = (recordedBalance).add(premiumToBeRedeemed[_user]); // add premium
            mintablePT = mintablePT.add(totalDelegationsReceived[_user]).sub(getTotalDelegated(_user)); // add delegated FYTs
            uint256 userStackingGrowthFactor = yieldOfPeriod[lastPeriodClaimed[_user]];
            if (userStackingGrowthFactor > 0) {
                mintablePT = mintablePT.add(claimableFYTByUser[_user].mul(userStackingGrowthFactor) / IBT_UNIT); // add reinvested FYTs
            }
            for (uint256 i = lastPeriodClaimed[_user] + 1; i < currentPeriodIndex; i++) {
                mintablePT = mintablePT.add(yieldOfPeriod[i].mul(mintablePT) / IBT_UNIT);
            }
            return mintablePT.add(getTotalDelegated(_user)).sub(recordedBalance).sub(totalDelegationsReceived[_user]);
        } else {
            return 0;
        }
    }

    /**
     * @notice Getter for user IBT amount that is unlockable
     * @param _user the user to unlock the IBT from
     * @return the amount of IBT the user can unlock
     */
    function getUnlockableFunds(address _user) public view virtual returns (uint256) {
        return pt.balanceOf(_user);
    }

    /**
     * @notice Getter for the amount of FYT that the user can claim for a certain period
     * @param _user the user to check the claimable FYT of
     * @param _periodIndex period ID to check the claimable FYT of
     * @return the amount of FYT claimable by the user for this period ID
     */
    function getClaimableFYTForPeriod(address _user, uint256 _periodIndex) external view virtual returns (uint256) {
        uint256 currentPeriodIndex = getCurrentPeriodIndex();

        if (_periodIndex != currentPeriodIndex || _user == address(this)) {
            return 0;
        } else if (_periodIndex == currentPeriodIndex && lastPeriodClaimed[_user] == currentPeriodIndex) {
            return claimableFYTByUser[_user];
        } else {
            return pt.balanceOf(_user).add(totalDelegationsReceived[_user]).sub(getTotalDelegated(_user));
        }
    }

    /**
     * @notice Getter for the yield currently generated by one pt for the current period
     * @return the amount of yield (in IBT) generated during the current period
     */
    function getUnrealisedYieldPerPT() public view virtual returns (uint256);

    /**
     * @notice Getter for the number of pt that can be minted for an amoumt deposited now
     * @param _amount the amount to of IBT to deposit
     * @return the number of pt that can be minted for that amount
     */
    function getPTPerAmountDeposited(uint256 _amount) public view virtual returns (uint256);

    /**
     * @notice Getter for premium in underlying tokens that can be redeemed at the end of the period of the deposit
     * @param _amount the amount to of underlying deposited
     * @return the number of underlying of the ibt deposited that will be redeemable
     */
    function getPremiumPerUnderlyingDeposited(uint256 _amount) public view virtual returns (uint256) {
        if (totalUnderlyingDeposited == 0) {
            return 0;
        }
        uint256 yieldPerFYT = getUnrealisedYieldPerPT();
        uint256 premiumToRefundInIBT = _amount.mul(yieldPerFYT).mul(performanceFeeFactor) / IBT_UNITS_MULTIPLIED_VALUE;
        return convertIBTToUnderlying(premiumToRefundInIBT);
    }

    /**
     * @notice Getter for the value (in underlying) of the unlockable premium
     * @param _user user adress
     * @return the unlockable premium
     */
    function getUnlockablePremium(address _user) public view returns (uint256) {
        if (lastPeriodClaimed[_user] != getCurrentPeriodIndex()) {
            return 0;
        } else {
            return premiumToBeRedeemed[_user];
        }
    }

    /**
     * @notice Getter for the total yield generated during one period
     * @param _periodID the period id
     * @return the total yield in underlying value
     */
    function getYieldOfPeriod(uint256 _periodID) external view returns (uint256) {
        require(getCurrentPeriodIndex() > _periodID, "FutureVault: Invalid period ID");
        return yieldOfPeriod[_periodID];
    }

    /**
     * @notice Getter for next period index
     * @return next period index
     * @dev index starts at 1
     */
    function getNextPeriodIndex() public view virtual returns (uint256) {
        return fyts.length;
    }

    /**
     * @notice Getter for current period index
     * @return current period index
     * @dev index starts at 1
     */
    function getCurrentPeriodIndex() public view virtual returns (uint256) {
        return fyts.length - 1;
    }

    /**
     * @notice Getter for total underlying deposited in the vault
     * @return the total amount of funds deposited in the vault (in underlying)
     */
    function getTotalUnderlyingDeposited() external view returns (uint256) {
        return totalUnderlyingDeposited;
    }

    /**
     * @notice Getter for controller address
     * @return the controller address
     */
    function getControllerAddress() public view returns (address) {
        return address(controller);
    }

    /**
     * @notice Getter for futureWallet address
     * @return futureWallet address
     */
    function getFutureWalletAddress() public view returns (address) {
        return address(futureWallet);
    }

    /**
     * @notice Getter for the IBT address
     * @return IBT address
     */
    function getIBTAddress() public view returns (address) {
        return address(ibt);
    }

    /**
     * @notice Getter for future pt address
     * @return pt address
     */
    function getPTAddress() public view returns (address) {
        return address(pt);
    }

    /**
     * @notice Getter for FYT address of a particular period
     * @param _periodIndex period index
     * @return FYT address
     */
    function getFYTofPeriod(uint256 _periodIndex) public view returns (address) {
        return address(fyts[_periodIndex]);
    }

    /**
     * @notice Getter for the terminated state of the future
     * @return true if this vault is terminated
     */
    function isTerminated() public view returns (bool) {
        return terminated;
    }

    /**
     * @notice Getter for the performance fee factor of the current period
     * @return the performance fee factor of the futureVault
     */
    function getPerformanceFeeFactor() external view returns (uint256) {
        return performanceFeeFactor;
    }

    /* Admin function */
    /**
     * @notice Set futureWallet address
     * @param _futureWallet the address of the new futureWallet
     * @dev needs corresponding permissions for sender
     */
    function setFutureWallet(IFutureWallet _futureWallet) external onlyAdmin {
        futureWallet = _futureWallet;
        emit FutureWalletSet(_futureWallet);
    }

    /**
     * @notice Pause liquidity transfers
     */
    function pauseLiquidityTransfers() public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        pt.pause();
        emit LiquidityTransfersPaused();
    }

    /**
     * @notice Resume liquidity transfers
     */
    function resumeLiquidityTransfers() public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        pt.unpause();
        emit LiquidityTransfersResumed();
    }
}
