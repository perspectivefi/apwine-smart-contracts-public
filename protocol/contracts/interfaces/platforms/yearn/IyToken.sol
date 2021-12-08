// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/interfaces/IERC20.sol";

interface yToken is IERC20 {
    function getPricePerFullShare() external view returns (uint256);
}
