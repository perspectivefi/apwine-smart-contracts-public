// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "contracts/interfaces/IAMM.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/ILPToken.sol";
import "contracts/interfaces/IFutureVault.sol";
import "contracts/interfaces/IFutureWallet.sol";
import "contracts/interfaces/IController.sol";
import "./library/AMMMaths.sol";
import "contracts/RoleCheckable.sol";

contract AMM is IAMM, RoleCheckable {
    using AMMMathsUtils for uint256;
    using SafeERC20Upgradeable for IERC20;

    // ERC-165 identifier for the main token standard.
    bytes4 public constant ERC1155_ERC165 = git;

    // keccak256("ROUTER_ROLE")
    bytes32 internal constant ROUTER_ROLE = 0x7a05a596cb0ce7fdea8a1e1ec73be300bdb35097c944ce1897202f7a13122eb2;

    uint64 public override ammId;

    IFutureVault private futureVault;
    uint256 public swapFee;

    IERC20 private ibt;
    IERC20 private pt;
    IERC20 private underlyingOfIBT;
    IERC20 private fyt;

    address internal feesRecipient;

    ILPToken private poolTokens;

    uint256 private constant BASE_WEIGHT = 5 * 10**17;

    enum AMMGlobalState { Created, Activated, Paused }
    AMMGlobalState private state;

    uint256 public currentPeriodIndex;
    uint256 public lastBlockYieldRecorded;
    uint256 public lastYieldRecorded;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    mapping(uint256 => mapping(uint256 => uint256)) private poolToUnderlyingAtPeriod;
    mapping(uint256 => uint256) private generatedYieldAtPeriod;
    mapping(uint256 => uint256) private underlyingSavedPerPeriod;
    mapping(uint256 => mapping(uint256 => uint256)) private totalLPSupply;

    mapping(uint256 => Pair) private pairs;
    mapping(address => uint256) private tokenToPairID;

    event AMMStateChanged(AMMGlobalState _newState);
    event PairCreated(uint256 indexed _pairID, address _token);
    event LiquidityCreated(address _user, uint256 _pairID);
    event PoolJoined(address _user, uint256 _pairID, uint256 _poolTokenAmount);
    event PoolExited(address _user, uint256 _pairID, uint256 _poolTokenAmount);
    event LiquidityIncreased(address _from, uint256 _pairID, uint256 _tokenID, uint256 _amount);
    event LiquidityDecreased(address _to, uint256 _pairID, uint256 _tokenID, uint256 _amount);
    event Swapped(
        address _user,
        uint256 _pairID,
        uint256 _tokenInID,
        uint256 _tokenOutID,
        uint256 _tokenAmountIn,
        uint256 _tokenAmountOut,
        address _to
    );
    event PeriodSwitched(uint256 _newPeriodIndex);
    event WeightUpdated(address _token, uint256[2] _newWeights);
    event ExpiredTokensWithdrawn(address _user, uint256 _amount);
    event SwappingFeeSet(uint256 _swapFee);

    /* General State functions */

    /**
     * @notice AMM initializer
     * @param _ammId We might need to create an AMMFactory to maintain a counter index which can be passed as _ammId
     * @param _underlyingOfIBTAddress the address of the IBT underlying
     * @param _futureVault the address of the future vault
     * @param _poolTokens ERC1155 contract to maintain LPTokens
     * @param _admin the address of the contract admin
     */
    function initialize(
        uint64 _ammId,
        address _underlyingOfIBTAddress,
        address _futureVault,
        ILPToken _poolTokens,
        address _admin,
        address _feesRecipient,
        address _router
    ) public virtual initializer {
        require(_poolTokens.supportsInterface(ERC1155_ERC165), "AMM: Interface not supported");
        require(_underlyingOfIBTAddress != address(0), "AMM: Invalid underlying address");
        require(_futureVault != address(0), "AMM: Invalid future address");
        require(_admin != address(0), "AMM: Invalid admin address");
        require(_feesRecipient != address(0), "AMM: Invalid fees recipient address");

        ammId = _ammId;
        poolTokens = _poolTokens;
        feesRecipient = _feesRecipient;
        futureVault = IFutureVault(_futureVault);
        ibt = IERC20(futureVault.getIBTAddress());

        address _ptAddress = futureVault.getPTAddress();

        // Initialize first PT x Underlying pool
        underlyingOfIBT = IERC20(_underlyingOfIBTAddress);
        pt = IERC20(_ptAddress);

        // Instantiate weights of first pool
        tokenToPairID[_ptAddress] = 0;
        _createPair(AMMMaths.ZERO_256, _underlyingOfIBTAddress);
        _status = _NOT_ENTERED;
        // Role initialization
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(ROUTER_ROLE, _router);

        state = AMMGlobalState.Created; // waiting to be finalized
    }

    function _createPair(uint256 _pairID, address _tokenAddress) internal {
        pairs[_pairID] = Pair({
            tokenAddress: _tokenAddress,
            weights: [BASE_WEIGHT, BASE_WEIGHT],
            balances: [AMMMaths.ZERO_256, AMMMaths.ZERO_256],
            liquidityIsInitialized: false
        });
        tokenToPairID[_tokenAddress] = _pairID;
        emit PairCreated(_pairID, _tokenAddress);
    }

    function togglePauseAmm() external override isAdmin {
        require(state != AMMGlobalState.Created, "AMM: Not Initialized");
        state = state == AMMGlobalState.Activated ? AMMGlobalState.Paused : AMMGlobalState.Activated;
        emit AMMStateChanged(state);
    }

    /**
     * @notice finalize the initialization of the amm
     * @dev must be called during the first period the amm is supposed to be active, will initialize fyt address
     */
    function finalize() external override isAdmin {
        require(state == AMMGlobalState.Created, "AMM: Already Finalized");
        currentPeriodIndex = futureVault.getCurrentPeriodIndex();
        require(currentPeriodIndex >= 1, "AMM: Invalid period ID");

        address fytAddress = futureVault.getFYTofPeriod(currentPeriodIndex);
        fyt = IERC20(fytAddress);

        _createPair(uint256(1), fytAddress);

        state = AMMGlobalState.Activated;
        emit AMMStateChanged(AMMGlobalState.Activated);
    }

    /**
     * @notice switch period
     * @dev must be called after each new period switch
     * @dev the switch will auto renew part of the tokens and update the weights accordingly
     */
    function switchPeriod() external override {
        ammIsActive();
        require(futureVault.getCurrentPeriodIndex() > currentPeriodIndex, "AMM: Invalid period index");
        _renewUnderlyingPool();
        _renewFYTPool();
        generatedYieldAtPeriod[currentPeriodIndex] = futureVault.getYieldOfPeriod(currentPeriodIndex);
        currentPeriodIndex = futureVault.getCurrentPeriodIndex();
        emit PeriodSwitched(currentPeriodIndex);
    }

    function _renewUnderlyingPool() internal {
        underlyingSavedPerPeriod[currentPeriodIndex] = pairs[0].balances[1];
        uint256 oldIBTBalance = ibt.balanceOf(address(this));
        uint256 ptBalance = pairs[0].balances[0];
        if (ptBalance != 0) {
            IController(futureVault.getControllerAddress()).withdraw(address(futureVault), ptBalance);
        }
        _saveExpiredIBTs(0, ibt.balanceOf(address(this)).sub(oldIBTBalance), currentPeriodIndex);
        _resetPair(0);
    }

    function _renewFYTPool() internal {
        address fytAddress = futureVault.getFYTofPeriod(futureVault.getCurrentPeriodIndex());
        pairs[1].tokenAddress = fytAddress;
        fyt = IERC20(fytAddress);
        uint256 oldIBTBalance = ibt.balanceOf(address(this));
        uint256 ptBalance = pairs[1].balances[0];
        if (ptBalance != 0) {
            IFutureWallet(futureVault.getFutureWalletAddress()).redeemYield(currentPeriodIndex); // redeem ibt from expired ibt
            IController(futureVault.getControllerAddress()).withdraw(address(futureVault), ptBalance); // withdraw current pt and generated fyt
        }
        _saveExpiredIBTs(1, ibt.balanceOf(address(this)).sub(oldIBTBalance), currentPeriodIndex);
        _resetPair(1);
    }

    function _resetPair(uint256 _pairID) internal {
        pairs[_pairID].balances = [uint256(0), uint256(0)];
        pairs[_pairID].weights = [BASE_WEIGHT, BASE_WEIGHT];
        pairs[_pairID].liquidityIsInitialized = false;
    }

    function _saveExpiredIBTs(
        uint256 _pairID,
        uint256 _ibtGenerated,
        uint256 _periodID
    ) internal {
        poolToUnderlyingAtPeriod[_pairID][_periodID] = futureVault.convertIBTToUnderlying(_ibtGenerated);
    }

    /**
     * @notice update the weights at each new block depending on the generated yield
     */
    function _updateWeightsFromYieldAtBlock() internal {
        (uint256 newUnderlyingWeight, uint256 yieldRecorded) = _getUpdatedUnderlyingWeightAndYield();
        if (newUnderlyingWeight != pairs[0].weights[1]) {
            lastYieldRecorded = yieldRecorded;
            lastBlockYieldRecorded = block.number;
            pairs[0].weights = [AMMMaths.UNIT - newUnderlyingWeight, newUnderlyingWeight];

            emit WeightUpdated(pairs[0].tokenAddress, pairs[0].weights);
        }
    }

    function getPTWeightInPair() external view override returns (uint256) {
        (uint256 newUnderlyingWeight, ) = _getUpdatedUnderlyingWeightAndYield();
        return AMMMaths.UNIT - newUnderlyingWeight;
    }

    function _getUpdatedUnderlyingWeightAndYield() internal view returns (uint256, uint256) {
        uint256 inverseSpotPrice = (AMMMaths.SQUARED_UNIT).div(getSpotPrice(0, 1, 0));
        uint256 yieldRecorded = futureVault.convertIBTToUnderlying(futureVault.getUnrealisedYieldPerPT());
        if (lastBlockYieldRecorded != block.number && lastYieldRecorded != yieldRecorded) {
            uint256 newSpotPrice =
                ((AMMMaths.UNIT + yieldRecorded).mul(AMMMaths.SQUARED_UNIT)).div(
                    ((AMMMaths.UNIT + lastYieldRecorded).mul(inverseSpotPrice))
                );
            if (newSpotPrice < AMMMaths.UNIT) {
                uint256[2] memory balances = pairs[0].balances;
                uint256 newUnderlyingWeight =
                    balances[1].mul(AMMMaths.UNIT).div(balances[1].add(balances[0].mul(newSpotPrice).div(AMMMaths.UNIT)));
                return (newUnderlyingWeight, yieldRecorded);
            }
        }
        return (pairs[0].weights[1], yieldRecorded);
    }

    /* Renewal functions */

    /**
     * @notice Withdraw expired LP tokens
     */
    function withdrawExpiredToken(address _user, uint256 _lpTokenId) external override {
        nonReentrant();
        _withdrawExpiredToken(_user, _lpTokenId);
        _status = _NOT_ENTERED;
    }

    function _withdrawExpiredToken(address _user, uint256 _lpTokenId) internal {
        (uint256 redeemableTokens, uint256 lastPeriodId, uint256 pairId) = getExpiredTokensInfo(_user, _lpTokenId);
        require(redeemableTokens > 0, "AMM: no redeemable token");
        uint256 userTotal = poolTokens.balanceOf(_user, _lpTokenId);
        uint256 tokenSupply = totalLPSupply[pairId][lastPeriodId];

        poolTokens.burnFrom(_user, _lpTokenId, userTotal);

        if (pairId == 0) {
            uint256 userUnderlyingAmount = underlyingSavedPerPeriod[lastPeriodId].mul(userTotal).div(tokenSupply);
            underlyingOfIBT.safeTransfer(_user, userUnderlyingAmount);
        }
        ibt.safeTransfer(_user, redeemableTokens);

        emit ExpiredTokensWithdrawn(_user, redeemableTokens);
    }

    /**
     * @notice Getter for redeemable expired tokens info
     * @param _user the address of the user to check the redeemable tokens of
     * @param _lpTokenId the lp token id
     * @return the amount, the period id and the pair id of the expired tokens of the user
     */
    function getExpiredTokensInfo(address _user, uint256 _lpTokenId)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(poolTokens.getAMMId(_lpTokenId) == ammId, "AMM: invalid amm id");
        uint256 pairID = poolTokens.getPairId(_lpTokenId);
        require(pairID < 2, "AMM: invalid pair id");
        uint256 periodIndex = poolTokens.getPeriodIndex(_lpTokenId);
        require(periodIndex <= currentPeriodIndex, "AMM: invalid period id");
        if (periodIndex == 0 || periodIndex == currentPeriodIndex) return (0, periodIndex, pairID);
        uint256 redeemable =
            poolTokens
                .balanceOf(_user, getLPTokenId(ammId, periodIndex, pairID))
                .mul(poolToUnderlyingAtPeriod[pairID][periodIndex])
                .div(totalLPSupply[pairID][periodIndex]);
        for (uint256 i = periodIndex.add(1); i < currentPeriodIndex; i++) {
            redeemable = redeemable
                .mul(AMMMaths.UNIT.add(futureVault.convertIBTToUnderlying(generatedYieldAtPeriod[i])))
                .div(AMMMaths.UNIT);
        }
        return (
            futureVault.convertUnderlyingtoIBT(
                redeemable.add(
                    redeemable.mul(futureVault.convertIBTToUnderlying(futureVault.getUnrealisedYieldPerPT())).div(
                        AMMMaths.UNIT
                    )
                )
            ),
            periodIndex,
            pairID
        );
    }

    /* Swapping functions */
    function swapExactAmountIn(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _tokenAmountIn,
        uint256 _tokenOut,
        uint256 _minAmountOut,
        address _to
    ) external override returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        tokenIdsAreValid(_tokenIn, _tokenOut);
        _updateWeightsFromYieldAtBlock();

        (tokenAmountOut, spotPriceAfter) = calcOutAndSpotGivenIn(
            _pairID,
            _tokenIn,
            _tokenAmountIn,
            _tokenOut,
            _minAmountOut
        );

        _pullToken(msg.sender, _pairID, _tokenIn, _tokenAmountIn);
        _pushToken(_to, _pairID, _tokenOut, tokenAmountOut);
        emit Swapped(msg.sender, _pairID, _tokenIn, _tokenOut, _tokenAmountIn, tokenAmountOut, _to);
        _status = _NOT_ENTERED;
        return (tokenAmountOut, spotPriceAfter);
    }

    function calcOutAndSpotGivenIn(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _tokenAmountIn,
        uint256 _tokenOut,
        uint256 _minAmountOut
    ) public view override returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        tokenIdsAreValid(_tokenIn, _tokenOut);
        uint256[2] memory balances = pairs[_pairID].balances;
        uint256[2] memory weights = pairs[_pairID].weights;
        require(weights[_tokenIn] > 0 && weights[_tokenOut] > 0, "AMM: Invalid token address");

        uint256 spotPriceBefore =
            AMMMaths.calcSpotPrice(balances[_tokenIn], weights[_tokenIn], balances[_tokenOut], weights[_tokenOut], swapFee);

        tokenAmountOut = AMMMaths.calcOutGivenIn(
            balances[_tokenIn],
            weights[_tokenIn],
            balances[_tokenOut],
            weights[_tokenOut],
            _tokenAmountIn,
            swapFee
        );
        require(tokenAmountOut >= _minAmountOut, "AMM: Min amount not reached");

        spotPriceAfter = AMMMaths.calcSpotPrice(
            balances[_tokenIn].add(_tokenAmountIn),
            weights[_tokenIn],
            balances[_tokenOut].sub(tokenAmountOut),
            weights[_tokenOut],
            swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "AMM: Math approximation error");
    }

    function swapExactAmountOut(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _maxAmountIn,
        uint256 _tokenOut,
        uint256 _tokenAmountOut,
        address _to
    ) external override returns (uint256 tokenAmountIn, uint256 spotPriceAfter) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        tokenIdsAreValid(_tokenIn, _tokenOut);
        _updateWeightsFromYieldAtBlock();

        (tokenAmountIn, spotPriceAfter) = calcInAndSpotGivenOut(_pairID, _tokenIn, _maxAmountIn, _tokenOut, _tokenAmountOut);

        _pullToken(msg.sender, _pairID, _tokenIn, tokenAmountIn);
        _pushToken(_to, _pairID, _tokenOut, _tokenAmountOut);
        emit Swapped(msg.sender, _pairID, _tokenIn, _tokenOut, tokenAmountIn, _tokenAmountOut, _to);
        _status = _NOT_ENTERED;
        return (tokenAmountIn, spotPriceAfter);
    }

    function calcInAndSpotGivenOut(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _maxAmountIn,
        uint256 _tokenOut,
        uint256 _tokenAmountOut
    ) public view override returns (uint256 tokenAmountIn, uint256 spotPriceAfter) {
        tokenIdsAreValid(_tokenIn, _tokenOut);
        uint256 inTokenBalance = pairs[_pairID].balances[_tokenIn];
        uint256 outTokenBalance = pairs[_pairID].balances[_tokenOut];
        uint256 tokenWeightIn = pairs[_pairID].weights[_tokenIn];
        uint256 tokenWeightOut = pairs[_pairID].weights[_tokenOut];
        require(tokenWeightIn > 0 && tokenWeightOut > 0, "AMM: Invalid token address");

        uint256 spotPriceBefore =
            AMMMaths.calcSpotPrice(inTokenBalance, tokenWeightIn, outTokenBalance, tokenWeightOut, swapFee);

        tokenAmountIn = AMMMaths.calcInGivenOut(
            inTokenBalance,
            tokenWeightIn,
            outTokenBalance,
            tokenWeightOut,
            _tokenAmountOut,
            swapFee
        );
        require(tokenAmountIn <= _maxAmountIn, "AMM: Max amount in reached");

        spotPriceAfter = AMMMaths.calcSpotPrice(
            inTokenBalance.add(tokenAmountIn),
            tokenWeightIn,
            outTokenBalance.sub(_tokenAmountOut),
            tokenWeightOut,
            swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "AMM: Math approximation error");
    }

    function joinSwapExternAmountIn(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _tokenAmountIn,
        uint256 _minPoolAmountOut
    ) external override returns (uint256 poolAmountOut) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);

        require(_tokenIn < 2, "AMM: Invalid Token Id");
        _updateWeightsFromYieldAtBlock();

        Pair memory pair = pairs[_pairID];

        uint256 inTokenBalance = pair.balances[_tokenIn];
        uint256 tokenWeightIn = pair.weights[_tokenIn];

        require(tokenWeightIn > 0, "AMM: Invalid token address");
        require(_tokenAmountIn <= inTokenBalance.mul(AMMMaths.MAX_IN_RATIO) / AMMMaths.UNIT, "AMM: Max in ratio reached");

        poolAmountOut = AMMMaths.calcPoolOutGivenSingleIn(
            inTokenBalance,
            tokenWeightIn,
            totalLPSupply[_pairID][currentPeriodIndex],
            AMMMaths.UNIT,
            _tokenAmountIn,
            swapFee
        );

        require(poolAmountOut >= _minPoolAmountOut, "AMM: Min amount not reached");

        _pullToken(msg.sender, _pairID, _tokenIn, _tokenAmountIn);
        _joinPool(msg.sender, poolAmountOut, _pairID);
        _status = _NOT_ENTERED;
        return poolAmountOut;
    }

    function joinSwapPoolAmountOut(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _poolAmountOut,
        uint256 _maxAmountIn
    ) external override returns (uint256 tokenAmountIn) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        require(_tokenIn < 2, "AMM: Invalid Token Id");
        _updateWeightsFromYieldAtBlock();
        Pair memory pair = pairs[_pairID];

        uint256 inTokenBalance = pair.balances[_tokenIn];
        uint256 tokenWeightIn = pair.weights[_tokenIn];

        require(tokenWeightIn > 0, "AMM: Invalid token address");
        tokenAmountIn = AMMMaths.calcSingleInGivenPoolOut(
            inTokenBalance,
            tokenWeightIn,
            totalLPSupply[_pairID][currentPeriodIndex],
            AMMMaths.UNIT,
            _poolAmountOut,
            swapFee
        );

        require(tokenAmountIn <= inTokenBalance.mul(AMMMaths.MAX_IN_RATIO) / AMMMaths.UNIT, "AMM: Max in ratio reached");
        require(tokenAmountIn != 0, "AMM: Math approximation error");
        require(tokenAmountIn <= _maxAmountIn, "AMM: Max amount in reached");

        _pullToken(msg.sender, _pairID, _tokenIn, tokenAmountIn);
        _joinPool(msg.sender, _poolAmountOut, _pairID);
        _status = _NOT_ENTERED;
        return tokenAmountIn;
    }

    function exitSwapPoolAmountIn(
        uint256 _pairID,
        uint256 _tokenOut,
        uint256 _poolAmountIn,
        uint256 _minAmountOut
    ) external override returns (uint256 tokenAmountOut) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        require(_tokenOut < 2, "AMM: Invalid Token Id");

        _updateWeightsFromYieldAtBlock();
        Pair memory pair = pairs[_pairID];

        uint256 outTokenBalance = pair.balances[_tokenOut];
        uint256 tokenWeightOut = pair.weights[_tokenOut];
        require(tokenWeightOut > 0, "AMM: Invalid token address");

        tokenAmountOut = AMMMaths.calcSingleOutGivenPoolIn(
            outTokenBalance,
            tokenWeightOut,
            totalLPSupply[_pairID][currentPeriodIndex],
            AMMMaths.UNIT,
            _poolAmountIn,
            swapFee
        );

        require(tokenAmountOut <= outTokenBalance.mul(AMMMaths.MAX_OUT_RATIO) / AMMMaths.UNIT, "AMM: Max out ratio reached");
        require(tokenAmountOut >= _minAmountOut, "AMM: Min amount not reached");

        _exitPool(msg.sender, _poolAmountIn, _pairID);
        _pushToken(msg.sender, _pairID, _tokenOut, tokenAmountOut);
        _status = _NOT_ENTERED;
        return tokenAmountOut;
    }

    function exitSwapExternAmountOut(
        uint256 _pairID,
        uint256 _tokenOut,
        uint256 _tokenAmountOut,
        uint256 _maxPoolAmountIn
    ) external override returns (uint256 poolAmountIn) {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        require(_tokenOut < 2, "AMM: Invalid Token Id");

        _updateWeightsFromYieldAtBlock();
        Pair memory pair = pairs[_pairID];

        uint256 outTokenBalance = pair.balances[_tokenOut];
        uint256 tokenWeightOut = pair.weights[_tokenOut];
        require(tokenWeightOut > 0, "AMM: Invalid token address");
        require(
            _tokenAmountOut <= outTokenBalance.mul(AMMMaths.MAX_OUT_RATIO) / AMMMaths.UNIT,
            "AMM: Max out ratio reached"
        );

        poolAmountIn = AMMMaths.calcPoolInGivenSingleOut(
            outTokenBalance,
            tokenWeightOut,
            totalLPSupply[_pairID][currentPeriodIndex],
            AMMMaths.UNIT,
            _tokenAmountOut,
            swapFee
        );

        require(poolAmountIn != 0, "AMM: Math approximation error");
        require(poolAmountIn <= _maxPoolAmountIn, "AMM: Max amount is reached");

        _exitPool(msg.sender, poolAmountIn, _pairID);
        _pushToken(msg.sender, _pairID, _tokenOut, _tokenAmountOut);
        _status = _NOT_ENTERED;
        return poolAmountIn;
    }

    /* Liquidity-related functions */

    /**
     * @notice Create liquidity on the pair setting an initial price
     */
    function createLiquidity(uint256 _pairID, uint256[2] memory _tokenAmounts) external override {
        nonReentrant();
        ammIsActive();
        require(!pairs[_pairID].liquidityIsInitialized, "AMM: Liquidity already present");
        require(_tokenAmounts[0] != 0 && _tokenAmounts[1] != 0, "AMM: Tokens Liquidity not exists");
        _pullToken(msg.sender, _pairID, 0, _tokenAmounts[0]);
        _pullToken(msg.sender, _pairID, 1, _tokenAmounts[1]);
        _joinPool(msg.sender, AMMMaths.UNIT, _pairID);
        pairs[_pairID].liquidityIsInitialized = true;
        emit LiquidityCreated(msg.sender, _pairID);
        _status = _NOT_ENTERED;
    }

    function _pullToken(
        address _sender,
        uint256 _pairID,
        uint256 _tokenID,
        uint256 _amount
    ) internal {
        address _tokenIn = _tokenID == 0 ? address(pt) : pairs[_pairID].tokenAddress;
        pairs[_pairID].balances[_tokenID] = pairs[_pairID].balances[_tokenID].add(_amount);
        IERC20(_tokenIn).safeTransferFrom(_sender, address(this), _amount);
        emit LiquidityIncreased(_sender, _pairID, _tokenID, _amount);
    }

    function _pushToken(
        address _recipient,
        uint256 _pairID,
        uint256 _tokenID,
        uint256 _amount
    ) internal {
        address _tokenIn = _tokenID == 0 ? address(pt) : pairs[_pairID].tokenAddress;
        pairs[_pairID].balances[_tokenID] = pairs[_pairID].balances[_tokenID].sub(_amount);
        IERC20(_tokenIn).safeTransfer(_recipient, _amount);
        emit LiquidityDecreased(_recipient, _pairID, _tokenID, _amount);
    }

    function addLiquidity(
        uint256 _pairID,
        uint256 _poolAmountOut,
        uint256[2] memory _maxAmountsIn
    ) external override {
        nonReentrant();
        samePeriodIndex();
        ammIsActive();
        pairLiquidityIsInitialized(_pairID);
        require(_poolAmountOut != 0, "AMM: Amount cannot be 0");
        _updateWeightsFromYieldAtBlock();

        uint256 poolTotal = totalLPSupply[_pairID][currentPeriodIndex];

        for (uint256 i; i < 2; i++) {
            uint256 amountIn = _computeAmountWithShares(pairs[_pairID].balances[i], _poolAmountOut, poolTotal);
            require(amountIn != 0, "AMM: Math approximation error");
            require(amountIn <= _maxAmountsIn[i], "AMM: Max amount in reached");
            _pullToken(msg.sender, _pairID, i, amountIn);
        }
        _joinPool(msg.sender, _poolAmountOut, _pairID);
        _status = _NOT_ENTERED;
    }

    function removeLiquidity(
        uint256 _pairID,
        uint256 _poolAmountIn,
        uint256[2] memory _minAmountsOut
    ) external override {
        nonReentrant();
        ammIsActive();
        samePeriodIndex();
        pairLiquidityIsInitialized(_pairID);
        require(_poolAmountIn != 0, "AMM: Amount cannot be 0");
        if (futureVault.getCurrentPeriodIndex() == currentPeriodIndex) {
            _updateWeightsFromYieldAtBlock();
        }

        uint256 poolTotal = totalLPSupply[_pairID][currentPeriodIndex];

        for (uint256 i; i < 2; i++) {
            uint256 amountOut = _computeAmountWithShares(pairs[_pairID].balances[i], _poolAmountIn, poolTotal);
            require(amountOut != 0, "AMM: Math approximation error");
            require(amountOut >= _minAmountsOut[i], "AMM: Min amount not reached");
            _pushToken(msg.sender, _pairID, i, amountOut.mul(AMMMaths.UNIT.sub(AMMMaths.EXIT_FEE)).div(AMMMaths.UNIT));
        }
        _exitPool(msg.sender, _poolAmountIn, _pairID);
        _status = _NOT_ENTERED;
    }

    function _joinPool(
        address _user,
        uint256 _amount,
        uint256 _pairID
    ) internal {
        poolTokens.mint(_user, ammId, uint64(currentPeriodIndex), uint32(_pairID), _amount, bytes(""));
        totalLPSupply[_pairID][currentPeriodIndex] = totalLPSupply[_pairID][currentPeriodIndex].add(_amount);
        emit PoolJoined(_user, _pairID, _amount);
    }

    function _exitPool(
        address _user,
        uint256 _amount,
        uint256 _pairID
    ) internal {
        uint256 lpTokenId = getLPTokenId(ammId, currentPeriodIndex, _pairID);

        uint256 exitFee = _amount.mul(AMMMaths.EXIT_FEE).div(AMMMaths.UNIT);
        uint256 userAmount = _amount.sub(exitFee);
        poolTokens.burnFrom(_user, lpTokenId, userAmount);
        poolTokens.safeTransferFrom(_user, feesRecipient, lpTokenId, exitFee, "");

        totalLPSupply[_pairID][currentPeriodIndex] = totalLPSupply[_pairID][currentPeriodIndex].sub(userAmount);
        emit PoolExited(_user, _pairID, _amount);
    }

    function setSwappingFees(uint256 _swapFee) external override isAdmin {
        require(_swapFee < AMMMaths.UNIT, "AMM: Fee must be < 1");
        swapFee = _swapFee;
        emit SwappingFeeSet(_swapFee);
    }

    // Emergency withdraw - will only rescue funds mistakenly sent to the address
    function rescueFunds(IERC20 _token, address _recipient) external isAdmin {
        uint256 pairId = tokenToPairID[address(_token)];
        bool istokenPresent = false;
        if (pairId == 0) {
            if (_token == pt || address(_token) == pairs[0].tokenAddress) {
                istokenPresent = true;
            }
        } else {
            istokenPresent = true;
        }
        require(!istokenPresent, "AMM: Token is present");
        uint256 toRescue = _token.balanceOf(address(this));
        require(toRescue > 0, "AMM: No funds to rescue");
        _token.safeTransfer(_recipient, toRescue);
    }

    /* Utils*/
    function _computeAmountWithShares(
        uint256 _amount,
        uint256 _sharesAmount,
        uint256 _sharesTotalAmount
    ) internal pure returns (uint256) {
        return _sharesAmount.mul(_amount).div(_sharesTotalAmount);
    }

    /* Getters */

    /**
     * @notice Getter for the spot price of a pair
     * @param _pairID the id of the pair
     * @param _tokenIn the id of the tokens sent
     * @param _tokenOut the id of the tokens received
     * @return the sport price of the pair
     */
    function getSpotPrice(
        uint256 _pairID,
        uint256 _tokenIn,
        uint256 _tokenOut
    ) public view override returns (uint256) {
        return
            AMMMaths.calcSpotPrice(
                pairs[_pairID].balances[_tokenIn],
                pairs[_pairID].weights[_tokenIn],
                pairs[_pairID].balances[_tokenOut],
                pairs[_pairID].weights[_tokenOut],
                swapFee
            );
    }

    /**
     * @notice Getter for the paused state of the AMM
     * @return true if the AMM is paused, false otherwise
     */
    function getAMMState() external view returns (AMMGlobalState) {
        return state;
    }

    /**
     * @notice Getter for the address of the corresponding future vault
     * @return the address of the future vault
     */
    function getFutureAddress() external view override returns (address) {
        return address(futureVault);
    }

    /**
     * @notice Getter for the pt address
     * @return the pt address
     */
    function getPTAddress() external view override returns (address) {
        return address(pt);
    }

    /**
     * @notice Getter for the address of the underlying token of the ibt
     * @return the address of the underlying token of the ibt
     */
    function getUnderlyingOfIBTAddress() external view override returns (address) {
        return address(underlyingOfIBT);
    }

    /**
     * @notice Getter for the address of the ibt
     * @return the address of the ibt token
     */
    function getIBTAddress() external view returns (address) {
        return address(ibt);
    }

    /**
     * @notice Getter for the fyt address
     * @return the fyt address
     */
    function getFYTAddress() external view override returns (address) {
        return address(fyt);
    }

    /**
     * @notice Getter for the pool token address
     * @return the pool tokens address
     */
    function getPoolTokenAddress() external view returns (address) {
        return address(poolTokens);
    }

    function getPairWithID(uint256 _pairID) external view override returns (Pair memory) {
        return pairs[_pairID];
    }

    function getTotalSupplyWithTokenId(uint256 _tokenId) external view returns (uint256) {
        uint256 pairId = poolTokens.getPairId(_tokenId);
        uint256 periodId = poolTokens.getPeriodIndex(_tokenId);
        return totalLPSupply[pairId][periodId];
    }

    function getPairIDForToken(address _tokenAddress) external view returns (uint256) {
        if (tokenToPairID[_tokenAddress] == 0)
            require(pairs[0].tokenAddress == _tokenAddress || _tokenAddress == address(pt), "AMM: invalid token address");
        return tokenToPairID[_tokenAddress];
    }

    function getLPTokenId(
        uint256 _ammId,
        uint256 _periodIndex,
        uint256 _pairID
    ) public pure override returns (uint256) {
        return (_ammId << 192) | (_periodIndex << 128) | (_pairID << 96);
    }

    /* Modifier functions */

    /**
     * @notice Check state of AMM
     */
    function ammIsActive() private view {
        require(state == AMMGlobalState.Activated, "AMM: AMM not active");
    }

    /**
     * @notice Check liquidity is initilized for the given _pairId
     * @param _pairID the id of the pair
     */
    function pairLiquidityIsInitialized(uint256 _pairID) private view {
        require(pairs[_pairID].liquidityIsInitialized, "AMM: Pair not active");
    }

    /**
     * @notice Check the periodIndex of Protocol and AMM
     */
    function samePeriodIndex() private view {
        require(futureVault.getCurrentPeriodIndex() == currentPeriodIndex, "AMM: Period index not same");
    }

    /**
     * @notice nonReentrant function used to remove reentrency
     */
    function nonReentrant() private {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    /**
     * @notice Check valid Token ID's
     * @param _tokenIdInd the id of token In
     * @param _tokenIdOut the id of token Out
     */
    function tokenIdsAreValid(uint256 _tokenIdInd, uint256 _tokenIdOut) private pure {
        require(_tokenIdInd < 2 && _tokenIdOut < 2 && _tokenIdInd != _tokenIdOut, "AMM: Invalid Token ID");
    }
}
