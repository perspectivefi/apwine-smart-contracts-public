// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/futureWallets/RateFutureWallet.sol";

/**
 * @title Contract for yToken Future Wallet
 * @notice Handles the future wallet mechanisms for the yearn platform
 * @dev Implement directly the rate future wallet abstraction as it fits the yToken IBT
 */
contract yTokenFutureWallet is RateFutureWallet {

}
