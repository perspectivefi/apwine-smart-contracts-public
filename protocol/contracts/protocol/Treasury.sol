// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "contracts/utils/RoleCheckable.sol";
import "contracts/interfaces/IERC20.sol";

/**
 * @title Treasury Contract
 * @notice the treasury of the protocols, allowing storage and transfer of funds
 */
contract Treasury is Initializable, RoleCheckable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20;

    /**
     * @notice Initializer of the contract
     * @param _admin the address the admin of the contract
     */
    function initialize(address _admin) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
    }

    /**
     * @notice Send ether to an address
     * @param _recipient the address of the recipient
     * @param _amount the amount of ether to send
     */
    function sendEther(address payable _recipient, uint256 _amount) public payable nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "ERR_CALLER");
        (bool success, ) = _recipient.call{ value: _amount }("");
        require(success, "Treasury: ERR_TRANSFER");
    }

    /**
     * @notice Send erc20 tokens to an address
     * @param _erc20 the address of the erc20 token
     * @param _recipient the address of the recipient
     * @param _amount the amount of tokens to send
     */
    function sendToken(
        IERC20 _erc20,
        address _recipient,
        uint256 _amount
    ) external nonReentrant onlyAdmin {
        _erc20.safeTransfer(_recipient, _amount);
    }

    /**
     * @notice Approve an address to spend an erc20 from the treasury
     * @param _erc20 the address of the erc20 token
     * @param _spender the address of the spender
     * @param _amount the approved value
     */
    function approveSpender(
        IERC20 _erc20,
        address _spender,
        uint256 _amount
    ) external nonReentrant onlyAdmin {
        _erc20.safeApprove(_spender, _amount);
    }
}
