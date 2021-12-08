// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";

import "contracts/RoleCheckable.sol";

/**
 * @title AMM Registry Contract
 * @notice Keeps a record of all Future / Pool pairs
 */
contract AMMRegistry is RoleCheckable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /* Addresses */
    mapping(address => address) private _ammPoolsByFutureVaultAddress;
    EnumerableSetUpgradeable.AddressSet private ammPools;

    /* Events */
    event FutureAMMPoolSet(address indexed _futureVaultAddress, address indexed _ammPool);
    event AMMPoolRegistered(address _ammPool);
    event AMMPoolRemoved(address _ammPool);

    /**
     * @notice Initializer of the contract
     * @param _admin the address of the admin of the contract
     */
    function initialize(address _admin) external initializer {
        _setupRole(ADMIN_ROLE, _admin);
    }

    /* Setters */

    /**
     * @notice Setter for the AMM pools
     * @param _futureVaultAddress the future vault address
     * @param _ammPool the AMM pool address
     */
    function setAMMPoolByFuture(address _futureVaultAddress, address _ammPool) external isAdmin {
        _ammPoolsByFutureVaultAddress[_futureVaultAddress] = _ammPool;
        require(ammPools.add(_ammPool), "Registry: ERR_AMM_ADD");
        emit FutureAMMPoolSet(_futureVaultAddress, _ammPool);
    }

    /**
     * @notice Register the AMM pools
     * @param _ammPool the AMM pool address
     */
    function setAMMPool(address _ammPool) external isAdmin {
        require(ammPools.add(_ammPool), "Registry: ERR_AMM_ADD");
        emit AMMPoolRegistered(_ammPool);
    }

    /**
     * @notice Remove an AMM Pool from the registry
     * @param _ammPool the address of the pool to remove from the registry
     */
    function removeAMMPool(address _ammPool) external isAdmin {
        require(ammPools.remove(_ammPool), "Registry: ERR_AMM_RM");
        emit AMMPoolRemoved(_ammPool);
    }

    /* Getters */
    /**
     * @notice Getter for the controller address
     * @return the address of the controller
     */
    function getFutureAMMPool(address _futureVaultAddress) external view returns (address) {
        return _ammPoolsByFutureVaultAddress[_futureVaultAddress];
    }

    function isRegisteredAMM(address _ammAddress) external view returns (bool) {
        return ammPools.contains(_ammAddress);
    }
}
