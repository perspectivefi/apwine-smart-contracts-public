// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract LPToken is
    Initializable,
    ContextUpgradeable,
    AccessControlUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155PausableUpgradeable
{
    // 0xFFFFFFFF
    uint32 public constant MAX_INT_32 = type(uint32).max;
    // OxFFFFFFFFFFFFFFFF
    uint64 public constant MAX_INT_64 = type(uint64).max;

    // keccak256("MINTER_ROLE")
    bytes32 public constant MINTER_ROLE = 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6;
    // keccak256("PAUSER_ROLE")
    bytes32 public constant PAUSER_ROLE = 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a;

    mapping(uint64 => address) public amms;

    event AmmAddressSet(uint64 _ammId, address _ammAddress);

    function initialize(string memory uri) public virtual initializer {
        __LPToken_init(uri);
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE` to the account that
     * deploys the contract.
     */
    function __LPToken_init(string memory uri) internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained(uri);
        __ERC1155Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC1155Pausable_init_unchained();
        __LPToken_init_unchained();
    }

    function __LPToken_init_unchained() internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @notice burns ERC1155 LP tokens
     * @param account the address of the user
     * @param id the id of the token
     * @param value the amount to be burned
     */
    function burnFrom(
        address account,
        uint256 id,
        uint256 value
    ) external virtual {
        require(
            msg.sender == amms[uint64(id >> 192)] || account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "LPToken: caller is not owner nor approved"
        );
        _burn(account, id, value);
    }

    /**
     * @notice mints ERC1155 LP tokens
     * @param to the address of the user
     * @param _ammId the id of the AMM
     * @param _periodIndex the current period value
     * @param _pairId the index of the pair
     * @param amount units of token to mint
     * @return id for the LP Token
     */
    function mint(
        address to,
        uint64 _ammId,
        uint64 _periodIndex,
        uint32 _pairId,
        uint256 amount,
        bytes memory data
    ) external returns (uint256 id) {
        require(hasRole(MINTER_ROLE, _msgSender()), "LPToken: must have minter role to mint");

        id = _createId(_ammId, _periodIndex, _pairId);
        if (amms[_ammId] == address(0)) {
            amms[_ammId] = msg.sender;
        }
        _mint(to, id, amount, data);
    }

    /**
     * @dev Toggle pause/unpause for all token transfers.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function togglePause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "LPToken: must have pauser role to unpause");
        paused() ? _unpause() : _pause();
    }

    /**
     * @notice Getter for predicted Token ID
     * @param _ammId the id of the AMM
     * @param _periodIndex the current period value
     * @param _pairId the index of the pair
     * @return id for the LP Token
     */
    function predictTokenId(
        uint256 _ammId,
        uint256 _periodIndex,
        uint256 _pairId
    ) external pure returns (uint256) {
        return _createId(_ammId, _periodIndex, _pairId);
    }

    /**
     * @notice Setter for AMM address
     * @param _ammId the id of the amm
     * @param _ammAddress the address of the amm
     */
    function setAmmAddress(uint64 _ammId, address _ammAddress) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LPToken: must have default admin role to set amm address");
        amms[_ammId] = _ammAddress;
        emit AmmAddressSet(_ammId, _ammAddress);
    }

    /**
     * @notice Getter for AMM id
     * @param _id the id of the LP Token
     * @return AMM id
     */
    function getAMMId(uint256 _id) external pure returns (uint64) {
        return uint64(_id >> 192);
    }

    /**
     * @notice Getter for PeriodIndex
     * @param _id the id of the LP Token
     * @return period index
     */
    function getPeriodIndex(uint256 _id) external pure returns (uint64) {
        return uint64(_id >> 128) & MAX_INT_64;
    }

    /**
     * @notice Getter for PairId
     * @param _id the index of the Pair
     * @return pair index
     */
    function getPairId(uint256 _id) external pure returns (uint32) {
        return uint32(_id >> 96) & MAX_INT_32;
    }

    /**
     * AMM -> first 64 bits
     * PeriodIndex -> next 64 bits
     * PairIndex -> next 32 bits
     * Reserved(for future use cases) -> last 96 bits
     * ----------------------------
     * Total -> 256 bits
     * @notice Creates ID for the LP token
     * @param _ammId the id of the AMM
     * @param _periodIndex the current period value
     * @param _pairId the index of the pair
     * @return id for the LP Token
     */
    function _createId(
        uint256 _ammId,
        uint256 _periodIndex,
        uint256 _pairId
    ) private pure returns (uint256) {
        return (_ammId << 192) | (_periodIndex << 128) | (_pairId << 96);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable, ERC1155PausableUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    uint256[50] private __gap;
}
