// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OracleGuard} from "../Contratti/OracleGuard/OracleGuard.sol";
import {IOracleGuard} from "../Contratti/Interfacce/IOracleGuard.sol";
import {IUMAMockOracle} from "../Contratti/Interfacce/IUMAMockOracle.sol";
import {IValidatorSBT} from "../Contratti/Interfacce/IValidatorSBT.sol";
import {ValidatorSBT} from "../Contratti/Token/ValidatorSBT.sol";
import {UMAMockOracle} from "../Contratti/Mock/UMAMockOracle.sol";
import {MockPoPVerifier} from "../Contratti/Mock/MockPoPVerifier.sol";

contract OracleGuardStandardTest is Test {
    OracleGuard public guard;
    ValidatorSBT public sbt;
    UMAMockOracle public umaMock;
    MockPoPVerifier public popVerifier;

    address public admin = address(1);
    address public validator1 = address(10);
    bytes32 public constant QUESTION_ID = keccak256("POLITICAL_ELECTION_QUESTION_2024");

    event RiskEvaluated(bytes32 indexed questionId, uint256 pfc, uint256 coc, IOracleGuard.ResolutionMode mode);
    event FastPathResolved(bytes32 indexed questionId, IOracleGuard.Outcome outcome);

    function setUp() public {
        vm.startPrank(admin);
        popVerifier = new MockPoPVerifier();
        sbt = new ValidatorSBT(address(popVerifier));
        umaMock = new UMAMockOracle();
        guard = new OracleGuard(address(sbt), address(umaMock));
        vm.stopPrank();

        bytes32 nullifier = keccak256("V1_NULLIFIER");
        vm.prank(validator1);
        sbt.claimWithPoP(nullifier, hex"deadbeef");
    }

    function test_EvaluateMarketRiskUnderThreshold() public {
        uint256 pfc = 5_000_000 * 1e18;
        uint256 coc = 25_000_000 * 1e18;

        vm.expectEmit(true, false, false, true);
        emit RiskEvaluated(QUESTION_ID, pfc, coc, IOracleGuard.ResolutionMode.UMA_ONLY);

        vm.prank(admin);
        guard.evaluateMarketRisk(QUESTION_ID, pfc, coc);

        (uint256 savedPfc, uint256 savedCoc, IOracleGuard.ResolutionMode mode, bool isEvaluated) = guard.marketRisks(QUESTION_ID);
        assertEq(savedPfc, pfc);
        assertEq(savedCoc, coc);
        assertEq(uint8(mode), uint8(IOracleGuard.ResolutionMode.UMA_ONLY));
        assertTrue(isEvaluated);
    }

    function test_FastPathResolvesDirectlyViaUMA() public {
        uint256 pfc = 10_000_000 * 1e18;
        uint256 coc = 25_000_000 * 1e18;

        vm.prank(admin);
        guard.evaluateMarketRisk(QUESTION_ID, pfc, coc);

        umaMock.reportOutcome(QUESTION_ID, umaMock.TRUTH_YES());

        vm.expectEmit(true, false, false, true);
        emit FastPathResolved(QUESTION_ID, IOracleGuard.Outcome.YES);

        IOracleGuard.Outcome resolvedOutcome = guard.resolve(QUESTION_ID);

        assertEq(uint8(resolvedOutcome), uint8(IOracleGuard.Outcome.YES));
        (bool isResolved, IOracleGuard.Outcome savedOutcome) = guard.getResolvedOutcome(QUESTION_ID);
        assertTrue(isResolved);
        assertEq(uint8(savedOutcome), uint8(IOracleGuard.Outcome.YES));
    }
}
