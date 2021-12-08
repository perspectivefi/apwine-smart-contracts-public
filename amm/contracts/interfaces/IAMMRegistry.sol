// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title AMM Registry interface
 * @notice Keeps a record of all Future / Pool pairs
 */
interface IAMMRegistry {
    /**
     * @notice Initializer of the contract
     * @param _admin the address of the admin of the contract
     */
    function initialize(address _admin) external;

    /* Setters */

    /**
     * @notice Setter for the AMM pools
     * @param _futureVaultAddress the future vault address
     * @param _ammPool the AMM pool address
     */
    function setAMMPoolByFuture(address _futureVaultAddress, address _ammPool) external;

    /**
     * @notice Register the AMM pools
     * @param _ammPool the AMM pool address
     */
    function setAMMPool(address _ammPool) external;

    /**
     * @notice Remove an AMM Pool from the registry
     * @param _ammPool the address of the pool to remove from the registry
     */
    function removeAMMPool(address _ammPool) external;

    /* Getters */
    /**
     * @notice Getter for the controller address
     * @return the address of the controller
     */
    function getFutureAMMPool(address _futureVaultAddress) external view returns (address);

    function isRegisteredAMM(address _ammAddress) external view returns (bool);
}
