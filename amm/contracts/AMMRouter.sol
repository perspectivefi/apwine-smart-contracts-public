// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "./interfaces/IAMM.sol";
import "./interfaces/IAMMRouter.sol";
import "./interfaces/IAMMRegistry.sol";
import "./interfaces/IERC20.sol";
import "contracts/RoleCheckable.sol";

/* Inspired from UniswapV2Router02: https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol */
contract AMMRouter is ReentrancyGuardUpgradeable, IAMMRouter, RoleCheckable {
    using SafeERC20Upgradeable for IERC20;
    using SafeMathUpgradeable for uint256;
    uint256 internal constant UNIT = 10**18;
    IAMMRegistry public registry;
    uint256 private constant MAX_UINT256 = uint256(-1);

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "AMMRouter: Deadline has expired");
        _;
    }

    modifier isValidAmm(address _ammAddress) {
        require(registry.isRegisteredAMM(_ammAddress), "AMMRouter: invalid amm address");
        _;
    }

    event RegistrySet(IAMMRegistry _registry);
    event TokenApproved(IERC20 _token, IAMM _amm);

    function initialize(IAMMRegistry _registry) public virtual initializer {
        registry = _registry;
        emit RegistrySet(_registry);
    }

    /* Swapping methods */
    function swapExactAmountIn(
        IAMM _amm,
        uint256[] calldata _pairPath, // e.g. [0, 1] -> will swap on pair 0 then 1
        uint256[] calldata _tokenPath, // e.g. [1, 0, 0, 1] -> will swap on pair 0 from token 1 to 0, then swap on pair 1 from token 0 to 1.
        uint256 _tokenAmountIn,
        uint256 _minAmountOut,
        address _to,
        uint256 _deadline
    ) public override ensure(_deadline) returns (uint256 tokenAmountOut) {
        {
            IERC20 tokenIn =
                _tokenPath[0] == 0 ? IERC20(_amm.getPTAddress()) : IERC20(_amm.getPairWithID(_pairPath[0]).tokenAddress);
            tokenIn.safeTransferFrom(msg.sender, address(this), _tokenAmountIn);
        }
        uint256 _currentTokenAmountIn = _tokenAmountIn;
        uint256 _pairPathMaxIndex = _pairPath.length;
        for (uint256 i; i < _pairPathMaxIndex; i++) {
            (_currentTokenAmountIn, ) = _amm.swapExactAmountIn(
                _pairPath[i],
                _tokenPath[2 * i],
                _currentTokenAmountIn,
                _tokenPath[2 * i + 1],
                0, // ignore _minAmountOut for intermediary swaps
                i == _pairPathMaxIndex - 1 ? _to : address(this) // send to recipient only for last swap
            );
        }
        require(_currentTokenAmountIn >= _minAmountOut, "AMMRouter: Min amount not reached");
        tokenAmountOut = _currentTokenAmountIn; // return value of last swapExactAmountIn call
    }

    function swapExactAmountOut(
        IAMM _amm,
        uint256[] calldata _pairPath, // e.g. [0, 1] -> will swap on pair 0 then 1
        uint256[] calldata _tokenPath, // e.g. [1, 0, 0, 1] -> will swap on pair 0 from token 1 to 0, then swap on pair 1 from token 0 to 1.
        uint256 _maxAmountIn,
        uint256 _tokenAmountOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 tokenAmountIn) {
        tokenAmountIn = getAmountIn(_amm, _pairPath, _tokenPath, _tokenAmountOut);
        require(tokenAmountIn <= _maxAmountIn, "AMMRouter: Max amount in reached");
        swapExactAmountIn(_amm, _pairPath, _tokenPath, tokenAmountIn, _tokenAmountOut, _to, _deadline);
    }

    /* getter methods */
    function getSpotPrice(
        IAMM _amm,
        uint256[] calldata _pairPath, // e.g. [0, 1] -> will swap on pair 0 then 1
        uint256[] calldata _tokenPath // e.g. [1, 0, 0, 1] -> will swap on pair 0 from token 1 to 0, then swap on pair 1 from token 0 to 1.
    ) external view override returns (uint256 spotPrice) {
        uint256 _pairPathMaxIndex = _pairPath.length;
        if (_pairPathMaxIndex == 0) {
            return spotPrice;
        }
        spotPrice = UNIT;
        for (uint256 i; i < _pairPathMaxIndex; i++) {
            uint256 currentSpotPrice = _amm.getSpotPrice(_pairPath[i], _tokenPath[2 * i], _tokenPath[2 * i + 1]);
            spotPrice = spotPrice.mul(currentSpotPrice) / UNIT;
        }
        return spotPrice;
    }

    function getAmountIn(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _tokenAmountOut
    ) public view override returns (uint256 tokenAmountIn) {
        uint256 _currentTokenAmountIn = _tokenAmountOut;
        uint256 _pairPathMaxIndex = _pairPath.length;
        for (uint256 i = _pairPathMaxIndex; i > 0; i--) {
            (_currentTokenAmountIn, ) = _amm.calcInAndSpotGivenOut(
                _pairPath[i - 1],
                _tokenPath[2 * i - 2],
                MAX_UINT256,
                _tokenPath[2 * i - 1],
                _currentTokenAmountIn
            );
        }
        tokenAmountIn = _currentTokenAmountIn;
    }

    function getAmountOut(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _tokenAmountIn
    ) external view override returns (uint256 tokenAmountOut) {
        uint256 _currentTokenAmountOut = _tokenAmountIn;
        uint256 _pairPathMaxIndex = _pairPath.length;
        for (uint256 i; i < _pairPathMaxIndex; i++) {
            (_currentTokenAmountOut, ) = _amm.calcOutAndSpotGivenIn(
                _pairPath[i],
                _tokenPath[2 * i],
                _currentTokenAmountOut,
                _tokenPath[2 * i + 1],
                0
            );
        }
        tokenAmountOut = _currentTokenAmountOut;
    }

    /* Approval methods */
    function setRegistry(IAMMRegistry _registry) external isAdmin {
        registry = _registry;
        emit RegistrySet(_registry);
    }

    function updateFYTApprovalOf(IAMM _amm) external isValidAmm(address(_amm)) {
        IERC20 fyt = IERC20(_amm.getFYTAddress());
        fyt.approve(address(_amm), MAX_UINT256);
        emit TokenApproved(fyt, _amm);
    }

    function updateAllTokenApprovalOf(IAMM _amm) external isValidAmm(address(_amm)) {
        IERC20 fyt = IERC20(_amm.getFYTAddress());
        IERC20 pt = IERC20(_amm.getPTAddress());
        IERC20 underlying = IERC20(_amm.getUnderlyingOfIBTAddress());
        fyt.approve(address(_amm), MAX_UINT256);
        pt.approve(address(_amm), MAX_UINT256);
        underlying.approve(address(_amm), MAX_UINT256);
        emit TokenApproved(fyt, _amm);
        emit TokenApproved(pt, _amm);
        emit TokenApproved(underlying, _amm);
    }
}
