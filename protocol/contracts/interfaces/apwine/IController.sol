// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
import "contracts/interfaces/apwine/IFutureVault.sol";
import "contracts/interfaces/apwine/IRegistry.sol";

interface IController {
    /* Events */

    event NextPeriodSwitchSet(uint256 _periodDuration, uint256 _nextSwitchTimestamp);
    event NewPeriodDurationIndexSet(uint256 _periodIndex);
    event FutureRegistered(IFutureVault _futureVault);
    event FutureUnregistered(IFutureVault _futureVault);
    event StartingDelaySet(uint256 _startingDelay);
    event NewPerformanceFeeFactor(IFutureVault _futureVault, uint256 _feeFactor);
    event FutureTerminated(IFutureVault _futureVault);
    event DepositsPaused(IFutureVault _futureVault);
    event DepositsResumed(IFutureVault _futureVault);
    event WithdrawalsPaused(IFutureVault _futureVault);
    event WithdrawalsResumed(IFutureVault _futureVault);
    event RegistryChanged(IRegistry _registry);
    event FutureSetToBeTerminated(IFutureVault _futureVault);

    /* Params */

    function STARTING_DELAY() external view returns (uint256);

    /* User Methods */

    /**
     * @notice Deposit funds into ongoing period
     * @param _futureVault the address of the futureVault to be deposit the funds in
     * @param _amount the amount to deposit on the ongoing period
     * @dev part of the amount depostied will be used to buy back the yield already generated proportionaly to the amount deposited
     */
    function deposit(address _futureVault, uint256 _amount) external;

    /**
     * @notice Withdraw deposited funds from APWine
     * @param _futureVault the address of the futureVault to withdraw the IBT from
     * @param _amount the amount to withdraw
     */
    function withdraw(address _futureVault, uint256 _amount) external;

    /**
     * @notice Exit a terminated pool
     * @param _futureVault the address of the futureVault to exit from from
     * @param _user the user to exit from the pool
     * @dev only pt are required as there  aren't any new FYTs
     */
    function exitTerminatedFuture(address _futureVault, address _user) external;

    /**
     * @notice Create a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault address
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to delegate
     */
    function createFYTDelegationTo(
        address _futureVault,
        address _receiver,
        uint256 _amount
    ) external;

    /**
     * @notice Remove a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault address
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to remove from the delegation
     */
    function withdrawFYTDelegationFrom(
        address _futureVault,
        address _receiver,
        uint256 _amount
    ) external;

    /* Getters */

    /**
     * @notice Getter for the registry address of the protocol
     * @return the address of the protocol registry
     */
    function getRegistryAddress() external view returns (address);

    /**
     * @notice Getter for the period index depending on the period duration of the futureVault
     * @param _periodDuration the duration of the periods
     * @return the period index
     */
    function getPeriodIndex(uint256 _periodDuration) external view returns (uint256);

    /**
     * @notice Getter for the beginning timestamp of the next period for the futures with a defined period duration
     * @param _periodDuration the duration of the periods
     * @return the timestamp of the beginning of the next period
     */
    function getNextPeriodStart(uint256 _periodDuration) external view returns (uint256);

    /**
     * @notice Getter for the next performance fee factor of one futureVault
     * @param _futureVault the address of the futureVault
     * @return the next performance fee factor of the futureVault
     */
    function getNextPerformanceFeeFactor(address _futureVault) external view returns (uint256);

    /**
     * @notice Getter for the performance fee factor of one futureVault
     * @param _futureVault the address of the futureVault
     * @return the performance fee factor of the futureVault
     */
    function getCurrentPerformanceFeeFactor(address _futureVault) external view returns (uint256);

    /**
     * @notice Getter for the list of futureVault durations registered in the contract
     * @return durationsList which consists of futureVault durations
     */
    function getDurations() external view returns (uint256[] memory durationsList);

    /**
     * @notice Getter for the futures by period duration
     * @param _periodDuration the period duration of the futures to return
     */
    function getFuturesWithDuration(uint256 _periodDuration) external view returns (address[] memory filteredFutures);

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the address of the futureVault
     * @return true if the futureVault is terminated
     */
    function isFutureTerminated(address _futureVault) external view returns (bool);

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the address of the futureVault
     * @return true if the futureVault is set to be terminated at its expiration
     */
    function isFutureSetToBeTerminated(address _futureVault) external view returns (bool);

    /**
     * @notice Getter for the futureVault withdrawals state
     * @param _futureVault the address of the futureVault
     * @return true is new withdrawals are paused, false otherwise
     */
    function isWithdrawalsPaused(address _futureVault) external view returns (bool);

    /**
     * @notice Getter for the futureVault deposits state
     * @param _futureVault the address of the futureVault
     * @return true is new deposits are paused, false otherwise
     */
    function isDepositsPaused(address _futureVault) external view returns (bool);
}
