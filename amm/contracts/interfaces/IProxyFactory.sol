// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

interface IProxyFactory {
    function deployMinimal(
        address _logic,
        bytes calldata _data,
        bytes32 _salt
    ) external returns (address proxy);
}
