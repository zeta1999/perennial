From iris.proofmode Require Import tactics.
From iris.algebra Require Import auth.
From iris.base_logic.lib Require Import proph_map.
From iris.program_logic Require Export weakestpre adequacy.
From Perennial.go_lang Require Import proofmode notation.
Set Default Proof Using "Type".

Class ffi_interp_adequacy `{!ffi_interp ffi} :=
  { ffi_preG: gFunctors -> Type;
    ffiΣ: gFunctors;
    (* modeled after subG_gen_heapPreG and gen_heap_init *)
    subG_ffiPreG : forall Σ, subG ffiΣ Σ -> ffi_preG Σ;
    ffi_init : forall Σ, ffi_preG Σ -> forall (σ:ffi_state),
(|==> ∃ (H0: ffiG Σ), ffi_ctx H0 σ)%I;
  }.

(* this is the magic that lets subG_ffiPreG solve for an ffi_preG using only
typeclass resolution, which is the one thing solve_inG tries. *)
Existing Class ffi_preG.
Hint Resolve subG_ffiPreG : typeclass_instances.

Class heapPreG `{ext: ext_op} `{ffi_interp_adequacy} Σ := HeapPreG {
  heap_preG_iris :> invPreG Σ;
  heap_preG_heap :> gen_heapPreG loc val Σ;
  heap_preG_proph :> proph_mapPreG proph_id (val * val) Σ;
  heap_preG_ffi : ffi_preG Σ;
}.

Hint Resolve heap_preG_ffi : typeclass_instances.

Definition heapΣ `{ext: ext_op} `{ffi_interp_adequacy} : gFunctors := #[invΣ; gen_heapΣ loc val; ffiΣ; proph_mapΣ proph_id (val * val)].
Instance subG_heapPreG `{ext: ext_op} `{ffi_interp_adequacy} {Σ} : subG heapΣ Σ → heapPreG Σ.
Proof. solve_inG. Qed.

Definition heap_adequacy `{ffi_sem: ext_semantics} `{!ffi_interp ffi} {Hffi_adequacy:ffi_interp_adequacy} Σ `{!heapPreG Σ} s e σ φ :
  (∀ `{!heapG Σ}, WP e @ s; ⊤ {{ v, ⌜φ v⌝ }}%I) →
  adequate s e σ (λ v _, φ v).
Proof.
  intros Hwp; eapply (wp_adequacy _ _); iIntros (??) "".
  iMod (gen_heap_init σ.(heap)) as (?) "Hh".
  iMod (proph_map_init κs σ.(used_proph_id)) as (?) "Hp".
  iMod (ffi_init _ _ σ.(world)) as (HffiG) "Hw".
  iModIntro. iExists
    (λ σ κs, (gen_heap_ctx σ.(heap) ∗ proph_map_ctx κs σ.(used_proph_id) ∗ ffi_ctx HffiG σ.(world))%I),
    (λ _, True%I).
  iFrame. iApply (Hwp (HeapG _ _ _ _ _)).
Qed.