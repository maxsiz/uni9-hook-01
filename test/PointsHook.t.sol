// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {PointsHook} from "../src/PointsHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
//import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
abstract contract ERC1155TokenReceiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
contract PointsHookTest is BaseTest
//, Deployers, 
,ERC1155TokenReceiver 
{
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency ethCurrency = Currency.wrap(address(0));
    Currency currency1;

    PoolKey poolKey;

    PointsHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("PointsHook.sol:PointsHook", constructorArgs, flags);
        hook = PointsHook(flags);

        // Create the pool
        poolKey = PoolKey(ethCurrency, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }
    function test_swap() public {
    uint256 poolIdUint = uint256(PoolId.unwrap(poolKey.toId()));
    uint256 pointsBalanceOriginal = hook.balanceOf(
        address(this),
        poolIdUint
    );
 
    // Set user address in hook data
    bytes memory hookData = abi.encode(address(this));
 
    // Now we swap
    // We will swap 0.001 ether for tokens
    // We should get 20% of 0.001 * 10**18 points
    // = 2 * 10**14
    // swapRouter.swap{value: 0.001 ether}(
    //     poolKey,
    //     SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: -0.001 ether, // Exact input for output swap
    //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //     }),
    //     PoolSwapTest.TestSettings({
    //         takeClaims: false,
    //         settleUsingBurn: false
    //     }),
    //     hookData
    // );

    swapRouter.swapExactTokensForTokens{value: 0.001 ether}(
        0.001 ether, //uint256 amountIn,
        0, //uint256 amountOutMin,
        true, //bool zeroForOne,
        poolKey, //PoolKey calldata poolKey,
        hookData, //bytes calldata hookData,
        address(this),//address receiver,
        block.timestamp +100 //uint256 deadline
    );


    uint256 pointsBalanceAfterSwap = hook.balanceOf(
        address(this),
        poolIdUint
    );
    assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
}

    // function testPointsHookHooks() public {
    //     // positions were created in setup()
    //     assertEq(hook.beforeAddLiquidityCount(poolId), 1);
    //     assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

    //     assertEq(hook.beforeSwapCount(poolId), 0);
    //     assertEq(hook.afterSwapCount(poolId), 0);

    //     // Perform a test swap //
    //     uint256 amountIn = 1e18;
    //     BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
    //         amountIn: amountIn,
    //         amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
    //         zeroForOne: true,
    //         poolKey: poolKey,
    //         hookData: Constants.ZERO_BYTES,
    //         receiver: address(this),
    //         deadline: block.timestamp + 1
    //     });
    //     // ------------------- //

    //     assertEq(int256(swapDelta.amount0()), -int256(amountIn));

    //     assertEq(hook.beforeSwapCount(poolId), 1);
    //     assertEq(hook.afterSwapCount(poolId), 1);
    // }

    // function testLiquidityHooks() public {
    //     // positions were created in setup()
    //     assertEq(hook.beforeAddLiquidityCount(poolId), 1);
    //     assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

    //     // remove liquidity
    //     uint256 liquidityToRemove = 1e18;
    //     positionManager.decreaseLiquidity(
    //         tokenId,
    //         liquidityToRemove,
    //         0, // Max slippage, token0
    //         0, // Max slippage, token1
    //         address(this),
    //         block.timestamp,
    //         Constants.ZERO_BYTES
    //     );

    //     assertEq(hook.beforeAddLiquidityCount(poolId), 1);
    //     assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);
    // }
}
