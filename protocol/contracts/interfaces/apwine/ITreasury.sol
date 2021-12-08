// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

interface ITreasury {
    /**
     * @notice send erc20 tokens to an address
     * @param _erc20 the address of the erc20 token
     * @param _recipient the address of the recipient
     * @param _amount the amount of tokens to send
     */
    function sendToken(
        address _erc20,
        address _recipient,
        uint256 _amount
    ) external;

    /**
     * @notice send ether to an address
     * @param _recipient the address of the recipient
     * @param _amount the amount of ether to send
     */
    function sendEther(address payable _recipient, uint256 _amount) external payable;

    /**
     * @notice approve an address to spend an erc20 from the treasury
     * @param _erc20 the address of the erc20 token
     * @param _spender the address of the spender
     * @param _amount the approved value
     */
    function approveSpender(
        address _erc20,
        address _spender,
        uint256 _amount
    ) external;
}
