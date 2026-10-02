// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC5192.sol";

/// @title IValidatorSBT - Interfaccia per il Registro dei Validatori Soulbound
/// @notice Definisce le funzioni di verifica e di accreditamento dei validatori tramite Proof-of-Personhood
interface IValidatorSBT is IERC5192 {
    /// @notice Verifica se un dato indirizzo è un validatore qualificato e attivo
    /// @param account L'indirizzo da verificare
    /// @return bool True se possiede un SBT valido e non revocato, False altrimenti
    function isQualifiedValidator(address account) external view returns (bool);

    /// @notice Restituisce il tokenId assegnato a un determinato validatore
    /// @param account L'indirizzo del validatore
    /// @return uint256 L'ID del token associato (o 0 se non presente)
    function validatorTokenId(address account) external view returns (uint256);

    /// @notice Permette a un utente umano di riscattare il proprio SBT presentando una prova PoP valida
    /// @param nullifierHash L'hash del nullifier per prevenire double-claiming
    /// @param proof La prova crittografica ZK generata off-chain
    /// @return uint256 L'ID del token appena coniato
    function claimWithPoP(bytes32 nullifierHash, bytes calldata proof) external returns (uint256);

    /// @notice Revoca l'SBT di un validatore compromesso
    /// @param tokenId L'identificativo dell'SBT da revocare
    function revokeSBT(uint256 tokenId) external;
}