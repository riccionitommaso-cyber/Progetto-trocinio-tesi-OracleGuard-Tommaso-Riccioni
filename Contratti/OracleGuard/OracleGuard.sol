// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleGuard} from "../Interfacce/IOracleGuard.sol";
import {IUMAMockOracle} from "../Interfacce/IUMAMockOracle.sol";
import {IValidatorSBT} from "../Interfacce/IValidatorSBT.sol";

contract OracleGuard is IOracleGuard {
    int256 public constant UMA_TRUTH_YES = 1e18;
    int256 public constant UMA_TRUTH_NO = 0;
    uint256 public constant SBT_OVERRIDE_MAJORITY_THRESHOLD = 70;

    struct MarketRiskData {
        uint256 pfc;
        uint256 coc;
        ResolutionMode mode;
        bool isEvaluated;
    }

    struct DisputeSession {
        bytes32 questionId;
        uint256 deadline;
        uint256 votesYes;
        uint256 votesNo;
        bool isSbtResolved;
        uint256 sbtYesPercent;
        mapping(address => bool) hasVoted;
    }

    IValidatorSBT public immutable sbtContract;
    IUMAMockOracle public immutable umaOracle;
    address public admin;

    mapping(bytes32 => MarketRiskData) public marketRisks;
    mapping(bytes32 => DisputeSession) public sessions;
    mapping(bytes32 => bool) public isMarketResolved;
    mapping(bytes32 => Outcome) public finalOutcomes;

    modifier onlyAdmin() {
        require(msg.sender == admin, "OracleGuard: Solo admin");
        _;
    }

    constructor(address _sbtContract, address _umaOracle) {
        require(_sbtContract != address(0), "OracleGuard: Indirizzo SBT non valido");
        require(_umaOracle != address(0), "OracleGuard: Indirizzo UMA non valido");
        admin = msg.sender;
        sbtContract = IValidatorSBT(_sbtContract);
        umaOracle = IUMAMockOracle(_umaOracle);
    }

    function evaluateMarketRisk(bytes32 questionId, uint256 pfc, uint256 coc) external override onlyAdmin {
        MarketRiskData storage risk = marketRisks[questionId];
        risk.pfc = pfc;
        risk.coc = coc;
        risk.isEvaluated = true;

        if (pfc > coc) {
            risk.mode = ResolutionMode.DUAL_SBT_GUARD;
        } else {
            risk.mode = ResolutionMode.UMA_ONLY;
        }

        emit RiskEvaluated(questionId, pfc, coc, risk.mode);
    }

    function startDisputeSession(bytes32 questionId, uint256 duration) external override onlyAdmin {
        MarketRiskData storage risk = marketRisks[questionId];
        require(risk.isEvaluated, "OracleGuard: Rischio non ancora valutato");
        require(risk.mode == ResolutionMode.DUAL_SBT_GUARD, "OracleGuard: SBT non richiesto per questo mercato");

        DisputeSession storage s = sessions[questionId];
        require(s.deadline == 0, "OracleGuard: Sessione gia esistente");
        require(duration > 0, "OracleGuard: Durata non valida");

        s.questionId = questionId;
        s.deadline = block.timestamp + duration;

        emit VotingSessionStarted(questionId, s.deadline);
    }

    function voteSBT(bytes32 questionId, Outcome choice) external override {
        DisputeSession storage s = sessions[questionId];
        require(s.deadline > 0 && block.timestamp <= s.deadline, "OracleGuard: Votazione non attiva o scaduta");
        require(sbtContract.isQualifiedValidator(msg.sender), "OracleGuard: Indirizzo sprovvisto di SBT valido");
        require(!s.hasVoted[msg.sender], "OracleGuard: Questo validatore ha gia votato");
        require(choice == Outcome.YES || choice == Outcome.NO, "OracleGuard: Scelta ammessa solo YES o NO");

        s.hasVoted[msg.sender] = true;

        if (choice == Outcome.YES) {
            s.votesYes++;
        } else {
            s.votesNo++;
        }

        emit VoteSubmitted(questionId, msg.sender, choice);
    }

    function closeSbtVoting(bytes32 questionId) external override {
        DisputeSession storage s = sessions[questionId];
        require(s.deadline > 0, "OracleGuard: Sessione non avviata");
        require(block.timestamp > s.deadline, "OracleGuard: Finestra di voto ancora aperta");
        require(!s.isSbtResolved, "OracleGuard: Sessione gia conteggiata");

        uint256 total = s.votesYes + s.votesNo;
        if (total == 0) {
            s.sbtYesPercent = 50;
        } else {
            s.sbtYesPercent = (s.votesYes * 100) / total;
        }

        s.isSbtResolved = true;
        emit SbtSessionConcluded(questionId, s.sbtYesPercent);
    }

    function resolve(bytes32 questionId) external override returns (Outcome winner) {
        require(!isMarketResolved[questionId], "OracleGuard: Mercato gia risolto");

        MarketRiskData storage risk = marketRisks[questionId];
        require(risk.isEvaluated, "OracleGuard: Rischio non valutato");

        (bool umaResolved, int256 umaOutcomeValue) = umaOracle.getResolvedOutcome(questionId);
        require(umaResolved, "OracleGuard: Esito UMA in attesa");

        Outcome umaOutcome = (umaOutcomeValue == UMA_TRUTH_YES) ? Outcome.YES : Outcome.NO;

        if (risk.mode == ResolutionMode.UMA_ONLY) {
            winner = umaOutcome;
            isMarketResolved[questionId] = true;
            finalOutcomes[questionId] = winner;

            emit FastPathResolved(questionId, winner);
            return winner;
        }

        DisputeSession storage s = sessions[questionId];
        require(s.isSbtResolved, "OracleGuard: Sessione SBT non ancora chiusa");

        bool circuitBreakerTriggered = false;

        if (umaOutcome == Outcome.NO && s.sbtYesPercent >= SBT_OVERRIDE_MAJORITY_THRESHOLD) {
            circuitBreakerTriggered = true;
            winner = Outcome.YES;
        } else if (umaOutcome == Outcome.YES && s.sbtYesPercent <= (100 - SBT_OVERRIDE_MAJORITY_THRESHOLD)) {
            circuitBreakerTriggered = true;
            winner = Outcome.NO;
        } else {
            winner = umaOutcome;
        }

        isMarketResolved[questionId] = true;
        finalOutcomes[questionId] = winner;

        emit DualPathResolved(questionId, winner, circuitBreakerTriggered);
        return winner;
    }

    function getResolvedOutcome(bytes32 questionId) external view override returns (bool isResolved, Outcome outcome) {
        return (isMarketResolved[questionId], finalOutcomes[questionId]);
    }
}
