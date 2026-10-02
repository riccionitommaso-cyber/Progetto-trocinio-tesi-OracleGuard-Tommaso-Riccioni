// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IUMAMockOracle - Interfaccia dell'Oracolo Ottimista UMA per Mercati Binari
/// @notice Definisce la funzione di lettura del verdetto dell'oracolo conforme allo standard UMA DVM / Optimistic Oracle V3
/// Utilizza la convenzione a virgola fissa con 18 decimali: 1e18 = YES (Verità asserita), 0 = NO (Falsità asserita).
interface IUMAMockOracle {
    /// @notice Restituisce lo stato di risoluzione e il valore di verità attestato dall'oracolo UMA
    /// @param questionId Identificativo univoco del mercato o dell'asserzione contesa
    /// @return isResolved True se l'oracolo ha emesso un responso definitivo (scadenza liveness o voto DVM), False se ancora pendente
    /// @return outcomeValue Il valore scalare deliberato (1e18 per YES, 0 per NO)
    function getResolvedOutcome(bytes32 questionId) external view returns (bool isResolved, int256 outcomeValue);
}