// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

import {DammOracle} from "../src/DammOracle.sol";
import {console} from "forge-std/console.sol";
import {FeeQuantizer} from "../src/FeeQuantizer.sol";
import {MevClassifier} from "../src/MevClassifier.sol";
import {DammHookHelper} from "../src/DammHookHelper.sol";
import {RandomNumberGenerator} from "../src/RandomNumberGenerator.sol";


contract DammHook is BaseHook {
	// Use CurrencyLibrary and BalanceDeltaLibrary
	// to add some helper functions over the Currency and BalanceDelta
	// data types 
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;
    RandomNumberGenerator private randomNumberGenerator;

    FeeQuantizer feeQuantizer;
    MevClassifier mevClassifier;
    DammOracle dammOracle;
    DammHookHelper dammHookHelper;

    // Keeping track of the moving average gas price
    uint128 public movingAverageGasPrice;
    // How many times has the moving average been updated?
    // Needed as the denominator to update it the next time based on the moving average formula
    uint104 public movingAverageGasPriceCount;

	// Keeping track of informed traders
	address[] public informedTraders;

	// Amount of points someone gets for referring someone else
    uint256 public constant POINTS_FOR_REFERRAL = 500 * 10 ** 18;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 3000; // 0.3%

    uint24 public constant CUT_OFF_PERCENTILE = 85;

    // TODO change M to 0.5 similar to BASE_FEE handling
    uint24 public constant M = 5000;
    uint24 public constant N = 2;

    error MustUseDynamicFee();

    //Storage for submittedDeltaFees
    mapping(address sender => uint256 inputAmount) public submittedDeltaFees;

    // TODO reset for a new block - maybe a Trader struct
    address[] senders;

    struct NewHookData {
        bytes hookData;
        address sender;
    }

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        feeQuantizer = new FeeQuantizer();
        mevClassifier = new MevClassifier(address(feeQuantizer), 5, 1, 2);
        dammOracle = new DammOracle();
        dammHookHelper = new DammHookHelper(address(dammOracle));
        randomNumberGenerator = new RandomNumberGenerator();

        //TODO clean up
        updateMovingAverage();
    }

	// Set up hook permissions to return `true`
	// for the two hook functions we are using
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    // TODO external override onlyByPoolManager
    function beforeSwap(
                address sender, 
                PoolKey calldata key, 
                IPoolManager.SwapParams calldata params, 
                bytes calldata hookData
            )   external override
                returns (bytes4, BeforeSwapDelta, uint24)
            {
                uint256 blockNumber = uint256(block.number);
                int256 amountToSwap = params.amountSpecified;
                uint256 poolFee;

                uint24 fee = BASE_FEE;
                uint24 INTERIM_FEE = BASE_FEE;

                uint256 offChainMidPrice = dammOracle.getOrderBookPressure();


                NewHookData memory data = abi.decode(hookData, (NewHookData));
                address sender_address = data.sender;

                uint256 submittedDeltaFee = 0;

                if (data.hookData.length > 0) {
                    submittedDeltaFee = abi.decode(data.hookData, (uint256));
                }
                
                _storeSubmittedDeltaFee(sender_address, blockNumber, submittedDeltaFee);
                // Quantize the fee
                uint256 quantizedFee = feeQuantizer.getquantizedFee(fee);

                // Adjust fee based on MEV classification
                uint256 priorityFee = getPriorityFee(params);
                bool mevFlag = mevClassifier.classifyTransaction(priorityFee);

                
                // Fetch order book pressure from DammOracle
                uint256 orderBookPressure = dammOracle.getOrderBookPressure();

                // Adjust the fee based on order book pressure
                // ToDo: USE BUY OR SEll 
                if (orderBookPressure > 0 && !params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE + uint24(dammHookHelper.calculateCombinedFee(blockNumber, sender_address));
                } else if (orderBookPressure < 0 && !params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE - uint24(dammHookHelper.calculateCombinedFee(blockNumber, sender_address));                
                } else if (orderBookPressure > 0 && params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE - uint24(dammHookHelper.calculateCombinedFee(blockNumber, sender_address));                
                } else if (orderBookPressure < 0 && params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE + uint24(dammHookHelper.calculateCombinedFee(blockNumber, sender_address));                
                }

                // Update the dynamic LP fee
                uint24 finalPoolFee = 
                    mevFlag ? BASE_FEE * 10: uint24(INTERIM_FEE);

                poolManager.updateDynamicLPFee(key, finalPoolFee);
                // poolManager.updateDynamicLPFee(key, fee);
                console.log("Blocknumber: ", blockNumber);


            // if (currentBlockId == 0) {
            //     currentBlockId = blockNumber;
            //     beginBlock(blockNumber, efficientOffChainPrice);
            // } else if (currentBlockId != blockId) {
            //     endBlock();
            //     currentBlockId = blockNumber;
            //     beginBlock(blockNumber, efficientOffChainPrice);
            // }

            // if (currentBlockId == 0) {
            //     poolFee = 1 + BASE_FEE;
            // } else {
            //     uint256 delta = calculateCombinedFee(blockNumber, sender).sub(BASE_FEE);
            //     poolFee = poolFee.add(delta);
            // }

            // uint256 currentAMMPrice = sqrtPrice.mul(sqrtPrice);
            // (uint256 ammBidPrice, uint256 ammAskPrice) = getBidAndAskOfAMM(currentAMMPrice);

            // if (submittedFee < 0) {
            //     revert("Submitted fee must be non-negative.");
            // } else if (submittedFee >= BASE_FEE) {
            //     revert("Submitted fee cannot exceed base fee.");
            // } else {
            //     listSubmittedFees.push(submittedFee);
            //     previousBlockSwappers[sender] = true;
            //     setOfIntendToTradeSwapperSignalledInPreviousBlock[sender] = true;
            // }

            // if (informedTraders[sender]) {
            //     if (ammAskPrice > efficientOffChainPrice && ammBidPrice < efficientOffChainPrice) {
            //         return (0, 0, 0);
            //     }
            // }

            // uint256 x;
            // uint256 y;
            // uint256 fee;
            // if (ammAskPrice < efficientOffChainPrice) {
            //     uint256 _fee = 1 + poolFee;
            //     uint256 newSqrtPrice = sqrt(efficientOffChainPrice.div(_fee));
            //     (x, y, fee) = buyXTokensForYTokens(newSqrtPrice, _fee);
            // } else if (ammBidPrice > efficientOffChainPrice) {
            //     uint256 _fee = 1 + poolFee;
            //     uint256 newSqrtPrice = sqrt(efficientOffChainPrice.mul(2).sub(_fee));
            //     (x, y, fee) = sellXTokensForYTokens(newSqrtPrice, _fee);
            // }

            // if (tx.gas > x.mul(efficientOffChainPrice).add(y)) {
            //     revert("Gas cost cannot exceed the total value of the trade.");
            // } else {
            //     sqrtPrice = sqrt(efficientOffChainPrice);
            // }

            // emit TokensSwapped(swapperId, x, y, fee);
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, finalPoolFee);
    }

    function getPriorityFee(IPoolManager.SwapParams calldata params) public returns (uint256) {
        // currently returns the priority fee as a random number
        uint256 randomNumber = randomNumberGenerator.getRandomNumber();
        return randomNumber;
    }

    function _storeSubmittedDeltaFee(
        address sender,
        uint256 blockNumber,
        uint256 submittedDeltaFee
    ) internal {
        if (submittedDeltaFee == 0) return;

        if (submittedDeltaFee != 0) {
            require(submittedDeltaFee >= 0, "Submitted fee must be non-negative.");
            require(submittedDeltaFee < BASE_FEE, "Submitted fee cannot exceed base fee.");

            if (submittedDeltaFees[sender] != 0) {
                uint256 oldSubmittedDeltaFee = submittedDeltaFees[sender];
                uint256 maxSubmittedDeltaFee = max(oldSubmittedDeltaFee, submittedDeltaFee);
                submittedDeltaFees[sender] = maxSubmittedDeltaFee;
                console.log("maxSubmittedDeltaFee: ", maxSubmittedDeltaFee);
            } else {
                senders.push(sender);
                submittedDeltaFees[sender] = submittedDeltaFee;
                console.log("submittedDeltaFee: ", submittedDeltaFee);
            }

            // TODO include intent to trade next block
            // setIntendToTradeNextBlock[swapperId] = true;
        }
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    // TODO OLD get fee function from sample
    function getFee() internal view returns (uint24) {
        uint128 gasPrice = uint128(tx.gasprice);

        // if gasPrice > movingAverageGasPrice * 1.1, then half the fees
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        // if gasPrice < movingAverageGasPrice * 0.9, then double the fees
        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }

        return BASE_FEE;
    }

    // TODO OLD moving average function from sample
    // Update our moving average gas price
    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);

        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) /
            (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    function getHookData(
        uint256 submittedDeltaFee
    ) public pure returns (bytes memory) {
        return abi.encode(submittedDeltaFee);
    }

    function getSubmittedDeltaFeesForBlockByAddress(
        address sender
    ) public view returns (uint256 submittedDeltaFee) {
        return submittedDeltaFees[sender];
    }

    function getSubmittedDeltaFeeForBlock() public view returns (uint256) {
        uint256 numberSenders = senders.length;
        if (numberSenders < 2) {
            return BASE_FEE;
        }

        uint[] memory sortedDeltaFees = new uint[](numberSenders);

        for (uint256 i = 0; i < senders.length; i++) {
            sortedDeltaFees[i] = submittedDeltaFees[senders[i]];
        }

        sort(sortedDeltaFees);

        uint256 cutoffIndex = (numberSenders * CUT_OFF_PERCENTILE) / 100;
        uint256[] memory filteredFees = new uint256[](cutoffIndex);
        for (uint256 i = 0; i < cutoffIndex; i++) {
            filteredFees[i] = sortedDeltaFees[i];
        }
        
        uint256 sigmaFee = filteredFees.sqrt();
        uint256 calculatedDeltaFeeForBlock = N * sigmaFee;

        // TODO include intent to trade next block
        // if (swapperIntent[swapperId]) {
        //     uint256 meanFee = mean(filteredFees);
        //     calculatedDeltaFeeForBlock = meanFee.add(m.mul(sigmaFee));
        // } else {
        //     calculatedDeltaFeeForBlock = n.mul(sigmaFee);
        // }

        return calculatedDeltaFeeForBlock;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    // very costly - maybe offchain calculation necessary
    function sort(uint[] memory arr) public pure {
        if (arr.length > 0)
            quickSort(arr, 0, arr.length - 1);
    }

    function quickSort(uint[] memory arr, uint left, uint right) public pure {
        if (left >= right)
            return;
        uint p = arr[(left + right) / 2];   // p = the pivot element
        uint i = left;
        uint j = right;
        while (i < j) {
            while (arr[i] < p) ++i;
            while (arr[j] > p) --j;         // arr[j] > p means p still to the left, so j > 0
            if (arr[i] > arr[j])
                (arr[i], arr[j]) = (arr[j], arr[i]);
            else
                ++i;
        }

        // Note --j was only done when a[j] > p.  So we know: a[j] == p, a[<j] <= p, a[>j] > p
        if (j > left)
            quickSort(arr, left, j - 1);    // j > left, so j > 0
        quickSort(arr, j + 1, right);
    }
}