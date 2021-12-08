// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

interface ITokensFactory {
    function deployNextFutureYieldToken(uint256 nextPeriodIndex) external returns (address newToken);

    function deployPT(
        string memory _ibtSymbol,
        uint256 _ibtDecimals,
        string memory _platformName,
        uint256 _perioDuration
    ) external returns (address newToken);
}
