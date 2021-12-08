// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/futureWallets/StreamFutureWallet.sol";

/**
 * @title Rate Future Wallet abstraction
 * @notice Abstraction for the future wallets that works with an IBT whose value incorporates the fees and with stream tokens
 * @dev Override future wallet abstraction with the particular functioning of rate and stream based IBT
 */
abstract contract HybridFutureWallet is StreamFutureWallet {

}
