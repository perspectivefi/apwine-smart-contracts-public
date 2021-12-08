// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/apwine/tokens/IFutureYieldToken.sol";
import "contracts/interfaces/apwine/IFutureVault.sol";
import "contracts/interfaces/apwine/IFutureWallet.sol";

import "contracts/utils/RegistryStorage.sol";

/**
 * @title Controller contract
 * @notice The controller dictates the futureVault mechanisms and serves as an interface for main user interaction with futures
 */
contract Controller is Initializable, RegistryStorage {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20;
    using SafeMathUpgradeable for uint256;

    /* Attributes */

    mapping(uint256 => uint256) private nextPeriodSwitchByDuration;
    mapping(address => uint256) private nextPerformanceFeeFactor; // represented as x/(10**18)

    EnumerableSetUpgradeable.UintSet private durations;
    mapping(uint256 => EnumerableSetUpgradeable.AddressSet) private futureVaultsByDuration;
    mapping(uint256 => uint256) private periodIndexByDurations;

    mapping(address => bool) private toBeTerminatedByFutureVault;
    EnumerableSetUpgradeable.AddressSet private futureVaultsTerminated;
    mapping(address => bool) private withdrawalsPausedByFutureVault;
    mapping(address => bool) private depositsPausedByFutureVault;

    /* Events */
    event NextPeriodSwitchSet(uint256 _periodDuration, uint256 _nextSwitchTimestamp);
    event NewPeriodDurationIndexSet(uint256 _periodIndex);
    event FutureRegistered(IFutureVault _futureVault);
    event FutureUnregistered(IFutureVault _futureVault);
    event StartingDelaySet(uint256 _startingDelay);
    event NewPerformanceFeeFactor(IFutureVault _futureVault, uint256 _feeFactor);
    event FutureTerminated(IFutureVault _futureVault);
    event DepositPauseChanged(IFutureVault _futureVault, bool _depositPaused);
    event WithdrawalPauseChanged(IFutureVault _futureVault, bool _withdrawalPaused);
    event FutureSetToBeTerminated(IFutureVault _futureVault);

    /* PlatformController Settings */
    uint256 public STARTING_DELAY;

    /* Modifiers */

    modifier futureVaultIsValid(IFutureVault _futureVault) {
        require(registry.isRegisteredFutureVault(address(_futureVault)), "Controller: ERR_FUTURE_ADDRESS");
        _;
    }

    modifier durationIsPresent(uint256 _duration) {
        require(durations.contains(_duration), "Controller: Period Duration not Found");
        _;
    }

    /* Initializer */

    /**
     * @notice Initializer of the Controller contract
     * @param _registry the address of the registry
     * @param _admin the address of the admin
     */
    function initialize(IRegistry _registry, address _admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        registry = _registry;
    }

    /* User Methods */

    /**
     * @notice Withdraw deposited funds from APWine
     * @param _futureVault the interface of the futureVault to withdraw the IBT from
     * @param _amount the amount to withdraw
     */
    function withdraw(IFutureVault _futureVault, uint256 _amount) external futureVaultIsValid(_futureVault) {
        _futureVault.withdraw(msg.sender, _amount);
    }

    /**
     * @notice Deposit funds into ongoing period
     * @param _futureVault the interface of the futureVault to be deposit the funds in
     * @param _amount the amount to deposit on the ongoing period
     * @dev part of the amount depostied will be used to buy back the yield already generated proportionaly to the amount deposited
     */
    function deposit(IFutureVault _futureVault, uint256 _amount) external futureVaultIsValid(_futureVault) {
        _futureVault.deposit(msg.sender, _amount);
        IERC20(_futureVault.getIBTAddress()).safeTransferFrom(msg.sender, address(_futureVault), _amount);
    }

    /**
     * @notice Create a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault interface
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to delegate
     */
    function createFYTDelegationTo(
        IFutureVault _futureVault,
        address _receiver,
        uint256 _amount
    ) external futureVaultIsValid(_futureVault) {
        _futureVault.createFYTDelegationTo(msg.sender, _receiver, _amount);
    }

    /**
     * @notice Remove a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault interface
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to remove from the delegation
     */
    function withdrawFYTDelegationFrom(
        IFutureVault _futureVault,
        address _receiver,
        uint256 _amount
    ) external futureVaultIsValid(_futureVault) {
        _futureVault.withdrawFYTDelegationFrom(msg.sender, _receiver, _amount);
    }

    /* Future admin methods */

    /**
     * @notice Register a newly created futureVault in the registry
     * @param _futureVault the interface of the new futureVault
     */
    function registerNewFutureVault(IFutureVault _futureVault) external onlyAdmin {
        registry.addFutureVault(address(_futureVault));
        uint256 futureDuration = _futureVault.PERIOD_DURATION();
        if (!durations.contains(futureDuration)) durations.add(futureDuration);
        futureVaultsByDuration[futureDuration].add(address(_futureVault));
        emit FutureRegistered(_futureVault);
    }

    /**
     * @notice Unregister a futureVault from the registry
     * @param _futureVault the interface of the futureVault to unregister
     */
    function unregisterFutureVault(IFutureVault _futureVault) external onlyAdmin {
        registry.removeFutureVault(address(_futureVault));

        uint256 futureDuration = _futureVault.PERIOD_DURATION();
        futureVaultsByDuration[futureDuration].remove(address(_futureVault));
        if (durations.contains(futureDuration) && futureVaultsByDuration[futureDuration].length() == 0)
            durations.remove(futureDuration);
        emit FutureUnregistered(_futureVault);
    }

    /**
     * @notice Change the delay for starting a new period
     * @param _startingDelay the new delay (+-) to start the next period
     */
    function setPeriodStartingDelay(uint256 _startingDelay) public onlyAdmin {
        STARTING_DELAY = _startingDelay;
        emit StartingDelaySet(_startingDelay);
    }

    /**
     * @notice Set the next period switch timestamp for the futureVault with corresponding duration
     * @param _periodDuration the period duration
     * @param _nextPeriodTimestamp the next period switch timestamp
     */
    function setNextPeriodSwitchTimestamp(uint256 _periodDuration, uint256 _nextPeriodTimestamp)
        external
        onlyAdmin
        durationIsPresent(_periodDuration)
    {
        nextPeriodSwitchByDuration[_periodDuration] = _nextPeriodTimestamp;
        emit NextPeriodSwitchSet(_periodDuration, _nextPeriodTimestamp);
    }

    /**
     * @notice Set the next period duration index
     * @param _periodDuration the period duration
     * @param _newPeriodIndex the next period duration index
     * @dev should only be called if there is a need of arbitrarily chaging the indexes in the FYT/PT naming
     */
    function setPeriodDurationIndex(uint256 _periodDuration, uint256 _newPeriodIndex)
        external
        onlyAdmin
        durationIsPresent(_periodDuration)
    {
        periodIndexByDurations[_periodDuration] = _newPeriodIndex;
        emit NewPeriodDurationIndexSet(_newPeriodIndex);
    }

    /**
     * @notice Set the performance fee factor for one futureVault, represented as x/(10**18)
     * @param _futureVault the instance of the futureVault
     * @param _feeFactor the performance fee factor of the futureVault
     */
    function setNextPerformanceFeeFactor(IFutureVault _futureVault, uint256 _feeFactor) external onlyAdmin {
        require(_feeFactor <= 10**18, "Controller: ERR_FEE_FACTOR");
        nextPerformanceFeeFactor[address(_futureVault)] = _feeFactor;
        emit NewPerformanceFeeFactor(_futureVault, _feeFactor);
    }

    /**
     * @notice Start all futures that have a defined period duration to synchronize them
     * @param _periodDuration the period duration of the futures to start
     */
    function startFuturesByPeriodDuration(uint256 _periodDuration)
        external
        onlyStartFuture
        durationIsPresent(_periodDuration)
    {
        uint256 numberOfVaults = futureVaultsByDuration[_periodDuration].length();
        for (uint256 i = 0; i < numberOfVaults; i++) {
            address futureVault = futureVaultsByDuration[_periodDuration].at(i);
            _startFuture(IFutureVault(futureVault));
        }
        nextPeriodSwitchByDuration[_periodDuration] = nextPeriodSwitchByDuration[_periodDuration].add(_periodDuration);
        periodIndexByDurations[_periodDuration]++;
        emit NextPeriodSwitchSet(_periodDuration, nextPeriodSwitchByDuration[_periodDuration]);
    }

    /**
     * @notice Start a specific future
     * @param _futureVault the interface of the futureVault to start
     */
    function startFuture(IFutureVault _futureVault) external onlyStartFuture futureVaultIsValid(_futureVault) {
        _startFuture(_futureVault);
    }

    function _startFuture(IFutureVault _futureVault) internal {
        _futureVault.startNewPeriod();
        if (toBeTerminatedByFutureVault[address(_futureVault)]) {
            futureVaultsTerminated.add(address(_futureVault));
            futureVaultsByDuration[_futureVault.PERIOD_DURATION()].remove(address(_futureVault));
            emit FutureTerminated(_futureVault);
        }
    }

    /**
     * @notice Start a specific future
     * @param _futureVault the interface of the futureVault to terminate
     * @param _user the address of user to exit from the pool
     */
    function exitTerminatedFuture(IFutureVault _futureVault, address _user)
        external
        onlyStartFuture
        futureVaultIsValid(_futureVault)
    {
        _futureVault.exitTerminatedFuture(_user);
    }

    /* Future Vault rewards mechanism */

    function harvestVaultRewards(IFutureVault _futureVault) external onlyHarvestReward futureVaultIsValid(_futureVault) {
        _futureVault.harvestRewards();
    }

    function redeemAllVaultRewards(IFutureVault _futureVault) external onlyHarvestReward futureVaultIsValid(_futureVault) {
        _futureVault.redeemAllVaultRewards();
    }

    function redeemVaultRewards(IFutureVault _futureVault, address _rewardToken)
        external
        onlyHarvestReward
        futureVaultIsValid(_futureVault)
    {
        _futureVault.redeemVaultRewards(_rewardToken);
    }

    function harvestWalletRewards(IFutureVault _futureVault) external onlyHarvestReward futureVaultIsValid(_futureVault) {
        IFutureWallet(_futureVault.getFutureWalletAddress()).harvestRewards();
    }

    function redeemAllWalletRewards(IFutureVault _futureVault) external onlyHarvestReward futureVaultIsValid(_futureVault) {
        IFutureWallet(_futureVault.getFutureWalletAddress()).redeemAllWalletRewards();
    }

    function redeemWalletRewards(IFutureVault _futureVault, address _rewardToken)
        external
        onlyHarvestReward
        futureVaultIsValid(_futureVault)
    {
        IFutureWallet(_futureVault.getFutureWalletAddress()).redeemWalletRewards(_rewardToken);
    }

    /* Getters */

    /**
     * @notice Getter for the registry address of the protocol
     * @return the address of the protocol registry
     */
    function getRegistryAddress() external view returns (address) {
        return address(registry);
    }

    /**
     * @notice Getter for the period index depending on the period duration of the futureVault
     * @param _periodDuration the duration of the periods
     * @return the period index
     */
    function getPeriodIndex(uint256 _periodDuration) public view returns (uint256) {
        return periodIndexByDurations[_periodDuration];
    }

    /**
     * @notice Getter for the beginning timestamp of the next period for the futures with a defined period duration
     * @param _periodDuration the duration of the periods
     * @return the timestamp of the beginning of the next period
     */
    function getNextPeriodStart(uint256 _periodDuration) public view returns (uint256) {
        return nextPeriodSwitchByDuration[_periodDuration];
    }

    /**
     * @notice Getter for the next performance fee factor of one futureVault
     * @param _futureVault the interface of the futureVault
     * @return the next performance fee factor of the futureVault
     */
    function getNextPerformanceFeeFactor(IFutureVault _futureVault) external view returns (uint256) {
        return nextPerformanceFeeFactor[address(_futureVault)];
    }

    /**
     * @notice Getter for the performance fee factor of one futureVault
     * @param _futureVault the interface of the futureVault
     * @return the performance fee factor of the futureVault
     */
    function getCurrentPerformanceFeeFactor(IFutureVault _futureVault)
        external
        view
        futureVaultIsValid(_futureVault)
        returns (uint256)
    {
        return _futureVault.getPerformanceFeeFactor();
    }

    /**
     * @notice Getter for the list of futureVault durations registered in the contract
     * @return durationsList which consists of futureVault durations
     */
    function getDurations() external view returns (uint256[] memory durationsList) {
        durationsList = new uint256[](durations.length());
        uint256 numberOfDurations = durations.length();
        for (uint256 i = 0; i < numberOfDurations; i++) {
            durationsList[i] = durations.at(i);
        }
    }

    /**
     * @notice Getter for the futures by period duration
     * @param _periodDuration the period duration of the futures to return
     */
    function getFuturesWithDuration(uint256 _periodDuration) external view returns (address[] memory filteredFutures) {
        uint256 listLength = futureVaultsByDuration[_periodDuration].length();
        filteredFutures = new address[](listLength);
        for (uint256 i = 0; i < listLength; i++) {
            filteredFutures[i] = futureVaultsByDuration[_periodDuration].at(i);
        }
    }

    /* Security functions */

    /**
     * @notice Terminate a futureVault
     * @param _futureVault the interface of the futureVault to terminate
     * @dev should only be called in extraordinary situations by the admin of the contract
     */
    function setFutureToTerminate(IFutureVault _futureVault) external onlyAdmin {
        toBeTerminatedByFutureVault[address(_futureVault)] = true;
        emit FutureSetToBeTerminated(_futureVault);
    }

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the interface of the futureVault
     * @return true if the futureVault is terminated
     */
    function isFutureTerminated(address _futureVault) external view returns (bool) {
        return futureVaultsTerminated.contains(_futureVault);
    }

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the interface of the futureVault
     * @return true if the futureVault is set to be terminated at its expiration
     */
    function isFutureSetToBeTerminated(address _futureVault) external view returns (bool) {
        return toBeTerminatedByFutureVault[_futureVault];
    }

    /**
     * @notice Toggle withdrawals
     * @param _futureVault the interface of the futureVault to toggle
     * @dev should only be called in extraordinary situations by the admin of the contract
     */
    function toggleWithdrawalPause(IFutureVault _futureVault) external onlyAdmin {
        bool withdrawalPaused = !withdrawalsPausedByFutureVault[address(_futureVault)];
        withdrawalsPausedByFutureVault[address(_futureVault)] = withdrawalPaused;
        emit WithdrawalPauseChanged(_futureVault, withdrawalPaused);
    }

    /**
     * @notice Getter for the futureVault withdrawals state
     * @param _futureVault the interface of the futureVault
     * @return true is new withdrawals are paused, false otherwise
     */
    function isWithdrawalsPaused(address _futureVault) external view returns (bool) {
        return withdrawalsPausedByFutureVault[_futureVault];
    }

    /**
     * @notice Toggle deposit
     * @param _futureVault the interface of the futureVault to toggle
     * @dev should only be called in extraordinary situations by the admin of the contract
     */
    function toggleDepositPause(IFutureVault _futureVault) external onlyAdmin {
        bool depositPaused = !depositsPausedByFutureVault[address(_futureVault)];
        depositsPausedByFutureVault[address(_futureVault)] = depositPaused;
        emit DepositPauseChanged(_futureVault, depositPaused);
    }

    /**
     * @notice Getter for the futureVault deposits state
     * @param _futureVault the interface of the futureVault
     * @return true is new deposits are paused, false otherwise
     */
    function isDepositsPaused(address _futureVault) external view returns (bool) {
        return depositsPausedByFutureVault[_futureVault];
    }
}
