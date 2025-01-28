// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {ConditionalTokens, IERC20, ERC1155} from "../contracts/ConditionalTokens.sol";
import {ERC20Mintable} from "./ERC20Mintable.sol";
import {Forwarder} from "./Forwarder.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ConditionalTokensTest is Test {
    ConditionalTokens public conditionalTokens;
    bytes32 public questionId;
    bytes32 public conditionId;

    address public ORACLE = vm.addr(1);
    bytes32 public constant NULL_BYTES32 = bytes32(0);
    uint256 public constant OUTCOME_SLOT_COUNT = 256;

    function setUp() public {
        conditionalTokens = new ConditionalTokens("");
        questionId = keccak256("question");
        conditionId = conditionalTokens.getConditionId(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );
    }

    function test_PrepareCondition_InvalidOutcomeSlots() public {
        // Test 0 outcome slots
        vm.expectRevert("there should be more than one outcome slot");
        conditionalTokens.prepareCondition(ORACLE, questionId, 0);

        // Test 1 outcome slot
        vm.expectRevert("there should be more than one outcome slot");
        conditionalTokens.prepareCondition(ORACLE, questionId, 1);
    }

    function test_PrepareCondition_Valid() public {
        // Outcome slot count should not be set
        assertEq(conditionalTokens.getOutcomeSlotCount(conditionId), 0);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.ConditionPreparation(
            conditionId,
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // Call the function
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // Outcome slot count should be set
        assertEq(
            conditionalTokens.getOutcomeSlotCount(conditionId),
            OUTCOME_SLOT_COUNT
        );

        // Payout denominator should not be set
        assertEq(conditionalTokens.payoutDenominator(conditionId), 0);

        // Cannot prepare the same condition more than once
        vm.expectRevert("condition already prepared");
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );
    }
}

abstract contract ConditionalTokensSplitMergeBase is Test {
    ConditionalTokens public conditionalTokens;
    ERC20Mintable public collateralToken;
    address public trader;
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public firstPositionId;
    uint256 public secondPositionId;
    uint256[] public partition;

    bytes32 public constant NULL_BYTES32 = bytes32(0);
    address public ORACLE = vm.addr(10);
    address public NOT_ORACLE = vm.addr(20);
    address public COUNTERPARTY = vm.addr(30);

    uint256 public constant OUTCOME_SLOT_COUNT = 2;
    uint256 public constant SPLIT_AMOUNT = 4 ether;
    uint256 public constant MERGE_AMOUNT = 3 ether;
    uint256 public constant COLLATERAL_TOKEN_COUNT = 10 ether;
    uint256 public constant TRANSFER_AMOUNT = 1 ether;

    // for the 'many conditions' tests at the bottom
    struct Condition {
        bytes32 id;
        bytes32 questionId;
        uint256 outcomeSlotCount;
    }
    Condition[4] public conditions;

    function setUp() public virtual {
        conditionalTokens = new ConditionalTokens("");
        collateralToken = new ERC20Mintable();
        trader = getTraderAddress();
        questionId = keccak256("question");
        conditionId = conditionalTokens.getConditionId(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        firstPositionId = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)),
            conditionalTokens.getCollectionId(
                NULL_BYTES32,
                conditionId,
                partition[0]
            )
        );
        secondPositionId = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)),
            conditionalTokens.getCollectionId(
                NULL_BYTES32,
                conditionId,
                partition[1]
            )
        );

        for (uint256 i = 0; i < conditions.length; i++) {
            conditions[i].questionId = keccak256(
                abi.encodePacked("question", i)
            );
            conditions[i].outcomeSlotCount = 4;
            conditions[i].id = conditionalTokens.getConditionId(
                ORACLE,
                conditions[i].questionId,
                conditions[i].outcomeSlotCount
            );
        }
    }

    // Abstract functions to be implemented by different trader types
    function getTraderAddress() public view virtual returns (address);
    function executeCall(address target, bytes memory data) public virtual;

    function split(
        bytes32 conditionId_,
        uint256[] memory partition_,
        uint256 amount,
        bytes32 parentCollectionId
    ) public {
        executeCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ConditionalTokens.splitPosition.selector,
                address(collateralToken),
                parentCollectionId,
                conditionId_,
                partition_,
                amount
            )
        );
    }

    function merge(
        bytes32 conditionId_,
        uint256[] memory partition_,
        uint256 amount,
        bytes32 parentCollectionId
    ) public {
        executeCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ConditionalTokens.mergePositions.selector,
                address(collateralToken),
                parentCollectionId,
                conditionId_,
                partition_,
                amount
            )
        );
    }

    function redeem(
        bytes32 conditionId_,
        uint256[] memory indexSets,
        bytes32 parentCollectionId
    ) public {
        executeCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ConditionalTokens.redeemPositions.selector,
                address(collateralToken),
                parentCollectionId,
                conditionId_,
                indexSets
            )
        );
    }

    function transfer(address to, uint256 positionId, uint256 amount) public {
        executeCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ERC1155.safeTransferFrom.selector,
                trader,
                to,
                positionId,
                amount,
                ""
            )
        );
    }

    function collateralBalanceOf(address addr) public view returns (uint256) {
        return collateralToken.balanceOf(addr);
    }

    function testSplitAndMerge() public {
        // Mint and approve collateral
        collateralToken.mint(trader, COLLATERAL_TOKEN_COUNT);
        executeCall(
            address(collateralToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(conditionalTokens),
                COLLATERAL_TOKEN_COUNT
            )
        );

        // Fail to split if condition not prepared
        vm.expectRevert("condition not prepared yet");
        split(conditionId, partition, SPLIT_AMOUNT, NULL_BYTES32);

        // Prepare condition
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // Fail to prepare again
        vm.expectRevert("condition already prepared");
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // Fail to split if given index sets aren't disjoint
        vm.expectRevert("partition not disjoint");
        uint256[] memory notDisjoint = new uint256[](2);
        notDisjoint[0] = 2;
        notDisjoint[1] = 2;
        split(conditionId, notDisjoint, SPLIT_AMOUNT, NULL_BYTES32);

        // Fail to split if partitioning more than condition's outcome slots
        vm.expectRevert("got invalid index set");
        uint256[] memory wrongNumberOfSlots = new uint256[](3);
        wrongNumberOfSlots[0] = 0;
        wrongNumberOfSlots[1] = 1;
        wrongNumberOfSlots[2] = 2;
        split(conditionId, wrongNumberOfSlots, SPLIT_AMOUNT, NULL_BYTES32);

        // Fail to split if given a singleton partition
        vm.expectRevert("got empty or singleton partition");
        uint256[] memory singletonPartition = new uint256[](1);
        singletonPartition[0] = 3;
        split(conditionId, singletonPartition, SPLIT_AMOUNT, NULL_BYTES32);

        // Fail to split if given an incomplete singleton partition
        vm.expectRevert("got empty or singleton partition");
        uint256[] memory incompleteSingletonPartition = new uint256[](1);
        incompleteSingletonPartition[0] = 1;
        split(
            conditionId,
            incompleteSingletonPartition,
            SPLIT_AMOUNT,
            NULL_BYTES32
        );

        // valid split, expect PositionSplit event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionSplit(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            SPLIT_AMOUNT
        );
        split(conditionId, partition, SPLIT_AMOUNT, NULL_BYTES32);

        // should transfer split collateral from trader
        assertEq(
            collateralBalanceOf(trader),
            COLLATERAL_TOKEN_COUNT - SPLIT_AMOUNT
        );
        assertEq(collateralBalanceOf(address(conditionalTokens)), SPLIT_AMOUNT);

        // should mint amounts in positions associated with partition
        assertEq(
            conditionalTokens.balanceOf(trader, firstPositionId),
            SPLIT_AMOUNT
        );
        assertEq(
            conditionalTokens.balanceOf(trader, secondPositionId),
            SPLIT_AMOUNT
        );

        // should not merge if amount exceeds balances in to-be-merged positions
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector,
                trader,
                SPLIT_AMOUNT,
                SPLIT_AMOUNT + 1,
                firstPositionId
            )
        );
        merge(conditionId, partition, SPLIT_AMOUNT + 1, NULL_BYTES32);

        // valid merge, expect PositionsMerge event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionsMerge(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            MERGE_AMOUNT
        );
        merge(conditionId, partition, MERGE_AMOUNT, NULL_BYTES32);

        // should transfer split collateral back to trader
        assertEq(
            collateralBalanceOf(trader),
            COLLATERAL_TOKEN_COUNT - SPLIT_AMOUNT + MERGE_AMOUNT
        );
        assertEq(
            collateralBalanceOf(address(conditionalTokens)),
            SPLIT_AMOUNT - MERGE_AMOUNT
        );

        // should burn amounts in positions associated with partition
        assertEq(
            conditionalTokens.balanceOf(trader, firstPositionId),
            SPLIT_AMOUNT - MERGE_AMOUNT
        );
        assertEq(
            conditionalTokens.balanceOf(trader, secondPositionId),
            SPLIT_AMOUNT - MERGE_AMOUNT
        );
    }

    function testMergeAndTransferAndReport() public {
        uint256[] memory payoutNumerators = new uint256[](2);
        payoutNumerators[0] = 3;
        payoutNumerators[1] = 7;

        // Mint and approve collateral
        collateralToken.mint(trader, COLLATERAL_TOKEN_COUNT);
        executeCall(
            address(collateralToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(conditionalTokens),
                COLLATERAL_TOKEN_COUNT
            )
        );

        // Prepare condition
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // valid split, expect PositionSplit event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionSplit(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            SPLIT_AMOUNT
        );
        split(conditionId, partition, SPLIT_AMOUNT, NULL_BYTES32);

        // valid merge, expect PositionsMerge event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionsMerge(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            MERGE_AMOUNT
        );
        merge(conditionId, partition, MERGE_AMOUNT, NULL_BYTES32);

        // should not allow transferring more than split balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector,
                trader,
                1 ether,
                SPLIT_AMOUNT + 1,
                firstPositionId
            )
        );
        transfer(COUNTERPARTY, firstPositionId, SPLIT_AMOUNT + 1);

        // should not allow reporting by incorrect oracle
        vm.expectRevert("condition not prepared or found");
        vm.prank(NOT_ORACLE);
        conditionalTokens.reportPayouts(questionId, payoutNumerators);

        // should not allow reporting with wrong questionId
        vm.expectRevert("condition not prepared or found");
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(
            keccak256("wrong question"),
            payoutNumerators
        );

        // should not allow reporting with no slots
        vm.expectRevert("there should be more than one outcome slot");
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(questionId, new uint256[](0));

        // should not allow reporting with wrong number of slots
        vm.expectRevert("condition not prepared or found");
        uint256[] memory noReporting = new uint256[](3);
        noReporting[0] = 2;
        noReporting[1] = 3;
        noReporting[2] = 5;
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(questionId, noReporting);

        // should not allow reporting with zero payouts in all slots
        vm.expectRevert("payout is all zeroes");
        uint256[] memory zeroPayouts = new uint256[](2);
        zeroPayouts[0] = 0;
        zeroPayouts[1] = 0;
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(questionId, zeroPayouts);

        // successful transfer
        transfer(COUNTERPARTY, firstPositionId, TRANSFER_AMOUNT);

        // report and emit ConditionResolution event
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.ConditionResolution(
            conditionId,
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT,
            payoutNumerators
        );
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(questionId, payoutNumerators);

        // should make reported payout numerators available
        for (uint256 i = 0; i < payoutNumerators.length; i++) {
            assertEq(
                conditionalTokens.payoutNumerators(conditionId, i),
                payoutNumerators[i]
            );
        }

        // should not merge if any amount is short
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector,
                trader,
                0,
                SPLIT_AMOUNT,
                firstPositionId
            )
        );
        merge(conditionId, partition, SPLIT_AMOUNT, NULL_BYTES32);
    }

    function testRedeem() public {
        uint256[] memory payoutNumerators = new uint256[](2);
        payoutNumerators[0] = 3;
        payoutNumerators[1] = 7;

        // Mint and approve collateral
        collateralToken.mint(trader, COLLATERAL_TOKEN_COUNT);
        executeCall(
            address(collateralToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(conditionalTokens),
                COLLATERAL_TOKEN_COUNT
            )
        );

        // Prepare condition
        conditionalTokens.prepareCondition(
            ORACLE,
            questionId,
            OUTCOME_SLOT_COUNT
        );

        // Split
        split(conditionId, partition, SPLIT_AMOUNT, NULL_BYTES32);

        // Transfer
        transfer(COUNTERPARTY, firstPositionId, TRANSFER_AMOUNT);

        // Report
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(questionId, payoutNumerators);

        uint256 payoutDenominator = 0;
        for (uint256 i = 0; i < payoutNumerators.length; i++) {
            payoutDenominator += payoutNumerators[i];
        }
        uint256 payout = (((SPLIT_AMOUNT - TRANSFER_AMOUNT) *
            payoutNumerators[0]) / payoutDenominator) +
            ((SPLIT_AMOUNT * payoutNumerators[1]) / payoutDenominator);

        // redeem should emit PayoutRedemption event
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PayoutRedemption(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            payout
        );
        redeem(conditionId, partition, NULL_BYTES32);

        // should zero out redeemed positions
        assertEq(
            conditionalTokens.balanceOf(
                trader,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    conditionalTokens.getCollectionId(
                        NULL_BYTES32,
                        conditionId,
                        partition[0]
                    )
                )
            ),
            0
        );
        assertEq(
            conditionalTokens.balanceOf(
                trader,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    conditionalTokens.getCollectionId(
                        NULL_BYTES32,
                        conditionId,
                        partition[1]
                    )
                )
            ),
            0
        );

        // should not affect other's positions
        assertEq(
            conditionalTokens.balanceOf(COUNTERPARTY, firstPositionId),
            TRANSFER_AMOUNT
        );

        // should credit payout as collateral
        assertEq(
            collateralBalanceOf(trader),
            COLLATERAL_TOKEN_COUNT - SPLIT_AMOUNT + payout
        );
    }

    function testManyConditionsSplit() public {
        // Mint and approve collateral
        collateralToken.mint(trader, COLLATERAL_TOKEN_COUNT);
        executeCall(
            address(collateralToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(conditionalTokens),
                COLLATERAL_TOKEN_COUNT
            )
        );

        for (uint256 i = 0; i < conditions.length; i++) {
            conditionalTokens.prepareCondition(
                ORACLE,
                conditions[i].questionId,
                conditions[i].outcomeSlotCount
            );
        }

        uint256[] memory partition0 = new uint256[](2);
        partition0[0] = 7;
        partition0[1] = 8;

        split(
            conditions[0].id,
            partition0,
            COLLATERAL_TOKEN_COUNT,
            NULL_BYTES32
        );
        transfer(
            COUNTERPARTY,
            conditionalTokens.getPositionId(
                IERC20(address(collateralToken)),
                conditionalTokens.getCollectionId(
                    NULL_BYTES32,
                    conditions[0].id,
                    partition0[1]
                )
            ),
            COLLATERAL_TOKEN_COUNT
        );

        // split to a deeper position with another condition
        uint256[] memory partition2 = new uint256[](3);
        partition2[0] = 1;
        partition2[1] = 2;
        partition2[2] = 12;
        bytes32 parentCollectionId = conditionalTokens.getCollectionId(
            NULL_BYTES32,
            conditions[0].id,
            partition0[0]
        );

        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionSplit(
            trader,
            IERC20(address(collateralToken)),
            parentCollectionId,
            conditions[1].id,
            partition2,
            SPLIT_AMOUNT
        );
        split(conditions[1].id, partition2, SPLIT_AMOUNT, parentCollectionId);

        // ensure value in parent position is burned
        assertEq(
            conditionalTokens.balanceOf(
                trader,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    parentCollectionId
                )
            ),
            COLLATERAL_TOKEN_COUNT - SPLIT_AMOUNT
        );

        // ensure value minted in child positions
        assertEq(
            conditionalTokens.balanceOf(
                trader,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    conditionalTokens.getCollectionId(
                        parentCollectionId,
                        conditions[1].id,
                        partition2[0]
                    )
                )
            ),
            SPLIT_AMOUNT
        );
        assertEq(
            conditionalTokens.balanceOf(
                trader,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    conditionalTokens.getCollectionId(
                        parentCollectionId,
                        conditions[1].id,
                        partition2[1]
                    )
                )
            ),
            SPLIT_AMOUNT
        );
    }

    function testManyConditionsReport() public {
        // Mint and approve collateral
        collateralToken.mint(trader, COLLATERAL_TOKEN_COUNT);
        executeCall(
            address(collateralToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(conditionalTokens),
                COLLATERAL_TOKEN_COUNT
            )
        );

        for (uint256 i = 0; i < conditions.length; i++) {
            conditionalTokens.prepareCondition(
                ORACLE,
                conditions[i].questionId,
                conditions[i].outcomeSlotCount
            );
        }

        uint256[] memory partition0 = new uint256[](2);
        partition0[0] = 7;
        partition0[1] = 8;

        uint256[] memory finalReport = new uint256[](4);
        finalReport[0] = 0;
        finalReport[1] = 33;
        finalReport[2] = 289;
        finalReport[3] = 678;

        uint256[] memory redeemSet = new uint256[](1);
        redeemSet[0] = partition0[0];

        uint256 payoutDenominator = 0;
        uint256 payout = 0;
        for (uint256 i = 0; i < finalReport.length; i++) {
            payoutDenominator += finalReport[i];
            if (redeemSet[0] & (1 << i) != 0) {
                payout += finalReport[i];
            }
        }
        payout = (payout * COLLATERAL_TOKEN_COUNT) / payoutDenominator;

        split(
            conditions[0].id,
            partition0,
            COLLATERAL_TOKEN_COUNT,
            NULL_BYTES32
        );
        transfer(
            COUNTERPARTY,
            conditionalTokens.getPositionId(
                IERC20(address(collateralToken)),
                conditionalTokens.getCollectionId(
                    NULL_BYTES32,
                    conditions[0].id,
                    partition0[1]
                )
            ),
            COLLATERAL_TOKEN_COUNT
        );

        // report and emit ConditionResolution event
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.ConditionResolution(
            conditions[0].id,
            ORACLE,
            conditions[0].questionId,
            conditions[0].outcomeSlotCount,
            finalReport
        );
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(conditions[0].questionId, finalReport);

        // should reflect report via payoutNumerators
        for (uint256 i = 0; i < finalReport.length; i++) {
            assertEq(
                conditionalTokens.payoutNumerators(conditions[0].id, i),
                finalReport[i]
            );
        }

        // should not allow another update to the report
        vm.expectRevert("payout denominator already set");
        vm.prank(ORACLE);
        conditionalTokens.reportPayouts(conditions[0].questionId, finalReport);

        // redeem should emit PayoutRedemption event
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PayoutRedemption(
            trader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditions[0].id,
            redeemSet,
            payout
        );
        redeem(conditions[0].id, redeemSet, NULL_BYTES32);
    }
}

// EOA Trader Implementation
contract EOATraderTest is ConditionalTokensSplitMergeBase {
    address internal TRADER = vm.addr(100);

    function setUp() public override {
        super.setUp();
    }

    function getTraderAddress() public view override returns (address) {
        return TRADER;
    }

    function executeCall(address target, bytes memory data) public override {
        vm.prank(TRADER);
        (bool success, ) = target.call(data);
        require(success, "Call failed");
    }
}

// Forwarder Trader Implementation
contract ForwarderTraderTest is ConditionalTokensSplitMergeBase {
    Forwarder public forwarder;
    address internal FORWARDER_EXECUTOR = vm.addr(1000);

    function setUp() public override {
        forwarder = new Forwarder();
        super.setUp();
    }

    function getTraderAddress() public view override returns (address) {
        return address(forwarder);
    }

    function executeCall(address target, bytes memory data) public override {
        vm.prank(FORWARDER_EXECUTOR);
        forwarder.call(target, data);
    }
}
