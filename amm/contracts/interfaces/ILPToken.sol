// SPDX-License-Identifier: BUSL-1.1

import "contracts/interfaces/IERC1155.sol";

pragma solidity ^0.7.6;

interface ILPToken is IERC1155 {
    function amms(uint64 _ammId) external view returns (address);

    /**
     * @notice Getter for AMM id
     * @param _id the id of the LP Token
     * @return AMM id
     */
    function getAMMId(uint256 _id) external pure returns (uint64);

    /**
     * @notice Getter for PeriodIndex
     * @param _id the id of the LP Token
     * @return period index
     */
    function getPeriodIndex(uint256 _id) external pure returns (uint64);

    /**
     * @notice Getter for PairId
     * @param _id the index of the Pair
     * @return pair index
     */
    function getPairId(uint256 _id) external pure returns (uint32);
}
