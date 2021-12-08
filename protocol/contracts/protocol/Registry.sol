// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableMapUpgradeable.sol";

import "contracts/utils/RoleCheckable.sol";
import "contracts/interfaces/apwine/tokens/IAPWToken.sol";

/**
 * @title Registry Contract
 * @notice Keeps a record of all valid contract addresses currently used in the protocol
 */
contract Registry is Initializable, RoleCheckable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.UintToAddressMap;

    /* Addresses */
    address private controller;
    address private treasury;
    address private tokensFactory;
    EnumerableSetUpgradeable.AddressSet private futureVaults;

    address private PTLogic;
    address private FYTLogic;

    event RegistryUpdate(string _contractName, address _old, address _new);

    /**
     * @notice Initializer of the contract
     * @param _admin the address of the admin of the contract
     */
    function initialize(address _admin) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
    }

    /* Setters */

    /**
     * @notice Setter for the treasury address
     * @param _newTreasury the address of the new treasury
     */
    function setTreasury(address _newTreasury) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        emit RegistryUpdate("Treasury", treasury, _newTreasury);
        treasury = _newTreasury;
    }

    /**
     * @notice Setter for the tokens factory addres
     * @param _newTokenFactory the address of the token factory
     */
    function setTokensFactory(address _newTokenFactory) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        emit RegistryUpdate("TokenFactory", tokensFactory, _newTokenFactory);
        tokensFactory = _newTokenFactory;
    }

    /**
     * @notice Setter for the controller address
     * @param _newController the address of the new controller
     */
    function setController(address _newController) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        emit RegistryUpdate("Controller", controller, _newController);
        _setupRole(CONTROLLER_ROLE, _newController);
        revokeRole(CONTROLLER_ROLE, controller);
        controller = _newController;
    }

    /**
     * @notice Getter for the controller address
     * @return the address of the controller
     */
    function getControllerAddress() public view returns (address) {
        return controller;
    }

    /**
     * @notice Getter for the treasury address
     * @return the address of the treasury
     */
    function getTreasuryAddress() public view returns (address) {
        return treasury;
    }

    /**
     * @notice Getter for the tokens factory address
     * @return the address of the tokens factory
     */
    function getTokensFactoryAddress() public view returns (address) {
        return tokensFactory;
    }

    /* Logic setters */

    /**
     * @notice Setter for the APWine IBTlogic address
     * @param _PTLogic the address of the new APWine IBTlogic
     */
    function setPTLogic(address _PTLogic) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        emit RegistryUpdate("PT logic", PTLogic, _PTLogic);
        PTLogic = _PTLogic;
    }

    /**
     * @notice Setter for the APWine FYTlogic address
     * @param _FYTLogic the address of the new APWine IBT logic
     */
    function setFYTLogic(address _FYTLogic) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        emit RegistryUpdate("FYT logic", FYTLogic, _FYTLogic);
        FYTLogic = _FYTLogic;
    }

    /* Factory getters */

    /**
     * @notice Getter for the token factory address
     * @return the token factory address
     */
    function getTokenFactoryAddress() public view returns (address) {
        return tokensFactory;
    }

    /* Logic getters */

    /**
     * @notice Getter for APWine IBT logic address
     * @return the APWine IBT logic address
     */
    function getPTLogicAddress() public view returns (address) {
        return PTLogic;
    }

    /**
     * @notice Getter for APWine FYT logic address
     * @return the APWine FYT logic address
     */
    function getFYTLogicAddress() public view returns (address) {
        return FYTLogic;
    }

    /* Futures */

    /**
     * @notice Add a future to the registry
     * @param _future the address of the future to add to the registry
     */
    function addFutureVault(address _future) external onlyController {
        require(futureVaults.add(_future), "Registry: ERR_FUTURE_ADD");
    }

    /**
     * @notice Remove a future from the registry
     * @param _future the address of the future to remove from the registry
     */
    function removeFutureVault(address _future) external onlyController {
        require(futureVaults.remove(_future), "Registry: ERR_FUTURE_RM");
    }

    /**
     * @notice Getter to check if a future is registered
     * @param _future the address of the future to check the registration of
     * @return true if it is, false otherwise
     */
    function isRegisteredFutureVault(address _future) external view returns (bool) {
        return futureVaults.contains(_future);
    }

    /**
     * @notice Getter for the future registered at an index
     * @param _index the index of the future to return
     * @return the address of the corresponding future
     */
    function getFutureVaultAt(uint256 _index) external view returns (address) {
        return futureVaults.at(_index);
    }

    /**
     * @notice Getter for number of futureVaults registered
     * @return the number of futureVaults registered
     */
    function futureVaultCount() external view returns (uint256) {
        return futureVaults.length();
    }
}
