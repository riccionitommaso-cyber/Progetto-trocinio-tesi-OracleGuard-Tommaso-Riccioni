// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ValidatorSBT} from "../Contratti/Token/ValidatorSBT.sol";
import {IERC5192} from "../Contratti/Interfacce/IERC5192.sol";
import {IValidatorSBT} from "../Contratti/Interfacce/IValidatorSBT.sol";
import {MockPoPVerifier} from "../Contratti/Mock/MockPoPVerifier.sol";

contract ValidatorSBTTest is Test {
    ValidatorSBT public sbt;
    MockPoPVerifier public popVerifier;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);

    bytes32 public constant NULLIFIER_ALICE = keccak256("ALICE_WORLD_ID_NULLIFIER");
    bytes32 public constant NULLIFIER_BOB = keccak256("BOB_WORLD_ID_NULLIFIER");
    bytes public dummyProof = hex"deadbeef";

    event Locked(uint256 tokenId);
    event IdentityMinted(address indexed validator, uint256 indexed tokenId, bytes32 indexed nullifierHash);
    event IdentityRevoked(address indexed validator, uint256 indexed tokenId);

    function setUp() public {
        vm.startPrank(admin);
        popVerifier = new MockPoPVerifier();
        sbt = new ValidatorSBT(address(popVerifier));
        vm.stopPrank();
    }

    function test_MintSBTWithValidPoP() public {
        vm.expectEmit(false, false, false, true);
        emit Locked(1);

        vm.expectEmit(true, true, true, false);
        emit IdentityMinted(alice, 1, NULLIFIER_ALICE);

        vm.prank(alice);
        uint256 tokenId = sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);

        assertEq(tokenId, 1);
        assertEq(sbt.ownerOf(1), alice);
        assertEq(sbt.balanceOf(alice), 1);
        assertTrue(sbt.isQualifiedValidator(alice));
        assertTrue(sbt.locked(1));
    }

    function test_RevertWhenReusingNullifier() public {
        vm.prank(alice);
        sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);

        vm.prank(bob);
        vm.expectRevert("ValidatorSBT: Nullifier gia utilizzato");
        sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);
    }

    function test_RevertWhenAccountClaimsTwice() public {
        vm.startPrank(alice);
        sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);

        bytes32 anotherNullifier = keccak256("ANOTHER_NULLIFIER");
        vm.expectRevert("ValidatorSBT: Hai gia un'identita registrata");
        sbt.claimWithPoP(anotherNullifier, dummyProof);
        vm.stopPrank();
    }

    function test_RevertWhenProofIsInvalid() public {
        popVerifier.setShouldPass(false);

        vm.prank(alice);
        vm.expectRevert("ValidatorSBT: Prova ZK PoP non valida");
        sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);
    }

    function test_RevokeValidatorByAdmin() public {
        vm.prank(alice);
        uint256 tokenId = sbt.claimWithPoP(NULLIFIER_ALICE, dummyProof);
        assertTrue(sbt.isQualifiedValidator(alice));

        vm.expectEmit(true, false, false, true);
        emit IdentityRevoked(alice, tokenId);

        vm.prank(admin);
        sbt.revokeSBT(tokenId);

        assertFalse(sbt.isQualifiedValidator(alice));
        assertTrue(sbt.isRevoked(alice));
    }
}
