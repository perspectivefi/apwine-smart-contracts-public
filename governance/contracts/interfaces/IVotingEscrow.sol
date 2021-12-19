pragma solidity >=0.7.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title APW token contract interface
 * @notice Governance token of the APWine protocol
 */
interface IVotingEscrow {
    function totalSupplyAt(uint256 _block) external view returns (uint256);

    function balanceOfAt(address _addr, uint256 _block) external view returns (uint256);
}
