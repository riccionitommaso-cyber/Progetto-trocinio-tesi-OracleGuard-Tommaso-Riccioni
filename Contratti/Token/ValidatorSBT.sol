// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IValidatorSBT} from "../Interfacce/IValidatorSBT.sol";
import {IPoPVerifier} from "../Interfacce/IPoPVerifier.sol";

contract ValidatorSBT is IValidatorSBT {
    string public name = "OracleGuard Validator SBT";
    string public symbol = "OG-SBT";
    bool private constant IS_LOCKED = true;

    event IdentityMinted(address indexed validator, uint256 indexed tokenId, bytes32 indexed nullifierHash);
    event IdentityRevoked(address indexed validator, uint256 indexed tokenId);

    address public admin;
    IPoPVerifier public popVerifier;
    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public override validatorTokenId;
    mapping(bytes32 => bool) public usedNullifiers;
    mapping(address => bool) public isRevoked;

    modifier onlyAdmin() {
        require(msg.sender == admin, "ValidatorSBT: Solo admin");
        _;
    }

    constructor(address _verifier) {
        require(_verifier != address(0), "ValidatorSBT: Verifier non valido");
        admin = msg.sender;
        popVerifier = IPoPVerifier(_verifier);
    }

    function claimWithPoP(bytes32 nullifierHash, bytes calldata proof) external override returns (uint256) {
        require(_balances[msg.sender] == 0, "ValidatorSBT: Hai gia un'identita registrata");
        require(!usedNullifiers[nullifierHash], "ValidatorSBT: Nullifier gia utilizzato");
        require(popVerifier.verifyProof(msg.sender, nullifierHash, proof), "ValidatorSBT: Prova ZK PoP non valida");

        usedNullifiers[nullifierHash] = true;
        uint256 tokenId = _nextTokenId++;

        _owners[tokenId] = msg.sender;
        _balances[msg.sender] = 1;
        validatorTokenId[msg.sender] = tokenId;

        emit Locked(tokenId);
        emit IdentityMinted(msg.sender, tokenId, nullifierHash);

        return tokenId;
    }

    function revokeSBT(uint256 tokenId) external override onlyAdmin {
        address validator = _owners[tokenId];
        require(validator != address(0), "ValidatorSBT: Token inesistente");
        require(!isRevoked[validator], "ValidatorSBT: Gia revocato");

        isRevoked[validator] = true;

        emit IdentityRevoked(validator, tokenId);
    }

    function isQualifiedValidator(address account) external view override returns (bool) {
        return _balances[account] > 0 && !isRevoked[account];
    }

    function locked(uint256 tokenId) external view override returns (bool) {
        require(_owners[tokenId] != address(0), "ValidatorSBT: Token inesistente");
        return IS_LOCKED;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ValidatorSBT: Token inesistente");
        return owner;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function setVerifier(address _newVerifier) external onlyAdmin {
        require(_newVerifier != address(0), "ValidatorSBT: Verifier nullo");
        popVerifier = IPoPVerifier(_newVerifier);
    }
}
