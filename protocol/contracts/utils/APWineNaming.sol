// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

library APWineNaming {
    using SafeMathUpgradeable for uint256;

    /**
     * @notice generate the symbol of the FYT
     * @param _index the index of the current period
     * @param _ibtSymbol the symbol of the IBT
     * @param _platform the platform name
     * @param _periodDuration the period duration
     * @return the symbol for the FYT
     * @dev i.e 30D-AAVE-ADAI-2
     */
    function genFYTSymbol(
        uint8 _index,
        string memory _ibtSymbol,
        string memory _platform,
        uint256 _periodDuration
    ) internal pure returns (string memory) {
        return concatenate(genIBTSymbol(_ibtSymbol, _platform, _periodDuration), concatenate("-", uintToString(_index)));
    }

    /**
     * @notice generate the symbol from the PT
     * @param _index the index of the current period
     * @param _ibtSymbol the symbol of the IBT
     * @return the symbol for the FYT
     * @dev i.e ADAI-2
     */
    function genFYTSymbolFromIBT(uint8 _index, string memory _ibtSymbol) internal pure returns (string memory) {
        return concatenate(_ibtSymbol, concatenate("-", uintToString(_index)));
    }

    /**
     * @notice generate the PT symbol
     * @param _ibtSymbol the symbol of the IBT of the future
     * @param _platform the platform name
     * @param _periodDuration the period duration
     * @return the symbol for the PT
     * @dev i.e 30D-AAVE-ADAI
     */
    function genIBTSymbol(
        string memory _ibtSymbol,
        string memory _platform,
        uint256 _periodDuration
    ) internal pure returns (string memory) {
        return
            concatenate(
                getPeriodDurationDenominator(_periodDuration),
                concatenate("-", concatenate(_platform, concatenate("-", _ibtSymbol)))
            );
    }

    /**
     * @notice generate the period denominator
     * @param _periodDuration the period duration
     * @return the period denominator
     * @dev i.e 30D
     */
    function getPeriodDurationDenominator(uint256 _periodDuration) internal pure returns (string memory) {
        if (_periodDuration >= 1 days) {
            uint256 numberOfdays = _periodDuration.div(1 days);
            return string(concatenate(uintToString(numberOfdays), "D"));
        }
        return "CUSTOM";
    }

    function uintToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }

    function concatenate(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}
