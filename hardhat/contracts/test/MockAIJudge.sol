// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AIJudge} from "../AIJudge.sol";

contract MockAIJudge is AIJudge {
    bytes public mockReview = bytes('{"winnerIndex":0,"summary":"mock"}');

    function setMockReview(bytes calldata review) external {
        mockReview = review;
    }

    function _executePrecompile(
        address,
        bytes memory
    ) internal view override returns (bytes memory) {
        return
            abi.encode(
                false,
                mockReview,
                bytes(""),
                "",
                ConvoHistory("", "", "")
            );
    }
}
