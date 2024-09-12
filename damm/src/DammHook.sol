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
import {MathLibrary} from "../src/MathLibrary.sol";


contract DammHook is BaseHook {
	// Use CurrencyLibrary and BalanceDeltaLibrary
	// to add some helper functions over the Currency and BalanceDelta
	// data types 
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    FeeQuantizer feeQuantizer;
    MevClassifier mevClassifier;
    DammOracle dammOracle;

    uint256 public cutOffPercentile;
    bool public firstTransaction;
    uint256 public alpha;
    uint256 public m;
    uint256 public n;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 3000; // 0.3%

    uint24 public constant CUT_OFF_PERCENTILE = 85;
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

    struct TransactionParams {
        uint256 priorityFee;
        // Add other transaction parameters as needed
    }

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        feeQuantizer = new FeeQuantizer();
        mevClassifier = new MevClassifier(address(feeQuantizer), 5, 1, 2);
        dammOracle = new DammOracle();
        cutOffPercentile = 85;
        firstTransaction = true;
        alpha = 50;
        m = 10;
        n = 5;
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

    function calculateCombinedFee(uint256 blockId, address swapperId) internal view returns (uint256) {
        uint256 combinedFee = alpha * endogenousDynamicFee(blockId) + (100 - alpha) * exogenousDynamicFee(swapperId) / 100;
        combinedFee = combinedFee > endogenousDynamicFee(blockId) ? combinedFee : endogenousDynamicFee(blockId);
        if (combinedFee <= BASE_FEE * 125 / 100) {
            cutOffPercentile = cutOffPercentile + 5 > 100 ? 100 : cutOffPercentile + 5;
        }
        if (combinedFee > BASE_FEE * 2) {
            cutOffPercentile = cutOffPercentile - 5 < 50 ? 50 : cutOffPercentile - 5;
        }
        if (firstTransaction) {
            combinedFee *= 5;
            firstTransaction = false;
        }
        return combinedFee;
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
                    INTERIM_FEE = BASE_FEE + uint24(calculateCombinedFee(blockNumber, sender_address));
                } else if (orderBookPressure < 0 && !params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE - uint24(calculateCombinedFee(blockNumber, sender_address));                
                } else if (orderBookPressure > 0 && params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE - uint24(calculateCombinedFee(blockNumber, sender_address));                
                } else if (orderBookPressure < 0 && params.zeroForOne) {
                    INTERIM_FEE = BASE_FEE + uint24(calculateCombinedFee(blockNumber, sender_address));                
                }

                // Update the dynamic LP fee
                uint24 finalPoolFee = 
                    mevFlag ? BASE_FEE * 10: uint24(INTERIM_FEE);

                poolManager.updateDynamicLPFee(key, finalPoolFee);
                // poolManager.updateDynamicLPFee(key, fee);
                console.log("Blocknumber: ", blockNumber);
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, finalPoolFee);
    }

    function getPriorityFee(TransactionParams calldata params) public view returns (uint256) {
        // currently returns the priority fee as a random number
        uint256 minersTip = tx.gasprice - block.basefee;
        return minersTip;
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

    function endogenousDynamicFee(uint256 blockId) internal view returns (uint256) {
        if (blockId == 0) {
            return BASE_FEE;
        }
        (uint256 priceBeforePreviousBlock, uint256 priceAfterPreviousBlock) = dammOracle.getPrices(blockId);
        uint256 priceImpact = (priceAfterPreviousBlock > priceBeforePreviousBlock) ?
            (priceAfterPreviousBlock - priceBeforePreviousBlock) * 1e18 / priceBeforePreviousBlock :
            (priceBeforePreviousBlock - priceAfterPreviousBlock) * 1e18 / priceBeforePreviousBlock;
        uint256 dynamicFee = BASE_FEE + priceImpact * 1 / 100; // 1% of price impact
        return dynamicFee;
    }

    function exogenousDynamicFee(address swapperId) internal view returns (uint256) {
        if (submittedDeltaFees.length < 2) {
            return BASE_FEE;
        }
        uint256[] memory sortedFees = submittedDeltaFees;
        // Sort the fees
        for (uint i = 0; i < sortedFees.length; i++) {
            for (uint j = i + 1; j < sortedFees.length; j++) {
                if (sortedFees[i] > sortedFees[j]) {
                    uint256 temp = sortedFees[i];
                    sortedFees[i] = sortedFees[j];
                    sortedFees[j] = temp;
                }
            }
        }
        uint256 cutoffIndex = sortedFees.length * cutOffPercentile / 100;
        uint256 sum = 0;
        for (uint i = 0; i < cutoffIndex; i++) {
            sum += sortedFees[i];
        }
        uint256 meanFee = sum / cutoffIndex;
        uint256 sigmaFee = 0;
        for (uint i = 0; i < cutoffIndex; i++) {
            sigmaFee += (sortedFees[i] - meanFee) ** 2;
        }
        sigmaFee = sqrt(sigmaFee / cutoffIndex);
        uint256 dynamicFee = previousBlockSwappers[swapperId] ? meanFee + m * sigmaFee : n * sigmaFee;
        return dynamicFee;
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        return (this.afterSwap.selector, 0);
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
        uint256 sigmaFee = calculateStdDev(filteredFees, calculateMean(filteredFees));
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

    function calculateStdDev(
        uint256[] memory data, uint256 mean) internal view returns (uint256) {
        uint256 variance = 0;
        for (uint256 i = 0; i < data.length; i++) {
            variance += (data[i] - mean) * (data[i] - mean);
        }
        variance /= data.length;
        return sqrt(variance);
    }

    function calculateMean(uint256[] memory data) internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            sum += data[i];
        }
        return sum / data.length;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
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