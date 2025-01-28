// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract Forwarder is IERC1155Receiver {
    function call(address to, bytes calldata data) external {
        (bool success, bytes memory retData) = to.call(data);
        // on failure, revert with the return data as-is. `mload(retData)` gets the 4-byte length of the return data, and `add(retData, 0x20)` is the pointer to the start of the return data (after the length)
        if (!success) {
            assembly {
                revert(add(retData, 0x20), mload(retData))
            }
        }
    }

    function onERC1155Received(
        address, /* operator */
        address, /* from */
        uint256, /* id */
        uint256, /* value */
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /* operator */
        address, /* from */
        uint256[] calldata, /* ids */
        uint256[] calldata, /* values */
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
