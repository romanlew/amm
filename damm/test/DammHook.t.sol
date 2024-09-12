pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

import {DammHook} from "../src/DammHook.sol";


contract TestDammHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    // event TransactionLogged(address indexed sender, uint256 value, uint256 timestamp);


    /*//////////////////////////////////////////////////////////////
                            TEST STORAGE
    //////////////////////////////////////////////////////////////*/

    // VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    // uint256 sepoliaForkId = vm.createFork("https://rpc.sepolia.org/");

    DammHook hook;
    address swapper0 = address(0xBEEF0);
    address swapper1 = address(0xBEEF1);
    address swapper2 = address(0xBEEF2);

    function setUp() public {
        // vm.selectFork(sepoliaForkId);
        // vm.deal(address(this), 500 ether);
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG
            )
        );

        // Set gas price = 10 gwei and deploy our hook
        vm.txGasPrice(10 gwei);
        deployCodeTo("DammHook", abi.encode(manager), hookAddress);
        hook = DammHook(hookAddress);

        // Initialize a pool
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function testBeforeSwap() public {
        key.currency0.transfer(address(swapper0), 5e18);
        key.currency1.transfer(address(swapper0), 5e18);

        key.currency0.transfer(address(swapper1), 10e18);
        key.currency1.transfer(address(swapper1), 10e18);

        key.currency0.transfer(address(swapper2), 15e18);
        key.currency1.transfer(address(swapper2), 15e18);

        console.log("testBeforeSwap | --- STARTING BALANCES ---");

        uint256 swapper0BalanceBefore0 = currency0.balanceOf(address(swapper0));
        uint256 swapper0BalanceBefore1 = currency1.balanceOf(address(swapper0));

        uint256 swapper1BalanceBefore0 = currency0.balanceOf(address(swapper1));
        uint256 swapper1BalanceBefore1 = currency1.balanceOf(address(swapper1));

        uint256 swapper2BalanceBefore0 = currency0.balanceOf(address(swapper2));
        uint256 swapper2BalanceBefore1 = currency1.balanceOf(address(swapper2));

        console.log("testBeforeSwap | Swapper address 0: ", address(swapper0));
        console.log("testBeforeSwap | Swapper address 1: ", address(swapper1));
        console.log("testBeforeSwap | Swapper address 2: ", address(swapper2));
        console.log("testBeforeSwap | Swapper address 0 balance in currency0 before swapping: ", swapper0BalanceBefore0);
        console.log("testBeforeSwap | Swapper address 0 balance in currency1 before swapping: ", swapper0BalanceBefore1);
        console.log("testBeforeSwap | Swapper address 1 balance in currency0 before swapping: ", swapper1BalanceBefore0);
        console.log("testBeforeSwap | Swapper address 1 balance in currency1 before swapping: ", swapper1BalanceBefore1);
        console.log("testBeforeSwap | Swapper address 2 balance in currency0 before swapping: ", swapper2BalanceBefore0);
        console.log("testBeforeSwap | Swapper address 2 balance in currency1 before swapping: ", swapper2BalanceBefore1);

        // Set up our swap parameters
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        console.log("testBeforeSwap | --- START PRANK WITH ADDRESS", address(swapper0));
        vm.startPrank(swapper0);

        uint256 submittedDeltaFee = 1000;
        bytes memory hookData = hook.getHookData(submittedDeltaFee);
        swapRouter.swap(key, params, testSettings, hookData);

        vm.stopPrank();
        console.log("testBeforeSwap | --- PRANK STOPPED FOR ADDRESS", address(swapper0));

        // vm.roll(5);

        // submittedDeltaFee = 2000;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // vm.stopPrank();
        // vm.startPrank(swapper1);
        // deployMintAndApprove2Currencies();

        // submittedDeltaFee = 2000;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // vm.stopPrank();

        // vm.prank(swapper2);
        // deployMintAndApprove2Currencies();

        // submittedDeltaFee = 2000;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // // skip 10 blocks ahead
        // vm.roll(10);

        // submittedDeltaFee = 1500;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // vm.roll(12);

        // submittedDeltaFee = 1500;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // submittedDeltaFee = 1500;
        // hookData = hook.getHookData(submittedDeltaFee);
        // swapRouter.swap(key, params, testSettings, hookData);

        // vm.roll(13);

        // // no submittedDeltaFee
        // swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // uint256 balanceOfToken1After = currency1.balanceOfSelf();
        // uint256 outputFromBaseFeeSwap = balanceOfToken1After -
        //     balanceOfToken1Before;

        // assertGt(balanceOfToken1After, balanceOfToken1Before);

        // console.log("Balance of token 1 before swap", balanceOfToken1Before);
        // console.log("Balance of token 1 after swap", balanceOfToken1After);
        // console.log("Base Fee Output", outputFromBaseFeeSwap);
    }


}