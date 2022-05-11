// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";

import "./interfaces/IAMM.sol";
import "./interfaces/IAMMRouterV1.sol";
import "./interfaces/IAMMRegistry.sol";
import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract AMMRouterV1 is IAMMRouterV1, AccessControlUpgradeable {
    using SafeERC20Upgradeable for IERC20;
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 internal constant UNIT = 10**18;
    uint256 private constant MAX_UINT256 = uint256(-1);
    bytes32 internal constant ADMIN_ROLE = 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775;
    bytes32 internal constant WHITELIST_ROLE = 0xdc72ed553f2544c34465af23b847953efeb813428162d767f9ba5f4013be6760;

    IAMMRegistry public registry;
    uint256 public GOVERNANCE_FEE;
    mapping(address => uint256) public REFERRAL_FEE; // % of the governance fee
    EnumerableSetUpgradeable.AddressSet internal referralAddresses;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "AMMRouterV1: Deadline has expired");
        _;
    }

    modifier isValidAmm(address _ammAddress) {
        require(registry.isRegisteredAMM(_ammAddress), "AMMRouterV1: invalid amm address");
        _;
    }

    event RegistrySet(IAMMRegistry _registry);
    event TokenApproved(IERC20 _token, IAMM _amm);
    event GovernanceFeeUpdated(uint256 _fee);
    event GovernanceFeeCollected(IERC20 _token, uint256 _amount, address _recipient);
    event ReferralRecipientAdded(address _recipient);
    event ReferralRecipientRemoved(address _recipient);
    event ReferralSet(address _recipient, uint256 _fee);
    event ReferralFeePaid(address _recipient, uint256 _feeAmount);

    function initialize(IAMMRegistry _registry, address _admin) public virtual initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
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
        uint256 _deadline,
        address _referralRecipient
    ) public override ensure(_deadline) returns (uint256 tokenAmountOut) {
        uint256 _currentTokenAmountIn = _pushFees(_amm, _pairPath, _tokenPath, _tokenAmountIn, _referralRecipient, false);

        uint256 _pairPathMaxIndex = _pairPath.length;
        require(_pairPathMaxIndex <= 2 && _pairPathMaxIndex > 0, "AMMRouterV1: invalid path length");
        (_currentTokenAmountIn, ) = _amm.swapExactAmountIn(
            _pairPath[0],
            _tokenPath[0],
            _currentTokenAmountIn,
            _tokenPath[1],
            0, // ignore _minAmountOut for intermediary swaps
            _pairPathMaxIndex == 1 ? _to : address(this) // send to recipient only for last swap
        );

        if (_pairPathMaxIndex == 2) {
            (_currentTokenAmountIn, ) = _amm.swapExactAmountIn(
                _pairPath[1],
                _tokenPath[2],
                _currentTokenAmountIn,
                _tokenPath[3],
                0, // ignore _minAmountOut for intermediary swaps
                _to // send to recipient only for last swap
            );
        }

        require(_currentTokenAmountIn >= _minAmountOut, "AMMRouterV1: Min amount not reached");
        tokenAmountOut = _currentTokenAmountIn; // return value of last swapExactAmountIn call
    }

    function _pushFeesCalculation(uint256 _tokenAmountIn, bool _isSwappingOut)
        internal
        returns (
            uint256 _currentAmountIn,
            uint256 _feeAmount,
            uint256 _pushAmount
        )
    {
        if (_isSwappingOut) {
            _currentAmountIn = _tokenAmountIn.mul(UNIT).div(UNIT - GOVERNANCE_FEE); // deScale currentAmout
            _feeAmount = _currentAmountIn.sub(_tokenAmountIn);
            _pushAmount = _currentAmountIn;
        } else {
            _currentAmountIn = _tokenAmountIn.mul(UNIT - GOVERNANCE_FEE) / UNIT; // Scale currentAmout
            _feeAmount = _tokenAmountIn.sub(_currentAmountIn);
            _pushAmount = _tokenAmountIn;
        }
    }

    function _pushFees(
        IAMM _amm,
        uint256[] calldata _pairPath, // e.g. [0, 1] -> will swap on pair 0 then 1
        uint256[] calldata _tokenPath, // e.g. [1, 0, 0, 1] -> will swap on pair 0 from token 1 to 0, then swap on pair 1 from token 0 to 1.
        uint256 _tokenAmountIn,
        address _referralRecipient,
        bool _isSwappingOut
    ) internal returns (uint256 _currentAmountIn) {
        uint256 _feeAmount;
        uint256 _pushAmount;
        IERC20 tokenIn =
            _tokenPath[0] == 0 ? IERC20(_amm.getPTAddress()) : IERC20(_amm.getPairWithID(_pairPath[0]).tokenAddress);

        (_currentAmountIn, _feeAmount, _pushAmount) = _pushFeesCalculation(_tokenAmountIn, _isSwappingOut);
        tokenIn.safeTransferFrom(msg.sender, address(this), _pushAmount);
        uint256 referralFee = REFERRAL_FEE[_referralRecipient];
        if (referralFee != 0) {
            uint256 referralFeeAmount = _feeAmount.mul(referralFee) / UNIT;
            if (referralFeeAmount > 0) {
                tokenIn.safeTransfer(_referralRecipient, referralFeeAmount);
                emit ReferralFeePaid(_referralRecipient, referralFeeAmount);
            }
        }
    }

    function swapExactAmountOut(
        IAMM _amm,
        uint256[] calldata _pairPath, // e.g. [0, 1] -> will swap on pair 0 then 1
        uint256[] calldata _tokenPath, // e.g. [1, 0, 0, 1] -> will swap on pair 0 from token 1 to 0, then swap on pair 1 from token 0 to 1.
        uint256 _maxAmountIn,
        uint256 _tokenAmountOut,
        address _to,
        uint256 _deadline,
        address _referralRecipient
    ) external override ensure(_deadline) returns (uint256 tokenAmountIn) {
        uint256 _pairPathMaxIndex = _pairPath.length;
        require(_pairPathMaxIndex <= 2 && _pairPathMaxIndex > 0, "AMMRouterswapExactAmountOutV1: invalid path length");

        uint256 currentAmountInWithoutGovernance =
            _getAmountInWithoutGovernance(_amm, _pairPath, _tokenPath, _tokenAmountOut);
        _pushFees(_amm, _pairPath, _tokenPath, currentAmountInWithoutGovernance, _referralRecipient, true);
        require(currentAmountInWithoutGovernance <= _maxAmountIn, "AMMRouterV1: Max amount in reached");
        tokenAmountIn = _executeSwap(_amm, _pairPath, _tokenPath, currentAmountInWithoutGovernance, _tokenAmountOut, _to);
    }

    function _executeSwap(
        IAMM _amm,
        uint256[] memory _pairPath,
        uint256[] memory _tokenPath,
        uint256 amountIn,
        uint256 _tokenAmountOut,
        address _to
    ) private returns (uint256 tokenAmountIn) {
        uint256[] memory pairPath = new uint256[](1);
        uint256[] memory tokenPath = new uint256[](2);
        uint256 firstSwapAmountOut;
        if (_pairPath.length == 2) {
            pairPath[0] = _pairPath[1];
            tokenPath[0] = _tokenPath[2];
            tokenPath[1] = _tokenPath[3];
            firstSwapAmountOut = _getAmountInWithoutGovernance(_amm, pairPath, tokenPath, _tokenAmountOut);

            (tokenAmountIn, ) = _amm.swapExactAmountOut(
                _pairPath[0],
                _tokenPath[0],
                amountIn,
                _tokenPath[1],
                firstSwapAmountOut,
                address(this)
            );
        } else {
            tokenPath[0] = _tokenPath[0];
            tokenPath[1] = _tokenPath[1];
            firstSwapAmountOut = amountIn;
        }

        _amm.swapExactAmountOut(
            _pairPath.length == 2 ? _pairPath[1] : _pairPath[0],
            tokenPath[0],
            firstSwapAmountOut,
            tokenPath[1],
            _tokenAmountOut,
            _to // send to recipient only for last swap
        );
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

    function _getAmountInWithoutGovernance(
        IAMM _amm,
        uint256[] memory _pairPath,
        uint256[] memory _tokenPath,
        uint256 _tokenAmountOut
    ) internal view returns (uint256 _currentTokenAmountInWithoutGovernance) {
        _currentTokenAmountInWithoutGovernance = _tokenAmountOut;
        uint256 _pairPathMaxIndex = _pairPath.length;
        for (uint256 i = _pairPathMaxIndex; i > 0; i--) {
            (_currentTokenAmountInWithoutGovernance, ) = _amm.calcInAndSpotGivenOut(
                _pairPath[i - 1],
                _tokenPath[2 * i - 2],
                MAX_UINT256,
                _tokenPath[2 * i - 1],
                _currentTokenAmountInWithoutGovernance
            );
        }
    }

    function getAmountIn(
        IAMM _amm,
        uint256[] memory _pairPath,
        uint256[] memory _tokenPath,
        uint256 _tokenAmountOut
    ) public view override returns (uint256 tokenAmountIn) {
        uint256 _currentTokenAmountIn = _getAmountInWithoutGovernance(_amm, _pairPath, _tokenPath, _tokenAmountOut);
        tokenAmountIn = _currentTokenAmountIn.mul(UNIT).div(UNIT - GOVERNANCE_FEE);
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
        tokenAmountOut = _currentTokenAmountOut.mul(UNIT - GOVERNANCE_FEE) / UNIT;
    }

    /* Approval methods */
    function setRegistry(IAMMRegistry _registry) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "AMMRouterV1: Caller is not an admin");
        registry = _registry;
        emit RegistrySet(_registry);
    }

    function setGovernanceFee(uint256 _fee) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "AMMRouterV1: Caller is not an admin");
        require(_fee < UNIT, "AMMRouterV1: Invalid fee value");
        GOVERNANCE_FEE = _fee;
        emit GovernanceFeeUpdated(_fee);
    }

    function setReferral(address _recipient, uint256 _fee) external {
        require(hasRole(WHITELIST_ROLE, msg.sender), "AMMRouterV1: Caller cannot doesnt have whitelist role");
        require(_fee <= UNIT, "AMMRouterV1: Invalid referral fee");
        if (_fee == 0) {
            delete REFERRAL_FEE[_recipient];
            referralAddresses.remove(_recipient);
            emit ReferralRecipientRemoved(_recipient);
        } else {
            if (referralAddresses.add(_recipient)) emit ReferralRecipientAdded(_recipient);
            REFERRAL_FEE[_recipient] = _fee;
            emit ReferralSet(_recipient, _fee);
        }
    }

    function collectGovernanceFee(IERC20 _token, address _recipient) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "AMMRouterV1: Caller is not an admin");
        uint256 amount = _token.balanceOf(address(this));
        _token.safeTransfer(_recipient, amount);
        emit GovernanceFeeCollected(_token, amount, _recipient);
    }

    function updateFYTApprovalOf(IAMM _amm) external isValidAmm(address(_amm)) {
        IERC20 fyt = IERC20(_amm.getFYTAddress());
        fyt.safeIncreaseAllowance(address(_amm), MAX_UINT256.sub(fyt.allowance(address(this), address(_amm))));
        emit TokenApproved(fyt, _amm);
    }

    function updateAllTokenApprovalOf(IAMM _amm) external isValidAmm(address(_amm)) {
        IERC20 fyt = IERC20(_amm.getFYTAddress());
        IERC20 pt = IERC20(_amm.getPTAddress());
        IERC20 underlying = IERC20(_amm.getUnderlyingOfIBTAddress());
        fyt.safeIncreaseAllowance(address(_amm), MAX_UINT256.sub(fyt.allowance(address(this), address(_amm))));
        pt.safeIncreaseAllowance(address(_amm), MAX_UINT256.sub(pt.allowance(address(this), address(_amm))));
        underlying.safeIncreaseAllowance(address(_amm), MAX_UINT256.sub(underlying.allowance(address(this), address(_amm))));
        emit TokenApproved(fyt, _amm);
        emit TokenApproved(pt, _amm);
        emit TokenApproved(underlying, _amm);
    }
}