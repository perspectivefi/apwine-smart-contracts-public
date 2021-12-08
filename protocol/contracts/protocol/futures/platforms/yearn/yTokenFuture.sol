// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/protocol/futures/RateFutureVault.sol";
import "contracts/interfaces/platforms/yearn/IyToken.sol";

/**
 * @title Contract for yToken Future
 * @notice Handles the future mechanisms for the yToken
 * @dev Implement directly the stream future abstraction as it fits the yToken IBT
 */
contract yTokenFutureVault is RateFutureVault {
    /**
     * @notice Getter for the rate of the IBT
     * @return the uint256 rate, IBT x rate must be equal to the quantity of underlying tokens
     */
    function getIBTRate() public view override returns (uint256) {
        return yToken(address(ibt)).getPricePerFullShare();
    }
}
