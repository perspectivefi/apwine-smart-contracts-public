// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "contracts/utils/RegistryStorage.sol";
import "contracts/interfaces/apwine/IFutureVault.sol";
import "contracts/interfaces/apwine/IRegistry.sol";
import "contracts/interfaces/apwine/IController.sol";
import "contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "contracts/utils/APWineNaming.sol";

/**
 * @title TokenFactory contract
 * @notice The TokenFactory deployed the token of Protocol.
 */
contract TokensFactory is Initializable, RegistryStorage {
    /* Events */
    event PTDeployed(address _futureVault, address _pt);
    event FytDeployed(address _futureVault, address _fyt);
    event ProxyCreated(address proxy);
    /* Modifiers */
    modifier onlyRegisteredFutureVault() {
        require(registry.isRegisteredFutureVault(msg.sender), "TokensFactory: ERR_FUTURE_ADDRESS");
        _;
    }

    /**
     * @notice Initializer of the contract
     * @param _registry the address of the registry of the contract
     * @param _admin the address of the admin of the contract
     */
    function initialize(IRegistry _registry, address _admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        registry = _registry;
    }

    /**
     * @notice Deploy the pt of the future
     */
    function deployPT(
        string memory _ibtSymbol,
        uint256 _ibtDecimals,
        string memory _platformName,
        uint256 _perioDuration
    ) external returns (address newToken) {
        string memory ibtSymbol = _getFutureIBTSymbol(_ibtSymbol, _platformName, _perioDuration);
        bytes memory payload = abi.encodeWithSignature(
            "initialize(string,string,uint8,address)",
            ibtSymbol,
            ibtSymbol,
            _ibtDecimals,
            msg.sender
        );

        newToken = _clonePositonToken(
            registry.getPTLogicAddress(),
            payload,
            keccak256(abi.encodePacked(ibtSymbol, msg.sender))
        );
        emit PTDeployed(msg.sender, newToken);
    }

    /**
     * @notice Deploy the next future yield token of the futureVault
     * @dev the caller must be a registered future vault
     */
    function deployNextFutureYieldToken(uint256 newPeriodIndex)
        external
        onlyRegisteredFutureVault
        returns (address newToken)
    {
        IFutureVault futureVault = IFutureVault(msg.sender);
        IERC20 pt = IERC20(futureVault.getPTAddress());
        IERC20 ibt = IERC20(futureVault.getIBTAddress());
        uint256 periodDuration = futureVault.PERIOD_DURATION();

        string memory tokenDenomination = _getFYTSymbol(pt.symbol(), periodDuration);
        bytes memory payload = abi.encodeWithSignature(
            "initialize(string,string,uint8,uint256,address)",
            tokenDenomination,
            tokenDenomination,
            ibt.decimals(),
            newPeriodIndex,
            address(futureVault)
        );
        newToken = _clonePositonToken(
            registry.getFYTLogicAddress(),
            payload,
            keccak256(abi.encodePacked(tokenDenomination, msg.sender, newPeriodIndex))
        );

        emit FytDeployed(msg.sender, newToken);
    }

    /**
     * @notice Getter for the symbol of the APWine IBT of one futureVault
     * @param _ibtSymbol the IBT of the external protocol
     * @param _platform the external protocol name
     * @param _periodDuration the duration of the periods for the futureVault
     * @return the generated symbol of the APWine IBT
     */
    function _getFutureIBTSymbol(
        string memory _ibtSymbol,
        string memory _platform,
        uint256 _periodDuration
    ) internal pure returns (string memory) {
        return APWineNaming.genIBTSymbol(_ibtSymbol, _platform, _periodDuration);
    }

    /**
     * @notice Getter for the symbol of the FYT of one futureVault
     * @param _ptSymbol the APWine IBT symbol for this futureVault
     * @param _periodDuration the duration of the periods for this futureVault
     * @return the generated symbol of the FYT
     */
    function _getFYTSymbol(string memory _ptSymbol, uint256 _periodDuration) internal view returns (string memory) {
        return
            APWineNaming.genFYTSymbolFromIBT(
                uint8(IController(registry.getControllerAddress()).getPeriodIndex(_periodDuration)),
                _ptSymbol
            );
    }

    /**
     * @notice Clones the position token - { returns position token address }
     *
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `master`
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone.
     *
     * @param _logic is the address of token whose behaviour needs to be mimicked
     * @param _data is the payload for the token address.
     * @param _salt is a salt used to deterministically deploy the clone
     *
     */
    function _clonePositonToken(
        address _logic,
        bytes memory _data,
        bytes32 _salt
    ) private returns (address proxy) {
        proxy = ClonesUpgradeable.cloneDeterministic(_logic, _salt);
        emit ProxyCreated(address(proxy));

        if (_data.length > 0) {
            (bool success, ) = proxy.call(_data);
            require(success);
        }
    }
}
