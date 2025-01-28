// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {ConditionalTokens, IERC20} from "../contracts/ConditionalTokens.sol";
import {ERC20Mintable} from "./ERC20Mintable.sol";

contract ConditionalTokensTest is Test {
    ConditionalTokens public conditionalTokens;

    address public minter = address(1);
    address public oracle = address(2);
    address public notOracle = address(3);
    address public eoaTrader = address(4);
    address public fwdExecutor = address(5);
    address public safeExecutor = address(6);
    address public counterparty = address(7);

    bytes32 public constant NULL_BYTES32 = bytes32(0);

    function setUp() public {
        conditionalTokens = new ConditionalTokens("");
    }

    function test_PrepareCondition_InvalidOutcomeSlots() public {
        bytes32 questionId = keccak256("question1");

        // Test 0 outcome slots
        vm.expectRevert("there should be more than one outcome slot");
        conditionalTokens.prepareCondition(oracle, questionId, 0);

        // Test 1 outcome slot
        vm.expectRevert("there should be more than one outcome slot");
        conditionalTokens.prepareCondition(oracle, questionId, 1);
    }

    function test_SplitMerge_ERC20() public {
        bytes32 questionId = keccak256("question2");
        uint256 outcomeSlotCount = 2;
        uint256 splitAmount = 4 ether;
        uint256 mergeAmount = 3 ether;

        // Prepare condition
        conditionalTokens.prepareCondition(
            oracle,
            questionId,
            outcomeSlotCount
        );
        bytes32 conditionId = conditionalTokens.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        // Approve conditional tokens to spend collateral
        vm.startPrank(eoaTrader);
        collateralToken.approve(address(conditionalTokens), 1e19 ether);

        // Test invalid splits
        uint256[] memory invalidPartition = new uint256[](1);
        invalidPartition[0] = 0x1;
        vm.expectRevert("partition not disjoint");
        conditionalTokens.splitPosition(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            invalidPartition,
            splitAmount
        );

        // Valid split
        uint256[] memory partition = new uint256[](2);
        partition[0] = 0x1;
        partition[1] = 0x2;
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionSplit(
            eoaTrader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            splitAmount
        );
        conditionalTokens.splitPosition(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            splitAmount
        );

        // Verify balances
        assertEq(
            collateralToken.balanceOf(eoaTrader),
            1e19 ether - splitAmount
        );
        for (uint256 i = 0; i < partition.length; i++) {
            bytes32 collectionId = conditionalTokens.getCollectionId(
                NULL_BYTES32,
                conditionId,
                partition[i]
            );
            uint256 positionId = conditionalTokens.getPositionId(
                IERC20(address(collateralToken)),
                collectionId
            );
            assertEq(
                conditionalTokens.balanceOf(eoaTrader, positionId),
                splitAmount
            );
        }

        // Test merge
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PositionsMerge(
            eoaTrader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            mergeAmount
        );
        conditionalTokens.mergePositions(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            mergeAmount
        );

        // Verify merged balances
        assertEq(
            collateralToken.balanceOf(eoaTrader),
            1e19 ether - splitAmount + mergeAmount
        );
        for (uint256 i = 0; i < partition.length; i++) {
            bytes32 collectionId = conditionalTokens.getCollectionId(
                NULL_BYTES32,
                conditionId,
                partition[i]
            );
            uint256 positionId = conditionalTokens.getPositionId(
                IERC20(address(collateralToken)),
                collectionId
            );
            assertEq(
                conditionalTokens.balanceOf(eoaTrader, positionId),
                splitAmount - mergeAmount
            );
        }

        // Test reporting and redemption
        uint256[] memory payoutNumerators = new uint256[](2);
        payoutNumerators[0] = 3;
        payoutNumerators[1] = 7;

        vm.prank(oracle);
        conditionalTokens.reportPayouts(questionId, payoutNumerators);

        // Redeem positions
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 0x1;
        vm.expectEmit(true, true, true, true);
        emit ConditionalTokens.PayoutRedemption(
            eoaTrader,
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            indexSets,
            3 ether // Expected payout based on 3/(3+7) * remaining balance
        );
        conditionalTokens.redeemPositions(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            indexSets
        );
    }
}
