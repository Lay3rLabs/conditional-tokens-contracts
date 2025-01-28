// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract Forwarder is IERC1155Receiver {
    function call(address to, bytes calldata data) external {
        (bool success, bytes memory retData) = to.call(data);
        require(success, string(retData));
    }

    function onERC1155Received(
        address /* operator */,
        address /* from */,
        uint256 /* id */,
        uint256 /* value */,
        bytes calldata /* data */
    ) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /* operator */,
        address /* from */,
        uint256[] calldata /* ids */,
        uint256[] calldata /* values */,
        bytes calldata /* data */
    ) external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
