// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
import "./IAMM.sol";

/**
 * IAMMRouter is an on-chain router designed to batch swaps for the APWine AMM.
 * It can be used to facilitate swaps and save gas fees as opposed to executing multiple transactions.
 * Example: swap from pair 0 to pair 1, from token 0 to token 1 then token 1 to token 0.
 * One practical use-case would be swapping from FYT to underlying, which would otherwise not be possible natively.
 */
interface IAMMRouter {
    /**
     * @dev execute a swapExactAmountIn given pair and token paths. Works just like the regular swapExactAmountIn from AMM.
     *
     * @param _amm the address of the AMM instance to execute the swap on
     * @param _pairPath a list of N pair indices, where N is the number of swaps to execute
     * @param _tokenPath a list of 2 * N token indices corresponding to the swaps path. For swap I, tokenIn = 2*I, tokenOut = 2*I + 1
     * @param _tokenAmountIn the exact input token amount
     * @param _minAmountOut the minimum amount of output tokens to receive, call will revert if not reached
     * @param _to the recipient address
     * @param _deadline the absolute deadline, in seconds, to prevent outdated swaps from being executed
     */
    function swapExactAmountIn(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _tokenAmountIn,
        uint256 _minAmountOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 tokenAmountOut);

    /**
     * @dev execute a swapExactAmountOut given pair and token paths. Works just like the regular swapExactAmountOut from AMM.
     *
     * @param _amm the address of the AMM instance to execute the swap on
     * @param _pairPath a list of N pair indices, where N is the number of swaps to execute
     * @param _tokenPath a list of 2 * N token indices corresponding to the swaps path. For swap I, tokenIn = 2*I, tokenOut = 2*I + 1
     * @param _maxAmountIn the maximum amount of input tokens needed to send, call will revert if not reached
     * @param _tokenAmountOut the exact out token amount
     * @param _to the recipient address
     * @param _deadline the absolute deadline, in seconds, to prevent outdated swaps from being executed
     */
    function swapExactAmountOut(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _maxAmountIn,
        uint256 _tokenAmountOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 tokenAmountIn);

    /**
     * @dev execute a getSpotPrice given pair and token paths. Works just like the regular getSpotPrice from AMM.
     *
     * @param _amm the address of the AMM instance to execute the spotPrice on
     * @param _pairPath a list of N pair indices, where N is the number of getSpotPrice to execute
     * @param _tokenPath a list of 2 * N token indices corresponding to the getSpotPrice path. For getSpotPrice I, tokenIn = 2*I, tokenOut = 2*I + 1
     */
    function getSpotPrice(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath
    ) external returns (uint256 spotPrice);

    /**
     * @dev execute a getAmountIn given pair and token paths. Works just like the regular calcInAndSpotGivenOut from AMM.
     *
     * @param _amm the address of the AMM instance to execute the getAmountIn on
     * @param _pairPath a list of N pair indices, where N is the number of getAmountIn to execute
     * @param _tokenPath a list of 2 * N token indices corresponding to the getAmountIn path. For getAmountIn I, tokenIn = 2*I, tokenOut = 2*I + 1
     * @param _tokenAmountOut the exact out token amount
     */
    function getAmountIn(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _tokenAmountOut
    ) external returns (uint256 tokenAmountIn);

    /**
     * @dev execute a getAmountOut given pair and token paths. Works just like the regular calcInAndSpotGivenOut from AMM.
     *
     * @param _amm the address of the AMM instance to execute the getAmountOut on
     * @param _pairPath a list of N pair indices, where N is the number of getAmountOut to execute
     * @param _tokenPath a list of 2 * N token indices corresponding to the getAmountOut path. For getAmountOut I, tokenIn = 2*I, tokenOut = 2*I + 1
     * @param _tokenAmountIn the exact input token amount
     */
    function getAmountOut(
        IAMM _amm,
        uint256[] calldata _pairPath,
        uint256[] calldata _tokenPath,
        uint256 _tokenAmountIn
    ) external returns (uint256 tokenAmountOut);
}
