// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OracleGuard} from "../Contratti/OracleGuard/OracleGuard.sol";
import {ValidatorSBT} from "../Contratti/Token/ValidatorSBT.sol";
import {IOracleGuard} from "../Contratti/Interfacce/IOracleGuard.sol";
import {UMAMockOracle} from "../Contratti/Mock/UMAMockOracle.sol";
import {MockPoPVerifier} from "../Contratti/Mock/MockPoPVerifier.sol";

contract OracleGuardAttackTest is Test {
    OracleGuard public guard;
    ValidatorSBT public sbt;
    UMAMockOracle public umaMock;
    MockPoPVerifier public popVerifier;

    address public admin = address(1);
    address[] public honestValidators;
    address public maliciousValidator = address(100);
    address public sybilAttacker = address(200);

    bytes32 public constant ELECTION_MARKET_ID = keccak256("US_PRESIDENTIAL_ELECTION_2024_TRUMP_WIN");

    event DualPathResolved(bytes32 indexed questionId, IOracleGuard.Outcome outcome, bool circuitBreakerTriggered);

    function setUp() public {
        vm.startPrank(admin);
        popVerifier = new MockPoPVerifier();
        sbt = new ValidatorSBT(address(popVerifier));
        umaMock = new UMAMockOracle();
        guard = new OracleGuard(address(sbt), address(umaMock));
        vm.stopPrank();

        bytes memory dummyProof = hex"deadbeef";

        for (uint160 i = 10; i < 19; i++) {
            address v = address(i);
            honestValidators.push(v);
            bytes32 nullifier = keccak256(abi.encodePacked("WORLD_ID_NULLIFIER_", v));
            vm.prank(v);
            sbt.claimWithPoP(nullifier, dummyProof);
        }

        bytes32 malNullifier = keccak256(abi.encodePacked("WORLD_ID_NULLIFIER_MALICIOUS"));
        vm.prank(maliciousValidator);
        sbt.claimWithPoP(malNullifier, dummyProof);
    }

    function test_WhaleAttackMitigatedByOracleGuard() public {
        uint256 pfc = 48_245_673 * 1e18;
        uint256 coc = 25_092_000 * 1e18;

        vm.prank(admin);
        guard.evaluateMarketRisk(ELECTION_MARKET_ID, pfc, coc);

        umaMock.reportManipulatedOutcome(ELECTION_MARKET_ID, umaMock.TRUTH_NO());

        vm.prank(admin);
        guard.startDisputeSession(ELECTION_MARKET_ID, 1 days);

        for (uint256 i = 0; i < honestValidators.length; i++) {
            vm.prank(honestValidators[i]);
            guard.voteSBT(ELECTION_MARKET_ID, IOracleGuard.Outcome.YES);
        }
        vm.prank(maliciousValidator);
        guard.voteSBT(ELECTION_MARKET_ID, IOracleGuard.Outcome.NO);

        vm.warp(block.timestamp + 1 days + 1);
        guard.closeSbtVoting(ELECTION_MARKET_ID);

        vm.expectEmit(true, false, false, true);
        emit DualPathResolved(ELECTION_MARKET_ID, IOracleGuard.Outcome.YES, true);

        IOracleGuard.Outcome winner = guard.resolve(ELECTION_MARKET_ID);

        assertEq(uint8(winner), uint8(IOracleGuard.Outcome.YES));
        (bool isResolved, IOracleGuard.Outcome savedOutcome) = guard.getResolvedOutcome(ELECTION_MARKET_ID);
        assertTrue(isResolved);
        assertEq(uint8(savedOutcome), uint8(IOracleGuard.Outcome.YES));
    }

    function test_CircuitBreakerDoesNotTriggerWithoutSupermajority() public {
        bytes32 marketId = keccak256("CLOSE_CONSENSUS_MARKET");
        uint256 pfc = 10_000_000 * 1e18;
        uint256 coc = 5_000_000 * 1e18;

        vm.prank(admin);
        guard.evaluateMarketRisk(marketId, pfc, coc);
        umaMock.reportOutcome(marketId, umaMock.TRUTH_NO());

        vm.prank(admin);
        guard.startDisputeSession(marketId, 1 days);

        for (uint256 i = 0; i < 6; i++) {
            vm.prank(honestValidators[i]);
            guard.voteSBT(marketId, IOracleGuard.Outcome.YES);
        }
        for (uint256 i = 6; i < 9; i++) {
            vm.prank(honestValidators[i]);
            guard.voteSBT(marketId, IOracleGuard.Outcome.NO);
        }
        vm.prank(maliciousValidator);
        guard.voteSBT(marketId, IOracleGuard.Outcome.NO);

        vm.warp(block.timestamp + 1 days + 1);
        guard.closeSbtVoting(marketId);

        vm.expectEmit(true, false, false, true);
        emit DualPathResolved(marketId, IOracleGuard.Outcome.NO, false);

        IOracleGuard.Outcome winner = guard.resolve(marketId);
        assertEq(uint8(winner), uint8(IOracleGuard.Outcome.NO));
    }

    function test_RevertIfValidatorVotesTwice() public {
        vm.prank(admin);
        guard.evaluateMarketRisk(ELECTION_MARKET_ID, 2e18, 1e18);

        vm.prank(admin);
        guard.startDisputeSession(ELECTION_MARKET_ID, 1 days);

        vm.prank(honestValidators[0]);
        guard.voteSBT(ELECTION_MARKET_ID, IOracleGuard.Outcome.YES);

        vm.prank(honestValidators[0]);
        vm.expectRevert("OracleGuard: Questo validatore ha gia votato");
        guard.voteSBT(ELECTION_MARKET_ID, IOracleGuard.Outcome.YES);
    }

    function test_RevertIfVoterLacksSBT() public {
        vm.prank(admin);
        guard.evaluateMarketRisk(ELECTION_MARKET_ID, 2e18, 1e18);

        vm.prank(admin);
        guard.startDisputeSession(ELECTION_MARKET_ID, 1 days);

        vm.prank(sybilAttacker);
        vm.expectRevert("OracleGuard: Indirizzo sprovvisto di SBT valido");
        guard.voteSBT(ELECTION_MARKET_ID, IOracleGuard.Outcome.YES);
    }

    function test_TemporalProtectionsRevert() public {
        vm.prank(admin);
        guard.evaluateMarketRisk(ELECTION_MARKET_ID, 2e18, 1e18);
        umaMock.reportOutcome(ELECTION_MARKET_ID, umaMock.TRUTH_YES());

        vm.prank(admin);
        guard.startDisputeSession(ELECTION_MARKET_ID, 1 days);

        vm.expectRevert("OracleGuard: Finestra di voto ancora aperta");
        guard.closeSbtVoting(ELECTION_MARKET_ID);

        vm.expectRevert("OracleGuard: Sessione SBT non ancora chiusa");
        guard.resolve(ELECTION_MARKET_ID);
    }
}
