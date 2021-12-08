// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract RoleCheckable is AccessControlUpgradeable {
    /* ACR Roles*/

    // keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x1effbbff9c66c5e59634f24fe842750c60d18891155c32dd155fc2d661a4c86d;
    // keccak256("CONTROLLER_ROLE")
    bytes32 internal constant CONTROLLER_ROLE = 0x7b765e0e932d348852a6f810bfa1ab891e259123f02db8cdcde614c570223357;
    // keccak256("START_FUTURE")
    bytes32 internal constant START_FUTURE = 0xeb5092aab714e6356486bc97f25dd7a5c1dc5c7436a9d30e8d4a527fba24de1c;
    // keccak256("FUTURE_ROLE")
    bytes32 internal constant FUTURE_ROLE = 0x52d2dbc4d362e84c42bdfb9941433968ba41423559d7559b32db1183b22b148f;
    // keccak256("HARVEST_REWARDS")
    bytes32 internal constant HARVEST_REWARDS = 0xf2683e58e5a2a04c1ed32509bfdbf1e9ebc725c63f4c95425d2afd482bfdb0f8;

    /* Modifiers */

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "RoleCheckable: Caller should be ADMIN");
        _;
    }

    modifier onlyStartFuture() {
        require(hasRole(START_FUTURE, msg.sender), "RoleCheckable: Caller should have START FUTURE Role");
        _;
    }

    modifier onlyHarvestReward() {
        require(hasRole(HARVEST_REWARDS, msg.sender), "RoleCheckable: Caller should have HARVEST REWARDS Role");
        _;
    }

    modifier onlyController() {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "RoleCheckable: Caller should be CONTROLLER");
        _;
    }

    modifier onlyFuture() {
        require(hasRole(FUTURE_ROLE, msg.sender), "RoleCheckable: Caller should have FUTURE Role");
        _;
    }
}
