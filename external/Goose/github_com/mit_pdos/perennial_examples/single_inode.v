(* autogenerated from github.com/mit-pdos/perennial-examples/single_inode *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

From Goose Require github_com.mit_pdos.perennial_examples.alloc.
From Goose Require github_com.mit_pdos.perennial_examples.inode.

(* Example client of inode that has a single inode and doesn't share the
   allocator with anything else. *)

Module SingleInode.
  Definition S := struct.decl [
    "i" :: struct.ptrT inode.Inode.S;
    "alloc" :: struct.ptrT alloc.Allocator.S
  ].
End SingleInode.

(* Restore the SingleInode from disk

   sz should be the size of the disk to use *)
Definition Open: val :=
  rec: "Open" "d" "sz" :=
    let: "i" := inode.Open "d" #0 in
    let: "used" := NewMap (struct.t alloc.unit.S) in
    alloc.SetAdd "used" (inode.Inode__UsedBlocks "i");;
    let: "allocator" := alloc.New #1 ("sz" - #1) "used" in
    struct.new SingleInode.S [
      "i" ::= "i";
      "alloc" ::= "allocator"
    ].

Definition SingleInode__Read: val :=
  rec: "SingleInode__Read" "i" "off" :=
    inode.Inode__Read (struct.loadF SingleInode.S "i" "i") "off".

Definition SingleInode__Append: val :=
  rec: "SingleInode__Append" "i" "b" :=
    inode.Inode__Append (struct.loadF SingleInode.S "i" "i") "b" (struct.loadF SingleInode.S "alloc" "i").
