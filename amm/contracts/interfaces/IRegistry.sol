// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IRegistry {
    /**
     * @notice Initializer of the contract
     * @param _admin the address of the admin of the contract
     */
    function initialize(address _admin) external;

    /* Setters */
    /**
     * @notice Setter for the treasury address
     * @param _newTreasury the address of the new treasury
     */
    function setTreasury(address _newTreasury) external;

    /**
     * @notice Setter for the controller address
     * @param _newController the address of the new controller
     */
    function setController(address _newController) external;

    /**
     * @notice Setter for the APW token address
     * @param _newAPW the address of the APW token
     */
    function setAPW(address _newAPW) external;

    /**
     * @notice Setter for the proxy factory address
     * @param _proxyFactory the address of the new proxy factory
     */
    function setProxyFactory(address _proxyFactory) external;

    /**
     * @notice Setter for the APWine IBT logic address
     * @param _PTLogic the address of the new APWine IBT logic
     */
    function setPTLogic(address _PTLogic) external;

    /**
     * @notice Setter for the APWine FYT logic address
     * @param _FYTLogic the address of the new APWine FYT logic
     */
    function setFYTLogic(address _FYTLogic) external;

    /**
     * @notice Setter for the maths utils address
     * @param _mathsUtils the address of the new math utils
     */
    function setMathsUtils(address _mathsUtils) external;

    /**
     * @notice Setter for the naming utils address
     * @param _namingUtils the address of the new naming utils
     */
    function setNamingUtils(address _namingUtils) external;

    /**
     * @notice Getter for the controller address
     * @return the address of the controller
     */
    function getControllerAddress() external view returns (address);

    /**
     * @notice Getter for the treasury address
     * @return the address of the treasury
     */
    function getTreasuryAddress() external view returns (address);

    /**
     * @notice Getter for the tokens factory address
     * @return the address of the tokens factory
     */
    function getTokensFactoryAddress() external view returns (address);

    /**
     * @notice Getter for the DAO address
     * @return the address of the DAO that has admin rights on the APW token
     */
    function getDAOAddress() external returns (address);

    /**
     * @notice Getter for the APW token address
     * @return the address the APW token
     */
    function getAPWAddress() external view returns (address);

    /**
     * @notice Getter for the AMM factory address
     * @return the AMM factory address
     */
    function getAMMFactoryAddress() external view returns (address);

    /**
     * @notice Getter for the token factory address
     * @return the token factory address
     */
    function getTokenFactoryAddress() external view returns (address);

    /**
     * @notice Getter for the proxy factory address
     * @return the proxy factory address
     */
    function getProxyFactoryAddress() external view returns (address);

    /**
     * @notice Getter for APWine IBT logic address
     * @return the APWine IBT logic address
     */
    function getPTLogicAddress() external view returns (address);

    /**
     * @notice Getter for APWine FYT logic address
     * @return the APWine FYT logic address
     */
    function getFYTLogicAddress() external view returns (address);

    /**
     * @notice Getter for APWine AMM logic address
     * @return the APWine AMM logic address
     */
    function getAMMLogicAddress() external view returns (address);

    /**
     * @notice Getter for APWine AMM LP token logic address
     * @return the APWine AMM LP token logic address
     */
    function getAMMLPTokenLogicAddress() external view returns (address);

    /**
     * @notice Getter for math utils address
     * @return the math utils address
     */
    function getMathsUtils() external view returns (address);

    /**
     * @notice Getter for naming utils address
     * @return the naming utils address
     */
    function getNamingUtils() external view returns (address);

    /* Futures */
    /**
     * @notice Add a future to the registry
     * @param _future the address of the future to add to the registry
     */
    function addFuture(address _future) external;

    /**
     * @notice Remove a future from the registry
     * @param _future the address of the future to remove from the registry
     */
    function removeFuture(address _future) external;

    /**
     * @notice Getter to check if a future is registered
     * @param _future the address of the future to check the registration of
     * @return true if it is, false otherwise
     */
    function isRegisteredFuture(address _future) external view returns (bool);

    /**
     * @notice Getter to check if an AMM is registered
     * @param _ammAddress the address of the amm to check the registration of
     * @return true if it is, false otherwise
     */
    function isRegisteredAMM(address _ammAddress) external view returns (bool);

    /**
     * @notice Getter for the future registered at an index
     * @param _index the index of the future to return
     * @return the address of the corresponding future
     */
    function getFutureAt(uint256 _index) external view returns (address);

    /**
     * @notice Getter for number of future registered
     * @return the number of future registered
     */
    function futureCount() external view returns (uint256);
}
