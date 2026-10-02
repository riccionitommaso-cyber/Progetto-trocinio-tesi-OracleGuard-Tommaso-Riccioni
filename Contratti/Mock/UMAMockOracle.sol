// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUMAMockOracle} from "../Interfacce/IUMAMockOracle.sol";

contract UMAMockOracle is IUMAMockOracle {
    int256 public constant TRUTH_YES = 1e18;
    int256 public constant TRUTH_NO = 0;

    event OutcomeReported(bytes32 indexed questionId, int256 outcome);

    mapping(bytes32 => bool) public resolved;
    mapping(bytes32 => int256) public outcomes;

    function reportOutcome(bytes32 questionId, int256 outcome) external {
        resolved[questionId] = true;
        outcomes[questionId] = outcome;
        emit OutcomeReported(questionId, outcome);
    }

    function reportManipulatedOutcome(bytes32 questionId, int256 manipulatedOutcome) external {
        resolved[questionId] = true;
        outcomes[questionId] = manipulatedOutcome;
        emit OutcomeReported(questionId, manipulatedOutcome);
    }

    function getResolvedOutcome(bytes32 questionId) external view override returns (bool isResolved, int256 outcomeValue) {
        return (resolved[questionId], outcomes[questionId]);
    }
}
