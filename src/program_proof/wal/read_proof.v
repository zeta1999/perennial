From RecordUpdate Require Import RecordSet.

From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof Require Import wal.invariant.

Section goose_lang.
Context `{!heapG Σ}.
Context `{!walG Σ}.

Implicit Types (v:val) (z:Z).
Implicit Types (γ: wal_names).
Implicit Types (s: log_state.t) (memLog: slidingM.t) (txns: list (u64 * list update.t)).
Implicit Types (pos: u64) (txn_id: nat).

Context (P: log_state.t -> iProp Σ).
Let N := walN.
Let innerN := walN .@ "wal".
Let circN := walN .@ "circ".

Opaque struct.t.

Lemma fmap_app_split3_inv {A B} (f: A -> B) (l: list A) (l1 l2: list B) (x: B) :
  f <$> l = l1 ++ [x] ++ l2 →
  ∃ l1' x' l2',
    l1 = f <$> l1' ∧
    l2 = f <$> l2' ∧
    x = f x' ∧
    l = l1' ++ [x'] ++ l2'.
Proof.
  intros H.
  apply fmap_app_inv in H as (l1' & l2' & (?&?&?)); subst.
  symmetry in H0.
  apply fmap_app_inv in H0 as (l1'' & l2'' & (?&?&?)); subst.
  symmetry in H.
  destruct l1''; try solve [ inversion H ].
  destruct l1''; try solve [ inversion H ].
  inversion H; subst.
  eexists _, _, _; eauto.
Qed.

Theorem find_highest_index_apply_upds log u i :
  find_highest_index (update.addr <$> log) u.(update.addr) = Some i →
  log !! i = Some u →
  apply_upds log ∅ !! (int.val u.(update.addr)) = Some u.(update.b).
Proof.
  intros.
  apply find_highest_index_Some_split in H as (poss1 & poss2 & (Heq & Hnotin & <-)).
  apply fmap_app_split3_inv in Heq as (log1 & u' & log2 & (?&?&?&?)); subst.
  assert (u = u'); [ | subst ].
  { autorewrite with len in H0.
    rewrite -> lookup_app_r in H0 by lia.
    rewrite minus_diag /= in H0.
    congruence. }
  clear H0 H2.
  destruct u' as [a b]; simpl in *.
  rewrite apply_upds_app /=.
  rewrite apply_upds_insert_commute; auto.
  rewrite lookup_insert //.
Qed.

Lemma apply_upds_not_in_general (a: u64) log d :
    forall (Hnotin: a ∉ update.addr <$> log),
    d !! int.val a = None →
    apply_upds log d !! int.val a = None.
Proof.
  revert d.
  induction log; simpl; intros; auto.
  destruct a0 as [a' b]; simpl in *.
  fold (update.addr <$> log) in Hnotin.
  apply not_elem_of_cons in Hnotin as [Hneq Hnotin].
  rewrite IHlog; eauto.
  rewrite lookup_insert_ne //.
  apply not_inj; auto.
Qed.

Lemma apply_upds_not_in (a: u64) log :
    a ∉ update.addr <$> log →
    apply_upds log ∅ !! int.val a = None.
Proof.
  intros Hnotin.
  apply apply_upds_not_in_general; auto.
Qed.

Theorem wp_WalogState__readMem γ (st: loc) σ (a: u64) diskEnd_txn_id :
  {{{ wal_linv_fields st σ ∗
      memLog_linv γ σ.(memLog) σ.(diskEnd) diskEnd_txn_id }}}
    WalogState__readMem #st #a
  {{{ b_s (ok:bool), RET (slice_val b_s, #ok);
      (if ok then ∃ b, is_block b_s 1 b ∗
                       ⌜apply_upds σ.(memLog).(slidingM.log) ∅ !! int.val a = Some b⌝
      else ⌜b_s = Slice.nil ∧ apply_upds σ.(memLog).(slidingM.log) ∅ !! int.val a = None⌝) ∗
      "Hfields" ∷ wal_linv_fields st σ ∗
      "HmemLog_linv" ∷ memLog_linv γ σ.(memLog) σ.(diskEnd) diskEnd_txn_id
  }}}.
Proof.
  iIntros (Φ) "(Hfields&HmemLog_inv) HΦ".
  iNamed "Hfields".
  iNamed "Hfield_ptsto".
  wp_call.
  wp_loadField.
  wp_apply (wp_sliding__posForAddr with "His_memLog").
  iIntros (pos ok) "(His_memLog&%Hlookup)".
  wp_pures.
  wp_if_destruct; subst.
  - destruct Hlookup as [Hbound Hfind].
    wp_apply util_proof.wp_DPrintf.
    wp_loadField.
    (* need to identify the update that we're looking up *)
    pose proof (find_highest_index_ok' _ _ _ Hfind) as [Hlookup Hhighest].
    rewrite list_lookup_fmap in Hlookup.
    apply fmap_Some_1 in Hlookup as [u [ Hlookup ->]].

    wp_apply (wp_sliding__get with "His_memLog"); eauto.
    { lia. }
    iIntros (uv q) "(Hu & His_memLog)".
    iDestruct "Hu" as "(%Hu&Hb)".
    wp_apply (wp_copyUpdateBlock with "Hb").
    iIntros (s') "[Hb Hb']".
    iSpecialize ("His_memLog" with "Hb").
    wp_pures.
    iApply "HΦ".
    iFrame "HmemLog_inv".
    iSplitL "Hb'".
    { iExists _; iFrame.
      iPureIntro.
      eapply find_highest_index_apply_upds; eauto. }
    iExists _; by iFrame.
  - wp_pures.
    change (slice.nil) with (slice_val Slice.nil).
    iApply "HΦ".
    iFrame "HmemLog_inv".
    iSplit.
    { iPureIntro.
      split; auto.
      apply find_highest_index_none_not_in in Hlookup.
      apply apply_upds_not_in; auto. }
    iExists _; by iFrame.
Qed.

Theorem simulate_read_cache_hit {l γ Q σ memLog diskEnd diskEnd_txn_id b a} :
  apply_upds memLog.(slidingM.log) ∅ !! int.val a = Some b ->
  (is_wal_inner l γ σ ∗ P σ) -∗
  memLog_linv γ memLog diskEnd diskEnd_txn_id -∗
  (∀ (σ σ' : log_state.t) mb,
      ⌜wal_wf σ⌝
        -∗ ⌜relation.denote (log_read_cache a) σ σ' mb⌝ -∗ P σ ={⊤ ∖ ↑N}=∗ P σ' ∗ Q mb) -∗
  |={⊤ ∖ ↑N}=> (is_wal_inner l γ σ ∗ P σ) ∗
              "HQ" ∷ Q (Some b) ∗
              "HmemLog_linv" ∷ memLog_linv γ memLog diskEnd diskEnd_txn_id.
Proof.
Admitted.

(* TODO: this is hard, should prove it at some point *)
Theorem simulate_read_cache_miss {l γ Q σ memLog diskEnd diskEnd_txn_id a} :
  apply_upds memLog.(slidingM.log) ∅ !! int.val a = None ->
  (is_wal_inner l γ σ ∗ P σ) -∗
  memLog_linv γ memLog diskEnd diskEnd_txn_id -∗
  (∀ (σ σ' : log_state.t) mb,
      ⌜wal_wf σ⌝
        -∗ ⌜relation.denote (log_read_cache a) σ σ' mb⌝ -∗ P σ ={⊤ ∖ ↑N}=∗ P σ' ∗ Q mb) -∗
  |={⊤ ∖ ↑N}=> (∃ σ', is_wal_inner l γ σ' ∗ P σ') ∗
              "HQ" ∷ Q None ∗
              "HmemLog_linv" ∷ memLog_linv γ memLog diskEnd diskEnd_txn_id.
Proof.
Admitted.

Theorem wp_Walog__ReadMem (Q: option Block -> iProp Σ) l γ a :
  {{{ is_wal P l γ ∗
       (∀ σₛ σₛ' mb,
         ⌜wal_wf σₛ⌝ -∗
         ⌜relation.denote (log_read_cache a) σₛ σₛ' mb⌝ -∗
         (P σₛ ={⊤ ∖ ↑N}=∗ P σₛ' ∗ Q mb))
   }}}
    Walog__ReadMem #l #a
  {{{ (ok:bool) bl, RET (slice_val bl, #ok); if ok
                                             then ∃ b, is_block bl 1 b ∗ Q (Some b)
                                             else Q None}}}.
Proof.
  iIntros (Φ) "[#Hwal Hfupd] HΦ".
  destruct_is_wal.
  wp_loadField.
  wp_apply (acquire_spec with "lk"). iIntros "(Hlocked&Hlkinv)".
  wp_loadField.
  iNamed "Hlkinv".
  wp_apply (wp_WalogState__readMem with "[$Hfields $HmemLog_linv]").
  iIntros (b_s ok) "(Hb&?&?)"; iNamed.
  (* really meant to do wp_pure until wp_bind Skip succeeds *)
  do 8 wp_pure _; wp_bind Skip.
  iDestruct "Hwal" as "[Hwal Hcirc]".
  iInv "Hwal" as (σs) "[Hinner HP]".
  wp_pures.
  destruct ok.
  - iDestruct "Hb" as (b) "[Hb %HmemLog_lookup]".
    iMod (fupd_intro_mask' _ (⊤ ∖ ↑N)) as "HinnerN"; first by solve_ndisj.
    iMod (simulate_read_cache_hit HmemLog_lookup with "[$Hinner $HP] HmemLog_linv Hfupd")
      as "([Hinner HP]&?&?)"; iNamed.
    iMod "HinnerN" as "_".
    iModIntro.
    iSplitL "Hinner HP".
    { iNext.
      iExists _; iFrame. }
    wp_loadField.
    wp_apply (release_spec with "[$lk $Hlocked HmemLog_linv Hfields HdiskEnd_circ Hstart_circ]").
    { iExists _; iFrame. }
    wp_pures.
    iApply "HΦ".
    iExists _; iFrame.
  - iDestruct "Hb" as "[-> %HmemLog_lookup]".
    iMod (fupd_intro_mask' _ (⊤ ∖ ↑N)) as "HinnerN"; first by solve_ndisj.
    iMod (simulate_read_cache_miss HmemLog_lookup with "[$Hinner $HP] HmemLog_linv Hfupd")
      as "(Hinv&?&?)"; iNamed.
    iMod "HinnerN" as "_".
    iModIntro.
    iFrame "Hinv".
    wp_loadField.
    wp_apply (release_spec with "[$lk $Hlocked HmemLog_linv Hfields HdiskEnd_circ Hstart_circ]").
    { iExists _; iFrame. }
    wp_pures.
    iApply "HΦ".
    iFrame.
Qed.

End goose_lang.
