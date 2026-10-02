// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOracleGuard - Interfaccia dell'Oracolo Ibrido con Circuit Breaker anti-whale
/// @notice Definisce i tipi di dato, gli eventi e i metodi operativi per la risoluzione dei mercati di predizione binari
/// @dev Integra il modello economico CoC vs PfC con la democrazia digitale 1-Persona-1-Voto.
/// Separa il flusso di risoluzione tra un percorso rapido ottimistico e una giuria di validatori accreditati via SBT.
interface IOracleGuard {
    /// @notice Stati e verdetti ammessi per la risoluzione del mercato
    /// @dev UNRESOLVED indica una richiesta aperta; YES e NO corrispondono agli esiti binari; INVALID gestisce mercati ambigui/nulli
    enum Outcome {
        UNRESOLVED,
        YES,
        NO,
        INVALID
    }

    /// @notice Modalita operativa assegnata al mercato in base alla valutazione del rischio economico
    /// @dev
    /// - UMA_ONLY: CoC >= PfC (assunto di sicurezza plutocratica soddisfatto, risoluzione diretta e a basso costo)
    /// - DUAL_SBT_GUARD: PfC > CoC (vulnerabilita plutocratica rilevata, attivazione obbligatoria della giuria biologica)
    enum ResolutionMode {
        UMA_ONLY,
        DUAL_SBT_GUARD
    }

    /// @notice Emesso quando l'amministratore/protocollo valuta le metriche economiche di un mercato
    /// @param questionId Identificativo univoco della query di mercato
    /// @param pfc Profit from Corruption misurato in USD (Open Interest / valore a rischio di manipolazione)
    /// @param coc Cost of Corruption calcolato in USD (costo per acquisire il quorum del token di governance)
    /// @param mode La modalita di risoluzione determinata dalla relazione tra PfC e CoC
    event RiskEvaluated(
        bytes32 indexed questionId,
        uint256 pfc,
        uint256 coc,
        ResolutionMode mode
    );

    /// @notice Emesso all'apertura di una sessione di voto per i validatori umani verificati
    /// @param questionId Identificativo della query di mercato
    /// @param deadline Timestamp Unix limite entro cui i voti SBT devono essere registrati on-chain
    event VotingSessionStarted(bytes32 indexed questionId, uint256 deadline);

    /// @notice Emesso ogni volta che un validatore qualificato esprime la propria preferenza
    /// @param questionId Identificativo della query di mercato
    /// @param validator Indirizzo del wallet che detiene l'SBT accreditato
    /// @param choice Scelta binaria espressa (Outcome.YES oppure Outcome.NO)
    event VoteSubmitted(bytes32 indexed questionId, address indexed validator, Outcome choice);

    /// @notice Emesso alla chiusura dello scrutinio dei validatori biologici
    /// @param questionId Identificativo della query di mercato
    /// @param sbtYesPercent Percentuale di voti a favore di YES calcolata sui partecipanti effettivi
    event SbtSessionConcluded(bytes32 indexed questionId, uint256 sbtYesPercent);

    /// @notice Emesso quando il mercato si risolve tramite il Fast-Path economico di UMA senza contestazioni
    /// @param questionId Identificativo della query di mercato
    /// @param outcome Esito finale deliberato
    event FastPathResolved(bytes32 indexed questionId, Outcome outcome);

    /// @notice Emesso quando il mercato si risolve tramite scrutinio ibrido (DUAL_SBT_GUARD)
    /// @param questionId Identificativo della query di mercato
    /// @param outcome Esito finale deliberato
    /// @param circuitBreakerTriggered True se la giuria umana ha ribaltato il responso dell'oracolo finanziario UMA
    event DualPathResolved(bytes32 indexed questionId, Outcome outcome, bool circuitBreakerTriggered);

    /// @notice Valuta e registra le grandezze CoC e PfC stabilendo la modalita di risoluzione del mercato
    /// @dev Convalida se PfC > CoC imponendo la giuria democratica qualora il capitale a rischio ecceda le garanzie economiche
    /// @param questionId Identificativo univoco della query di mercato
    /// @param pfc Profit from Corruption (valore economico totale esposto al settlement)
    /// @param coc Cost of Corruption (costo finanziario stimato per corrompere il meccanismo a token)
    function evaluateMarketRisk(bytes32 questionId, uint256 pfc, uint256 coc) external;

    /// @notice Avvia la finestra temporale di voto riservata ai detentori di ValidatorSBT
    /// @dev Invocabile solo se il mercato e in modalita DUAL_SBT_GUARD e il rischio e stato formalmente valutato
    /// @param questionId Identificativo univoco della query di mercato
    /// @param duration Durata della sessione di voto espressa in secondi
    function startDisputeSession(bytes32 questionId, uint256 duration) external;

    /// @notice Registra il voto binario del validatore accreditato secondo il principio 1-Persona-1-Voto
    /// @dev Verifica che il chiamante possieda un SBT attivo e non revocato e che non abbia gia votato per la sessione
    /// @param questionId Identificativo univoco della query di mercato
    /// @param choice Esito votato (ammessi esclusivamente Outcome.YES o Outcome.NO)
    function voteSBT(bytes32 questionId, Outcome choice) external;

    /// @notice Sigilla la votazione della giuria umana e calcola il rapporto percentuale di consenso
    /// @dev Invocabile esclusivamente a finestra temporale scaduta (block.timestamp > deadline). Gestisce casi di quorum nullo
    /// @param questionId Identificativo univoco della query di mercato
    function closeSbtVoting(bytes32 questionId) external;

    /// @notice Esegue la risoluzione definitiva del mercato determinando l'esito vincente
    /// @dev Interroga il verdetto di UMA. In modalita DUAL_SBT_GUARD, valuta la divergenza rispetto alla giuria SBT:
    /// qualora emerga disaccordo qualificato (>= 70%), interviene il Circuit Breaker ribaltando il verdetto finanziario
    /// @param questionId Identificativo univoco della query di mercato
    /// @return outcome L'esito finale con cui liquidare il mercato
    function resolve(bytes32 questionId) external returns (Outcome outcome);

    /// @notice Restituisce lo stato di liquidazione e l'esito consolidato di una specifica query
    /// @param questionId Identificativo univoco della query di mercato
    /// @return isResolved True se il mercato e stato definitivamente risolto, False altrimenti
    /// @return outcome L'esito finale memorizzato
    function getResolvedOutcome(bytes32 questionId) external view returns (bool isResolved, Outcome outcome);
}