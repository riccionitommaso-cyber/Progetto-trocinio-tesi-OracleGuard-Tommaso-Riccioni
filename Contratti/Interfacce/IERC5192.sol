// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC5192 - Interfaccia Minima per Soulbound Token (ERC-5192)
/// @notice Definisce gli eventi e la funzione di controllo dello stato di blocco (intrasferibilità) dei token
/// @dev Conforme alla specifica EIP-5192.

interface IERC5192 {
    /// @notice Emesso quando lo stato di un token viene impostato su bloccato
    /// @dev Deve essere emesso all'atto del conio se il token nasce vincolato all'anima
    /// @param tokenId L'identificativo univoco del token
    event Locked(uint256 tokenId);

    /// @notice Emesso quando lo stato di un token viene impostato su sbloccato
    /// @dev Utilizzato qualora un protocollo consenta di rimuovere temporaneamente il vincolo di intrasferibilità
    /// @param tokenId L'identificativo univoco del token
    event Unlocked(uint256 tokenId);

    /// @notice Restituisce lo stato di blocco di un Soulbound Token
    /// @dev Secondo la specifica EIP-5192, se il token è associato all'indirizzo zero
    /// oppure è inesistente/revocato, la funzione DEVE sollevare un revert/eccezione
    /// @param tokenId L'identificativo del token da verificare
    /// @return bool True se il token è bloccato (intrasferibile), False altrimenti
    function locked(uint256 tokenId) external view returns (bool);
}