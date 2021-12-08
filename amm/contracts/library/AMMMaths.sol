// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

// https://github.com/balancer-labs/balancer-core/blob/master/contracts/BNum.sol
library AMMMathsUtils {
    uint256 internal constant UNIT = 10**18;
    uint256 internal constant MIN_POW_BASE = 1 wei;
    uint256 internal constant MAX_POW_BASE = (2 * UNIT) - 1 wei;
    uint256 internal constant POW_PRECISION = UNIT / 10**10;

    function powi(uint256 a, uint256 n) internal pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : UNIT;
        for (n /= 2; n != 0; n /= 2) {
            a = div(mul(a, a), UNIT);
            if (n % 2 != 0) {
                z = div(mul(z, a), UNIT);
            }
        }
        return z;
    }

    function pow(uint256 base, uint256 exp) internal pure returns (uint256) {
        require(base >= MIN_POW_BASE, "ERR_POW_BASE_TOO_LOW");
        require(base <= MAX_POW_BASE, "ERR_POW_BASE_TOO_HIGH");
        uint256 whole = mul(div(exp, UNIT), UNIT);
        uint256 remain = sub(exp, whole);
        uint256 wholePow = powi(base, div(whole, UNIT));
        if (remain == 0) {
            return wholePow;
        }
        uint256 partialResult = powApprox(base, remain, POW_PRECISION);
        return div(mul(wholePow, partialResult), UNIT);
    }

    function subSign(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        return (a >= b) ? (a - b, false) : (b - a, true);
    }

    function powApprox(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) internal pure returns (uint256) {
        // term 0:
        uint256 a = exp;
        (uint256 x, bool xneg) = subSign(base, UNIT);
        uint256 term = UNIT;
        uint256 sum = term;
        bool negative = false;
        for (uint256 i = 1; term >= precision; ++i) {
            uint256 bigK = mul(i, UNIT);
            (uint256 c, bool cneg) = subSign(a, sub(bigK, UNIT));
            term = div(mul(term, div(mul(c, x), UNIT)), UNIT);
            term = div(mul(UNIT, term), bigK);
            if (term == 0) break;
            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = sub(sum, term);
            } else {
                sum = add(sum, term);
            }
        }
        return sum;
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "AMMMaths: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "AMMMaths: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "AMMMaths: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "AMMMaths: division by zero");
        return a / b;
    }
}

// https://github.com/balancer-labs/balancer-core/blob/master/contracts/BMath.sol
library AMMMaths {
    using AMMMathsUtils for uint256;
    uint256 internal constant UNIT = 10**18;
    uint256 internal constant SQUARED_UNIT = UNIT * UNIT;
    uint256 internal constant EXIT_FEE = 0;

    uint256 internal constant MAX_IN_RATIO = UNIT / 2;
    uint256 internal constant MAX_OUT_RATIO = (UNIT / 3) + 1 wei;

    function calcOutGivenIn(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _tokenAmountIn,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        return
            calcOutGivenIn(
                _tokenBalanceIn,
                _tokenWeightIn,
                _tokenBalanceOut,
                _tokenWeightOut,
                _tokenAmountIn,
                _swapFee,
                UNIT
            );
    }

    function calcOutGivenIn(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _tokenAmountIn,
        uint256 _swapFee,
        uint256 _slippageFactor
    ) internal pure returns (uint256) {
        uint256 slippageBase = UNIT.mul(UNIT).div(_slippageFactor);
        uint256 weightRatio = slippageBase.mul(_tokenWeightIn).div(_tokenWeightOut);
        uint256 adjustedIn = _tokenAmountIn.mul(UNIT.sub(_swapFee)).div(UNIT);
        uint256 y = UNIT.mul(_tokenBalanceIn).div(_tokenBalanceIn.add(adjustedIn));
        uint256 bar = UNIT.sub(AMMMathsUtils.pow(y, weightRatio));
        return _tokenBalanceOut.mul(bar).div(UNIT);
    }

    function calcInGivenOut(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _tokenAmountOut,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        return
            calcInGivenOut(
                _tokenBalanceIn,
                _tokenWeightIn,
                _tokenBalanceOut,
                _tokenWeightOut,
                _tokenAmountOut,
                _swapFee,
                UNIT
            );
    }

    function calcInGivenOut(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _tokenAmountOut,
        uint256 _swapFee,
        uint256 _slippageFactor
    ) internal pure returns (uint256) {
        uint256 slippageBase = UNIT.mul(UNIT).div(_slippageFactor);
        uint256 weightRatio = slippageBase.mul(_tokenWeightOut).div(_tokenWeightIn);
        uint256 y = UNIT.mul(_tokenBalanceOut).div(_tokenBalanceOut.sub(_tokenAmountOut));
        uint256 foo = AMMMathsUtils.pow(y, weightRatio).sub(UNIT);
        return _tokenBalanceIn.mul(foo).div(UNIT.sub(_swapFee));
    }

    function calcPoolOutGivenSingleIn(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _poolSupply,
        uint256 _totalWeight,
        uint256 _tokenAmountIn,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        uint256 normalizedWeight = UNIT.mul(_tokenWeightIn).div(_totalWeight);
        uint256 zaz = (UNIT.sub(normalizedWeight)).mul(_swapFee).div(UNIT);
        uint256 tokenAmountInAfterFee = _tokenAmountIn.mul(UNIT.sub(zaz)).div(UNIT);
        uint256 newTokenBalanceIn = _tokenBalanceIn.add(tokenAmountInAfterFee);
        uint256 tokenInRatio = UNIT.mul(newTokenBalanceIn).div(_tokenBalanceIn);
        uint256 poolRatio = AMMMathsUtils.pow(tokenInRatio, normalizedWeight);
        uint256 newPoolSupply = poolRatio.mul(_poolSupply).div(UNIT);
        return newPoolSupply.sub(_poolSupply);
    }

    function calcSingleInGivenPoolOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountOut,
        uint256 swapFee
    ) internal pure returns (uint256 tokenAmountIn) {
        uint256 normalizedWeight = UNIT.mul(tokenWeightIn).div(totalWeight);
        uint256 newPoolSupply = poolSupply.add(poolAmountOut);
        uint256 poolRatio = UNIT.mul(newPoolSupply).div(poolSupply);

        //uint256 newBalTi = poolRatio^(1/weightTi) * balTi;
        uint256 boo = UNIT.mul(UNIT).div(normalizedWeight);
        uint256 tokenInRatio = AMMMathsUtils.pow(poolRatio, boo);
        uint256 newTokenBalanceIn = tokenInRatio.mul(tokenBalanceIn).div(UNIT);
        uint256 tokenAmountInAfterFee = newTokenBalanceIn.sub(tokenBalanceIn);
        // Do reverse order of fees charged in joinswap_ExternAmountIn, this way
        //     ``` pAo == joinswap_ExternAmountIn(Ti, joinswap_PoolAmountOut(pAo, Ti)) ```
        //uint256 tAi = tAiAfterFee / (1 - (1-weightTi) * swapFee) ;
        uint256 zar = (UNIT.sub(normalizedWeight)).mul(swapFee).div(UNIT);
        tokenAmountIn = UNIT.mul(tokenAmountInAfterFee).div(UNIT.sub(zar));
        return tokenAmountIn;
    }

    function calcSpotPrice(
        uint256 _tokenBalanceIn,
        uint256 _tokenWeightIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        uint256 numer = UNIT.mul(_tokenBalanceIn).div(_tokenWeightIn);
        uint256 denom = UNIT.mul(_tokenBalanceOut).div(_tokenWeightOut);
        uint256 ratio = UNIT.mul(numer).div(denom);
        uint256 scale = UNIT.mul(UNIT).div(UNIT.sub(_swapFee));
        return ratio.mul(scale).div(UNIT);
    }

    function calcSingleOutGivenPoolIn(
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _poolSupply,
        uint256 _totalWeight,
        uint256 _poolAmountIn,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        uint256 normalizedWeight = UNIT.mul(_tokenWeightOut).div(_totalWeight);
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint256 poolAmountInAfterExitFee = _poolAmountIn.mul(UNIT.sub(EXIT_FEE)).div(UNIT);
        uint256 newPoolSupply = _poolSupply.sub(poolAmountInAfterExitFee);
        uint256 poolRatio = UNIT.mul(newPoolSupply).div(_poolSupply);

        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint256 tokenOutRatio = AMMMathsUtils.pow(poolRatio, UNIT.mul(UNIT).div(normalizedWeight));
        uint256 newTokenBalanceOut = tokenOutRatio.mul(_tokenBalanceOut).div(UNIT);

        uint256 tokenAmountOutBeforeSwapFee = _tokenBalanceOut.sub(newTokenBalanceOut);

        // charge swap fee on the output token side
        //uint256 tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * _swapFee)
        uint256 zaz = (UNIT.sub(normalizedWeight)).mul(_swapFee).div(UNIT);
        return tokenAmountOutBeforeSwapFee.mul(UNIT.sub(zaz)).div(UNIT);
    }

    function calcPoolInGivenSingleOut(
        uint256 _tokenBalanceOut,
        uint256 _tokenWeightOut,
        uint256 _poolSupply,
        uint256 _totalWeight,
        uint256 _tokenAmountOut,
        uint256 _swapFee
    ) internal pure returns (uint256) {
        // charge swap fee on the output token side
        uint256 normalizedWeight = UNIT.mul(_tokenWeightOut).div(_totalWeight);
        //uint256 tAoBeforeSwapFee = tAo / (1 - (1-weightTo) * _swapFee) ;
        uint256 zoo = UNIT.sub(normalizedWeight);
        uint256 zar = zoo.mul(_swapFee).div(UNIT);
        uint256 tokenAmountOutBeforeSwapFee = UNIT.mul(_tokenAmountOut).div(UNIT.sub(zar));

        uint256 newTokenBalanceOut = _tokenBalanceOut.sub(tokenAmountOutBeforeSwapFee);
        uint256 tokenOutRatio = UNIT.mul(newTokenBalanceOut).div(_tokenBalanceOut);

        //uint256 newPoolSupply = (ratioTo ^ weightTo) * _poolSupply;
        uint256 poolRatio = AMMMathsUtils.pow(tokenOutRatio, normalizedWeight);
        uint256 newPoolSupply = poolRatio.mul(_poolSupply).div(UNIT);
        uint256 poolAmountInAfterExitFee = _poolSupply.sub(newPoolSupply);

        // charge exit fee on the pool token side
        // pAi = pAiAfterExitFee/(1-exitFee)
        return UNIT.mul(poolAmountInAfterExitFee).div(UNIT.sub(EXIT_FEE));
    }
}
