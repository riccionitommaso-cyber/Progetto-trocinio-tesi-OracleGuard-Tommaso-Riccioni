// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPoPVerifier - Interfaccia per il Verificatore ZK della Proof-of-Personhood
/// @notice Astrae l'algoritmo di verifica succinta a conoscenza zero (zk-SNARK) per la validazione dell'unicità biologica
interface IPoPVerifier {
    /// @notice Convalida una prova ZK attestante che il mittente è un individuo umano reale e unico
    /// @dev La funzione esegue una verifica in tempo costante O(1) sui pairing della curva ellittica
    /// @param signal L'indirizzo pubblico del richiedente (msg.sender), vincolato come input pubblico per prevenire front-running e attacchi di malleabilità
    /// @param nullifierHash L'impronta crittografica univoca derivata dall'identità biologica segreta (previene attacchi Sybil e double-claiming)
    /// @param proof La prova computazionale succinta zk-SNARK generata dal prover off-chain (es. Groth16 / Alt_bn128)
    /// @return bool True se la prova algebrica è formalmente valida ed è convinta dell'asserzione, False altrimenti
    function verifyProof(
        address signal,
        bytes32 nullifierHash,
        bytes calldata proof
    ) external view returns (bool);
}