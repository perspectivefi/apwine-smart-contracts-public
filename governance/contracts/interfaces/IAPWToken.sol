pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title APW token contract interface
 * @notice Governance token of the APWine protocol
 */
interface IAPWToken is IERC20Upgradeable {
    /**
     * @notice Mint tokens to the specified wallet
     * @param _to the address of the receiver
     * @param _amount the amount of token to mint
     * @dev caller must be granted to MINTER_ROLE
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @notice Intializer
     * @param _APWINEDAO the address of the owner address
     */
    function initialize(address _APWINEDAO) external;
}
