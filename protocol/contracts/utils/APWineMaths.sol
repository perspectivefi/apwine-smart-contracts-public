// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

library APWineMaths {
    using SafeMathUpgradeable for uint256;

    /**
     * @notice scale an input
     * @param _actualValue the original value of the input
     * @param _initialSum the scaled value of the sum of the inputs
     * @param _actualSum the current value of the sum of the inputs
     */
    function getScaledInput(
        uint256 _actualValue,
        uint256 _initialSum,
        uint256 _actualSum
    ) internal pure returns (uint256) {
        if (_initialSum == 0 || _actualSum == 0) return _actualValue;
        return (_actualValue.mul(_initialSum)).div(_actualSum);
    }

    /**
     * @notice scale back a value to the output
     * @param _scaledOutput the current scaled output
     * @param _initialSum the scaled value of the sum of the inputs
     * @param _actualSum the current value of the sum of the inputs
     */
    function getActualOutput(
        uint256 _scaledOutput,
        uint256 _initialSum,
        uint256 _actualSum
    ) internal pure returns (uint256) {
        if (_initialSum == 0 || _actualSum == 0) return 0;
        return (_scaledOutput.mul(_actualSum)).div(_initialSum);
    }
}
