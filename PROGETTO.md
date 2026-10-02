# OracleGuard

## 1. Scopo del progetto

OracleGuard è un prototipo di sistema per la risoluzione di mercati di previsione binari. Combina:

- un oracolo UMA, usato come percorso ordinario e veloce;
- un registro di validatori umani identificati tramite Proof-of-Personhood (PoP);
- un Soulbound Token (SBT) che abilita il principio `1 persona = 1 voto`;
- un circuit breaker che può correggere un responso UMA quando il rischio economico di manipolazione è elevato.

La scelta del percorso dipende dal confronto tra:

- `PfC` (`Profit from Corruption`): valore economico esposto alla manipolazione, rappresentato nel contratto dal parametro `pfc`;
- `CoC` (`Cost of Corruption`): costo stimato per controllare il meccanismo UMA, rappresentato dal parametro `coc`.

La regola è:

```text
PfC <= CoC  -> UMA_ONLY
PfC >  CoC  -> DUAL_SBT_GUARD
```

Nel primo caso il mercato viene risolto direttamente da UMA. Nel secondo caso, oltre al responso UMA, viene attivata una votazione dei validatori SBT.

## 2. Struttura del repository

```text
.
├── Contratti/
│   ├── Interfacce/
│   ├── Mock/
│   ├── OracleGuard/
│   └── Token/
├── Test/
├── Simulazione/
│   ├── Analisi empirica storica/
│   ├── Simulazione dinamica agenti/
│   ├── dati_simulazione/
│   └── Paper per simulazione/
├── cache/
├── lib/forge-std/
├── CONTRATTI_E_INTERFACCE.md
├── SIMULAZIONI.md
├── TEST_FOUNDRY.md
└── PROGETTO.md
```

### Directory principali

- `Contratti/`: sorgenti Solidity del protocollo.
- `Contratti/Interfacce/`: contratti astratti e API condivise.
- `Contratti/Mock/`: implementazioni semplificate usate nei test e nelle dimostrazioni.
- `Contratti/OracleGuard/`: coordinatore della risoluzione.
- `Contratti/Token/`: implementazione dell'identità SBT dei validatori.
- `Test/`: test Foundry dei contratti.
- `Simulazione/`: analisi storica e simulazione dinamica del rischio economico.
- `lib/forge-std/`: submodule `forge-std`, libreria standard di Foundry per test, cheatcode e asserzioni.
- `cache/` e `out/`: artefatti generati da Foundry, non sorgenti del protocollo.

## 3. Architettura complessiva

```text
                    +----------------------+
                    |      OracleGuard     |
                    | valutazione e settle  |
                    +----------+-----------+
                               |
             +-----------------+-----------------+
             |                                   |
             v                                   v
   +-------------------+              +-------------------+
   |   IUMAMockOracle  |              |   IValidatorSBT   |
   |     UMA mock      |              | registro validator |
   +---------+---------+              +---------+---------+
             |                                  |
             v                                  v
   +-------------------+              +-------------------+
   |   UMAMockOracle   |              |   ValidatorSBT    |
   +-------------------+              +---------+---------+
                                                    |
                                                    v
                                           +-------------------+
                                           |   IPoPVerifier    |
                                           | verifica identità |
                                           +---------+---------+
                                                     |
                                                     v
                                           +-------------------+
                                           |  MockPoPVerifier  |
                                           +-------------------+
```

`OracleGuard` non implementa direttamente UMA o la verifica PoP. Dipende dalle interfacce, così l'oracolo e il verificatore possono essere sostituiti con implementazioni reali senza cambiare il flusso principale.

## 4. Interfacce

### `IOracleGuard.sol`

Definisce l'API e i tipi del sistema di risoluzione.

#### Enum `Outcome`

- `UNRESOLVED`: nessun esito definitivo;
- `YES`: esito positivo;
- `NO`: esito negativo;
- `INVALID`: esito non valido o mercato annullato.

Nel codice attuale `OracleGuard` usa operativamente `YES` e `NO`; `UNRESOLVED` e `INVALID` sono previsti dall'interfaccia ma non vengono assegnati durante la risoluzione.

#### Enum `ResolutionMode`

- `UMA_ONLY`: il costo di corruzione è almeno pari al profitto dalla corruzione;
- `DUAL_SBT_GUARD`: il profitto dalla corruzione supera il costo stimato e serve una giuria SBT.

#### Eventi

L'interfaccia espone gli eventi che rendono osservabile il protocollo:

- `RiskEvaluated`: valutazione di `pfc`, `coc` e modalità scelta;
- `VotingSessionStarted`: apertura della finestra di voto;
- `VoteSubmitted`: voto di un validatore;
- `SbtSessionConcluded`: chiusura dello scrutinio e percentuale `YES`;
- `FastPathResolved`: risoluzione diretta tramite UMA;
- `DualPathResolved`: risoluzione ibrida, con indicazione dell'eventuale intervento del circuit breaker.

### `IValidatorSBT.sol`

Eredita da `IERC5192` e definisce le operazioni del registro dei validatori:

- `isQualifiedValidator`: verifica che un account abbia un SBT attivo;
- `validatorTokenId`: restituisce il token associato all'account;
- `claimWithPoP`: crea un'identità dopo una prova PoP valida;
- `revokeSBT`: revoca un validatore;
- `locked`: verifica che il token sia non trasferibile.

### `IERC5192.sol`

È l'interfaccia minima dello standard EIP-5192 per Soulbound Token. Contiene gli eventi `Locked` e `Unlocked` e la funzione `locked(tokenId)`.

Nel progetto ogni SBT nasce bloccato e non esiste una funzione per sbloccarlo o trasferirlo.

### `IPoPVerifier.sol`

Astrazione del verificatore di Proof-of-Personhood. Riceve:

- l'indirizzo del richiedente (`signal`);
- un `nullifierHash`;
- la prova ZK in formato `bytes`.

Restituisce `true` se la prova è valida.

### `IUMAMockOracle.sol`

Espone `getResolvedOutcome(questionId)`, che restituisce:

- un booleano che indica se il mercato è stato risolto;
- un valore `int256` codificato come `1e18` per `YES` e `0` per `NO`.

## 5. Contratto `OracleGuard`

File: `Contratti/OracleGuard/OracleGuard.sol`

È il coordinatore del protocollo. Riceve nel costruttore gli indirizzi del contratto SBT e dell'oracolo UMA.

### Costanti

```solidity
UMA_TRUTH_YES = 1e18
UMA_TRUTH_NO = 0
SBT_OVERRIDE_MAJORITY_THRESHOLD = 70
```

La soglia del 70% è calcolata sui voti effettivamente espressi, non sul numero totale di SBT esistenti.

### Stato principale

#### `MarketRiskData`

Per ogni `questionId` salva:

- `pfc`;
- `coc`;
- `mode`;
- `isEvaluated`.

È memorizzato in `marketRisks`.

#### `DisputeSession`

Per ogni mercato in modalità duale salva:

- `questionId`;
- `deadline`;
- `votesYes` e `votesNo`;
- `isSbtResolved`;
- `sbtYesPercent`;
- `hasVoted`, mapping che impedisce il doppio voto.

È memorizzato in `sessions`.

#### Stato finale

- `isMarketResolved[questionId]`: indica che il mercato è stato chiuso;
- `finalOutcomes[questionId]`: contiene l'esito finale.

### Controllo amministrativo

`evaluateMarketRisk` e `startDisputeSession` sono protette da `onlyAdmin`. L'amministratore è l'indirizzo che effettua il deploy e non può essere cambiato dal contratto.

Il voto e la risoluzione non richiedono il ruolo admin, ma hanno i propri controlli di qualifica, stato e temporizzazione.

### `evaluateMarketRisk`

Registra `pfc` e `coc` e sceglie la modalità:

```solidity
if (pfc > coc) {
    mode = DUAL_SBT_GUARD;
} else {
    mode = UMA_ONLY;
}
```

La funzione può essere richiamata nuovamente per lo stesso mercato e sovrascrive la valutazione precedente.

### `startDisputeSession`

Apre una sessione solo quando:

1. il mercato è stato valutato;
2. la modalità è `DUAL_SBT_GUARD`;
3. non esiste già una sessione;
4. `duration` è maggiore di zero.

La scadenza è `block.timestamp + duration`.

### `voteSBT`

Un account può votare se:

1. la sessione esiste e non è scaduta;
2. `isQualifiedValidator(msg.sender)` restituisce `true`;
3. non ha già votato;
4. la scelta è `YES` o `NO`.

Ogni indirizzo conta una volta. Il contratto non pesa il voto in base alla quantità di token o al capitale posseduto.

### `closeSbtVoting`

Può essere eseguita solo dopo la deadline e una sola volta.

La percentuale viene calcolata come:

```text
sbtYesPercent = votesYes * 100 / (votesYes + votesNo)
```

Se non è stato espresso alcun voto, il risultato neutro è `50%`.

### `resolve`

È la funzione di settlement finale.

1. Rifiuta mercati già risolti.
2. Richiede che il rischio sia stato valutato.
3. Interroga UMA.
4. Rifiuta un responso UMA ancora pendente.
5. Traduce `1e18` in `YES`; ogni altro valore viene trattato come `NO`.

In modalità `UMA_ONLY`, salva e restituisce direttamente il responso UMA ed emette `FastPathResolved`.

In modalità `DUAL_SBT_GUARD`, richiede una votazione SBT chiusa:

- se UMA dice `NO` e la giuria raggiunge almeno il 70% `YES`, il risultato diventa `YES`;
- se UMA dice `YES` e la giuria raggiunge almeno il 70% `NO`, il risultato diventa `NO`;
- negli altri casi prevale UMA.

Il risultato viene salvato in `finalOutcomes` e l'evento `DualPathResolved` indica se il circuit breaker è intervenuto.

## 6. Contratto `ValidatorSBT`

File: `Contratti/Token/ValidatorSBT.sol`

`ValidatorSBT` rappresenta l'identità dei validatori. Il token è soulbound: non è pensato per essere trasferito tra indirizzi.

### Stato

- `_owners[tokenId]`: proprietario del token;
- `_balances[account]`: numero di token associati all'account;
- `validatorTokenId[account]`: token dell'account;
- `usedNullifiers[nullifierHash]`: nullifier già utilizzati;
- `isRevoked[account]`: stato di revoca;
- `_nextTokenId`: prossimo ID, inizializzato a `1`;
- `popVerifier`: verificatore PoP corrente;
- `admin`: amministratore.

### `claimWithPoP`

Il claim verifica:

1. l'account non possiede già un'identità;
2. il nullifier non è già stato usato;
3. `popVerifier.verifyProof` restituisce `true`.

Dopo la verifica:

- consuma il nullifier;
- assegna un nuovo `tokenId`;
- salva proprietario e bilancio;
- emette `Locked`;
- emette `IdentityMinted`.

L'account ottiene quindi un solo SBT e può essere riconosciuto come validatore.

### `isQualifiedValidator`

Restituisce `true` solo se:

```text
_balance[account] > 0 && !isRevoked[account]
```

È la funzione usata da `OracleGuard` per autorizzare il voto.

### `revokeSBT`

È disponibile solo all'amministratore. Non brucia il token e non rimuove il proprietario: imposta `isRevoked[validator] = true`, rendendo però l'account non qualificato ai fini del voto.

### `locked`, `ownerOf`, `balanceOf`

- `locked` restituisce sempre `true` per un token esistente;
- `ownerOf` restituisce il proprietario e va in revert se il token non esiste;
- `balanceOf` restituisce il numero di token associati a un account.

### `setVerifier`

Permette all'amministratore di sostituire il contratto verificatore PoP con un indirizzo non nullo.

## 7. Mock e dipendenze

### `UMAMockOracle.sol`

Mock dell'oracolo UMA. Memorizza per ogni domanda:

- `resolved[questionId]`;
- `outcomes[questionId]`.

`reportOutcome` e `reportManipulatedOutcome` producono lo stesso effetto tecnico: registrano un risultato definitivo ed emettono `OutcomeReported`. La distinzione nel nome serve ai test per rappresentare un responso corretto o manipolato.

Il mock non impone autenticazione, liveness period, bond, dispute o quorum UMA. È quindi un sostituto didattico dell'oracolo reale.

### `MockPoPVerifier.sol`

Contiene il flag `shouldPass`. `verifyProof` restituisce semplicemente il valore del flag, mentre `setShouldPass` permette ai test di simulare prove valide e non valide.

Non esegue una verifica ZK reale e non dimostra l'unicità biologica di un utente.

### `lib/forge-std`

È il submodule ufficiale `forge-std` di Foundry. I test utilizzano soprattutto:

- `Test.sol` per la base dei test;
- cheatcode come `vm.prank`, `vm.startPrank`, `vm.warp`, `vm.expectRevert` e `vm.expectEmit`;
- asserzioni come `assertEq`, `assertTrue` e `assertFalse`.

## 8. Flussi operativi

### Flusso ordinario `UMA_ONLY`

```text
admin
  -> deploy di PoP verifier, ValidatorSBT, UMAMockOracle e OracleGuard
admin
  -> evaluateMarketRisk(questionId, pfc, coc)
     con pfc <= coc
UMA
  -> reportOutcome(questionId, 1e18 oppure 0)
utente/protocollo
  -> resolve(questionId)
OracleGuard
  -> salva il risultato UMA
  -> emette FastPathResolved
```

### Flusso protetto `DUAL_SBT_GUARD`

```text
admin
  -> evaluateMarketRisk(questionId, pfc, coc)
     con pfc > coc
admin
  -> startDisputeSession(questionId, duration)
validator qualificato
  -> voteSBT(questionId, YES oppure NO)
admin o altro account
  -> closeSbtVoting dopo la deadline
UMA
  -> restituisce il proprio responso
utente/protocollo
  -> resolve(questionId)
OracleGuard
  -> confronta UMA con la supermaggioranza SBT
  -> salva l'esito finale
  -> emette DualPathResolved
```

### Scenari limite gestiti

Il codice rifiuta:

- contratti dipendenti all'indirizzo zero;
- rischio non ancora valutato;
- sessione avviata in modalità `UMA_ONLY`;
- durata nulla;
- voto fuori dalla finestra temporale;
- account senza SBT attivo;
- doppio voto dello stesso account;
- scelta diversa da `YES` o `NO`;
- chiusura prima della deadline;
- chiusura ripetuta;
- risoluzione prima della chiusura SBT;
- responso UMA non ancora disponibile;
- risoluzione dello stesso mercato più di una volta.

## 9. Test Foundry

La suite contiene 12 test divisi in tre file.

### `Test/OracleGuardStandard.t.sol`

La fixture crea i quattro contratti principali e accredita un validatore.

Verifica:

- la classificazione `UMA_ONLY` quando `pfc <= coc`;
- il salvataggio di `pfc`, `coc`, modalità e flag di valutazione;
- l'evento `RiskEvaluated`;
- la risoluzione diretta di un responso UMA `YES`;
- l'evento `FastPathResolved`;
- la memorizzazione dell'esito finale.

### `Test/OracleGuardAttack.t.sol`

Crea nove validatori onesti, un validatore malevolo e un indirizzo Sybil senza SBT.

Verifica:

- un attacco in modalità duale con 9 voti `YES` e 1 voto `NO`;
- il calcolo del 90% `YES`;
- il ribaltamento di un responso UMA `NO`;
- l'attivazione del circuit breaker;
- il caso 6 `YES` contro 4 `NO`, che non raggiunge il 70% e quindi non ribalta UMA;
- il rifiuto del doppio voto;
- il rifiuto di un account privo di SBT;
- le protezioni temporali della sessione.

### `Test/ValidatorSBT.t.sol`

Verifica:

- mint con PoP valida;
- evento `Locked`;
- evento `IdentityMinted`;
- proprietà, bilancio e qualifica del validatore;
- rifiuto del riutilizzo di un nullifier;
- rifiuto di un secondo claim dello stesso account;
- rifiuto di una prova non valida;
- revoca amministrativa e perdita della qualifica.

Per eseguire la suite dalla root, in un ambiente Foundry configurato, il comando tipico è:

```bash
forge test
```

Per maggiore dettaglio:

```bash
forge test -vv
```

## 10. Analisi empirica storica

File: `Simulazione/Analisi empirica storica/historical_empirical_analysis.py`

Lo script confronta dati storici di Polymarket e UMA.

### Input

- `Simulazione/dati_simulazione/polymarket_election_2024.csv`: open interest del mercato;
- `Simulazione/dati_simulazione/uma_token_metrics.json`: supply circolante, partecipazione tipica, prezzo e date.

### Calcoli

Per ogni data presente in entrambi i dataset:

```text
active_voting_tokens = circulating_supply * typical_quorum_participation_pct
CoC = active_voting_tokens * 0.51 * price_usd
PfC = market_open_interest_usd
ratio = PfC / CoC
```

La modalità teorica è `DUAL_SBT_GUARD` se `PfC > CoC`, altrimenti `UMA_ONLY`.

Lo script stampa una tabella con data, `PfC`, `CoC`, rapporto e modalità. Calcola anche minimi, massimi e media e prepara le liste necessarie per grafici temporali.

### Nota operativa

Nel codice il percorso usato da `load_data()` è scritto in minuscolo come `simulazione/dati_simulazione/...`, mentre la directory del repository è `Simulazione/dati_simulazione/...`. Su macOS e Linux questo può causare `FileNotFoundError`, perché i percorsi possono essere case-sensitive. Prima dell'esecuzione il percorso va quindi allineato alla directory reale.

## 11. Simulazione dinamica ad agenti

File: `Simulazione/Simulazione dinamica agenti/agent_market_simulation.py`

Questa simulazione usa casualità deterministica iniziale con:

```python
np.random.seed(42)
random.seed(42)
```

### Mercato CLOB

`RealisticPolymarketCLOB` modella un mercato semplificato con:

- prezzi medi (`mid_prices`);
- spread bid/ask;
- profondità dei bid e degli ask;
- volume cumulato;
- open interest.

`execute_market_order` aggiorna volume, open interest, slippage, prezzi e profondità. Gli ordini `YES` spingono il prezzo verso l'alto, gli ordini `NO` verso il basso. I prezzi vengono poi normalizzati affinché la somma sia pari a `1`.

### Agenti

La dashboard simula tre categorie di attività:

- trader retail, che generano ordini casuali;
- market maker, che aggiungono liquidità al book;
- una whale, che acquista progressivamente `YES` su un candidato e riduce il proprio budget.

La whale dispone di un budget iniziale di 12 milioni di dollari. Il mercato parte con un open interest di 45 milioni di dollari e usa un `CoC_UMA` di 25.092 milioni di dollari.

### Modalità di sicurezza

Ad ogni passo viene verificato:

```text
open_interest > COC_UMA -> DUAL_SBT_GUARD
open_interest <= COC_UMA -> UMA_ONLY
```

La dashboard mostra prezzi, profondità, transazioni, wallet, volume, `PfC`, `CoC` e rapporto di vulnerabilità.

### Giuria endogena

`run_endogenous_jury_resolution` seleziona casualmente, tra i partecipanti:

- chi possiede un SBT, con probabilità del 65%;
- chi partecipa al voto, con probabilità del 75%;
- chi vota correttamente, con probabilità del 93%.

Calcola quindi la percentuale `YES` e attiva il circuit breaker quando raggiunge almeno il 70%.

### Interfaccia

`curses_dashboard` fornisce una dashboard terminale aggiornata durante la simulazione. Il tasto `q` interrompe l'esecuzione. `main` raccoglie la durata, esegue la dashboard e stampa il report finale con:

- transazioni;
- capitale finale;
- rapporto `PfC/CoC`;
- prezzi finali;
- investimento della whale;
- profitto potenziale senza protezione;
- statistiche della giuria;
- verdetto teorico con e senza OracleGuard.
