From RecordUpdate Require Import RecordSet.
From iris.algebra Require Import auth.

From Perennial.program_logic Require Import ghost_var_old.
From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof Require Import wal.invariant.

Remove Hints fractional.into_sep_fractional : typeclass_instances.

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

Theorem wp_Walog__waitForSpace l γ σₛ :
  {{{ "#HmemLock" ∷ readonly (l ↦[Walog.S :: "memLock"] #σₛ.(memLock)) ∗
      "#HcondLogger" ∷ readonly (l ↦[Walog.S :: "condLogger"] #σₛ.(condLogger)) ∗
      "#HcondInstall" ∷ readonly (l ↦[Walog.S :: "condInstall"] #σₛ.(condInstall)) ∗
      "#His_cond1" ∷ is_cond σₛ.(condLogger) #σₛ.(memLock) ∗
      "#His_cond2" ∷ is_cond σₛ.(condInstall) #σₛ.(memLock) ∗
      "#?" ∷ readonly (l ↦[Walog.S :: "st"] #σₛ.(wal_st)) ∗
      "Hlkinv" ∷ wal_linv σₛ.(wal_st) γ ∗
      "Hlocked" ∷ locked #σₛ.(memLock) ∗
      "#His_lock" ∷ is_lock N #σₛ.(memLock) (wal_linv σₛ.(wal_st) γ)
  }}}
    Walog__waitForSpace #l
  {{{ σ, RET #();
      "Hlocked" ∷ locked #σₛ.(memLock)  ∗
      "Hfields" ∷ wal_linv_fields σₛ.(wal_st) σ ∗
      "HmemLog_linv" ∷ memLog_linv γ σ.(memLog) σ.(diskEnd) σ.(locked_diskEnd_txn_id) ∗
      "HdiskEnd_circ" ∷ diskEnd_linv γ σ.(diskEnd) σ.(locked_diskEnd_txn_id) ∗
      "Hstart_circ" ∷ diskStart_linv γ σ.(memLog).(slidingM.start) ∗
      "%Hhas_space" ∷ ⌜length σ.(memLog).(slidingM.log) ≤ LogSz⌝
  }}}.
Proof.
  iIntros (Φ) "Hpre HΦ".
  iNamed "Hpre".
  wp_call.
  iNamed "Hlkinv".
  wp_apply (wp_forBreak_cond
              (λ b, "Hlocked" ∷ locked #σₛ.(memLock) ∗
                    "*" ∷ ∃ σ, "Hfields" ∷ wal_linv_fields σₛ.(wal_st) σ ∗
                               "HmemLog_linv" ∷ memLog_linv γ σ.(memLog) σ.(diskEnd) σ.(locked_diskEnd_txn_id) ∗
                               "HdiskEnd_circ" ∷ diskEnd_linv γ σ.(diskEnd) σ.(locked_diskEnd_txn_id) ∗
                               "Hstart_circ" ∷ diskStart_linv γ σ.(memLog).(slidingM.start) ∗
                               "%Hbreak" ∷ ⌜b = false → (length σ.(memLog).(slidingM.log) ≤ LogSz)⌝
              )%I
              with "[] [-HΦ]").
  2: {
    iFrame.
    iExists _; iFrame "# ∗".
    iPureIntro. inversion 1.
  }
  { iIntros "!>" (Φ') "HI HΦ".
    iNamed "HI".
    iNamed "Hfields".
    iNamed "Hfield_ptsto".
    wp_loadField. wp_loadField.
    wp_apply (wp_log_len with "His_memLog"); iIntros "His_memLog".
    wp_pures.
    change (int.val (word.divu (word.sub 4096 8) 8)) with LogSz.
    wp_if_destruct.
    - wp_loadField.
      wp_apply (wp_condWait with "[-HΦ]"); [ iFrame "His_cond2 His_lock Hlocked" | ].
      { iExists _; iFrame "∗ #". iExists _; iFrame "% # ∗". }
      iIntros "(Hlocked&Hlkinv)".
      wp_pures.
      iApply "HΦ"; iFrame.
      iNamed "Hlkinv".
      iExists _; iFrame "# ∗".
      iPureIntro; inversion 1.
    - iApply "HΦ"; iFrame.
      iExists _; iFrame "∗ #".
      iSplit.
      { iExists _; by iFrame "# ∗". }
      iPureIntro.
      intros _.
      unfold locked_wf, slidingM.wf in Hlocked_wf.
      revert Heqb; word.
  }
  iIntros "HI"; iNamed "HI".
  specialize (Hbreak ltac:(auto)).
  iApply "HΦ".
  iFrameNamed. auto.
Qed.

Hint Unfold slidingM.logIndex slidingM.wf : word.

Lemma take_more {A} (n m: nat) (l: list A) :
  (n ≤ length l)%nat →
  take (n + m) l = take n l ++ take m (drop n l).
Proof.
  intros Hbound.
  rewrite -{1}(take_drop n l).
  rewrite -> take_app_ge by len.
  f_equal.
  f_equal.
  len.
Qed.

Lemma subslice_def {A} (n m: nat) (l: list A) :
  subslice n m l = drop n (take m l).
Proof. reflexivity. Qed.

Lemma subslice_comm {A} (n m: nat) (l: list A) :
  subslice n m l = take (m - n)%nat (drop n l).
Proof. rewrite /subslice skipn_firstn_comm //. Qed.

(** this is a way to re-fold subslice after commuting it, a useful inverse to
[subslice_comm] *)
Lemma subslice_take_drop {A} (n k: nat) (l: list A) :
  take k (drop n l) = subslice n (n + k) l.
Proof. rewrite /subslice firstn_skipn_comm //. Qed.

Lemma apply_upds_lookup_Some (txns: list update.t) (d: disk) (a: u64) (i: nat) :
  find_highest_index (update.addr <$> txns) a = Some i →
  ∃ u, txns !! i = Some u ∧ a = u.(update.addr) ∧
       apply_upds txns d !! (int.val a) = Some u.(update.b).
Proof.
Admitted.

Lemma apply_upds_lookup_None (txns: list update.t) (d: disk) (a: u64) :
  find_highest_index (update.addr <$> txns) a = None →
  apply_upds txns d !! (int.val a) = d !! (int.val a).
Proof.
Admitted.

Lemma apply_upds_lookup_overflow (txns: list update.t) (d: disk) z :
  2^64 ≤ z →
  apply_upds txns d !! z = d !! z.
Proof.
Admitted.

Lemma apply_upds_eq_nil (txns1 txns2: list update.t) :
  apply_upds txns1 ∅ = apply_upds txns2 ∅ →
  (forall d, apply_upds txns1 d = apply_upds txns2 d).
Proof.
Admitted.

Theorem subslice_split_r {A} n m m' (l: list A) :
  (n ≤ m ≤ m')%nat →
  (m ≤ length l)%nat →
  subslice n m' l = subslice n m l ++ subslice m m' l.
Proof.
  intros Hbound1 Hbound2.
  rewrite /subslice.
  replace m' with (m + (m' - m))%nat by lia.
  rewrite -> take_more by lia.
  rewrite -> drop_app_le by len.
  f_equal.
  rewrite -> drop_app_le by len.
  rewrite -> (drop_ge (take m l)) by len.
  auto.
Qed.

Lemma circ_matches_extend cs txns installed_txn_id diskEnd_txn_id new_txn nextDiskEnd_txn_id :
  (installed_txn_id ≤ diskEnd_txn_id ≤ nextDiskEnd_txn_id)%nat →
  (nextDiskEnd_txn_id < length txns)%nat →
  has_updates new_txn (subslice (S diskEnd_txn_id) (S nextDiskEnd_txn_id) txns) →
  circ_matches_txns cs txns installed_txn_id diskEnd_txn_id →
  circ_matches_txns (set upds (λ u, u ++ new_txn) cs) txns installed_txn_id nextDiskEnd_txn_id.
Proof.
  rewrite /circ_matches_txns /=.
  intros ? ? ? [? ?].
  split; [ | lia ].
  rewrite -> (subslice_split_r installed_txn_id (S diskEnd_txn_id) (S nextDiskEnd_txn_id)) by lia.
  apply has_updates_app; auto.
Qed.

Lemma is_installed_extend_durable γ d txns installed_txn_id diskEnd_txn_id diskEnd_txn_id' :
  (diskEnd_txn_id ≤ diskEnd_txn_id' < length txns)%nat →
  is_installed γ d txns installed_txn_id diskEnd_txn_id -∗
  is_installed γ d txns installed_txn_id diskEnd_txn_id'.
Proof.
  intros Hbound.
  iNamed 1.
  iExists _, _; iFrame.
  iPureIntro; lia.
Qed.

Lemma circ_diskEnd_app σ upds' :
  circΣ.diskEnd (set circΣ.upds (λ u, u ++ upds') σ) =
  circΣ.diskEnd σ + length upds'.
Proof.
  rewrite /circΣ.diskEnd /=.
  len.
Qed.

Lemma logIndex_diff memLog pos1 pos2 :
  int.val memLog.(slidingM.start) ≤ int.val pos1 →
  (slidingM.logIndex memLog pos2 - slidingM.logIndex memLog pos1)%nat =
  (int.nat pos2 - int.nat pos1)%nat.
Proof.
  rewrite /slidingM.logIndex; intros.
  lia.
Qed.

Theorem wp_Walog__logAppend l circ_l γ σₛ :
  {{{ "#HmemLock" ∷ readonly (l ↦[Walog.S :: "memLock"] #σₛ.(memLock)) ∗
      "#HcondLogger" ∷ readonly (l ↦[Walog.S :: "condLogger"] #σₛ.(condLogger)) ∗
      "#HcondInstall" ∷ readonly (l ↦[Walog.S :: "condInstall"] #σₛ.(condInstall)) ∗
      "#d" ∷ readonly (l ↦[Walog.S :: "d"] σₛ.(wal_d)) ∗
      "#circ" ∷ readonly (l ↦[Walog.S :: "circ"] #σₛ.(circ)) ∗
      "#His_cond1" ∷ is_cond σₛ.(condLogger) #σₛ.(memLock) ∗
      "#His_cond2" ∷ is_cond σₛ.(condInstall) #σₛ.(memLock) ∗
      "#?" ∷ readonly (l ↦[Walog.S :: "st"] #σₛ.(wal_st)) ∗
      "#His_lock" ∷ is_lock N #σₛ.(memLock) (wal_linv σₛ.(wal_st) γ) ∗
      "#Hwal" ∷ is_wal P l γ ∗
      "Hlkinv" ∷ wal_linv σₛ.(wal_st) γ ∗
      "Hlocked" ∷ locked #σₛ.(memLock) ∗
      "Hlogger" ∷ logger_inv γ circ_l
  }}}
    Walog__logAppend #l #circ_l
  {{{ (progress:bool), RET #progress;
      wal_linv σₛ.(wal_st) γ ∗
      locked #σₛ.(memLock) ∗
      logger_inv γ circ_l
  }}}.
Proof.
  iIntros (Φ) "Hpre HΦ"; iNamed "Hpre".
  iNamed "Hlogger".
  wp_call.
  wp_apply (wp_Walog__waitForSpace with "[$Hlkinv $Hlocked]").
  { iFrameNamed. iFrame "#". }
  iIntros (σ) "Hpost"; iNamed "Hpost".
  iNamed "Hfields".
  iNamed "Hfield_ptsto".
  wp_loadField. wp_loadField.
  wp_loadField. wp_loadField.
  wp_apply (wp_sliding__takeFrom with "His_memLog").
  { word. }
  iIntros (q s) "(His_memLog&Hbufs)".
  wp_pures.
  wp_apply wp_slice_len; wp_pures.
  wp_if_destruct; wp_pures.
  { iApply "HΦ".
    iFrame "Hlocked".
    iSplitR "HnotLogging Hown_diskEnd_txn_id Happender".
    - iExists _; iFrame.
      iExists _; iFrame "% ∗".
    - iFrame.
      iExists _; iFrame.
  }
  iNamed "HdiskEnd_circ".
  iMod (thread_own_get with "HdiskEnd_exactly HnotLogging") as
      "(HdiskEnd_exactly&Hlog_owned&HareLogging)";
    iNamed "Hlog_owned".
  iNamed "HmemLog_linv".
  iNamed "Hstart_circ".
  iDestruct "HmemStart_txn" as "#HmemStart_txn".
  iDestruct "HnextDiskEnd_txn" as "#HnextDiskEnd_txn".
  iMod (txn_pos_valid_locked with "Hwal HmemStart_txn Howntxns") as "(%HmemStart_txn&Howntxns)".
  iMod (txn_pos_valid_locked with "Hwal HnextDiskEnd_txn Howntxns") as "(%HnextDiskEnd_txn&Howntxns)".
  iMod (get_txns_are _ _ _ _ memStart_txn_id (S nextDiskEnd_txn_id) with "Howntxns Hwal") as "[Htxns_are Howntxns]"; eauto.
  { pose proof (is_txn_bound _ _ _ HnextDiskEnd_txn).
    lia. }
  (* use this to also strip a later, which the [wp_loadField] tactic does not do *)
  wp_apply (wp_loadField_ro with "HmemLock"); first by auto.
  iDestruct "Htxns_are" as "#Htxns_are".
  wp_apply (release_spec with "[-HΦ HareLogging HdiskEnd_is Happender Hbufs Hown_diskEnd_txn_id γdiskEnd_txn_id1 $His_lock $Hlocked]").
  { iExists _; iFrame "# ∗".
    iSplitR "Howntxns HmemEnd_txn".
    - iExists _; iFrame "% ∗".
    - iExists _, _, _; iFrame "# % ∗". }
  wp_loadField.
  iDestruct "Hwal" as "[Hwal Hcirc]".
  wp_apply (wp_circular__Append _ _
                              ("γdiskEnd_txn_id1" ∷ own γ.(diskEnd_txn_id_name) (●{1/2} Excl' nextDiskEnd_txn_id) ∗
                               "Hown_diskEnd_txn_id" ∷ own γ.(diskEnd_txn_id_name) (◯E nextDiskEnd_txn_id))
              with "[$Hbufs $HdiskEnd_is $Happender $Hcirc $Hstart_at_least Hown_diskEnd_txn_id γdiskEnd_txn_id1]").
  { rewrite subslice_length; word. }
  { rewrite subslice_length; word. }

  { (* Append fupd *)
    rewrite /circular_pred.
    iIntros (cs) "(%Hcirc_wf&%HdiskEnd_eq&Hcirc_ctx)".
    iIntros (cs' [] [Htrans Hcirc_wf']).
    simpl in Htrans; monad_inv.
    iInv "Hwal" as (σs) "[Hinner HP]".

    iDestruct "Hinner" as "(>%Hwf&Hmem&>?&>?&>?)"; iNamed.
    iNamed "Hdisk".
    iDestruct (ghost_var_agree with "Hcirc_ctx Howncs") as %Heq; subst cs0.
    iDestruct (txns_are_sound with "Htxns_ctx Htxns_are") as %Htxns_are.
    iDestruct (txn_pos_valid_general with "Htxns_ctx HmemStart_txn") as %HmemStart'.
    iDestruct (txn_pos_valid_general with "Htxns_ctx HnextDiskEnd_txn") as %HnextDiskEnd'.
    iMod (ghost_var_old.ghost_var_update _ with "Hcirc_ctx Howncs") as "[$ Howncs]".
    iNamed "Hdisk".
    iDestruct (ghost_var_frac_frac_agree with "γdiskEnd_txn_id1 γdiskEnd_txn_id2") as %?; subst.
    iCombine "γdiskEnd_txn_id1 γdiskEnd_txn_id2" as "γdiskEnd_txn_id".
    iDestruct (ghost_var_agree with "γdiskEnd_txn_id Hown_diskEnd_txn_id") as %?; subst.
    iMod (ghost_var_old.ghost_var_update _ with "γdiskEnd_txn_id Hown_diskEnd_txn_id") as
        "[[γdiskEnd_txn_id $] $]".
    iModIntro.
    iSplitL; [ | done ].
    iNext.
    iExists _; iFrame.
    iSplitR; auto.
    iExists _; iFrame.
    iNamed "circ.end".
    iExists installed_txn_id, nextDiskEnd_txn_id.
    iFrame "# ∗".
    iSplitL "Hinstalled".
    { iApply (is_installed_extend_durable with "Hinstalled").
      apply is_txn_bound in HnextDiskEnd'.
      word. }
    iSplitL "Hdurable".
    { iDestruct "Hdurable" as %Hmatches.
      iPureIntro.
      eapply circ_matches_extend; eauto; try lia.
      { split; try lia.
        destruct Hmatches. done. }
      { apply is_txn_bound in HnextDiskEnd'; auto. }
      pose proof (is_txn_bound _ _ _ HnextDiskEnd_txn).
      rewrite -> subslice_length in Htxns_are by lia.
      replace (memStart_txn_id + (S nextDiskEnd_txn_id - memStart_txn_id))%nat
              with (S nextDiskEnd_txn_id) in Htxns_are by lia.
      apply (subslice_suffix_eq _ _ _ (S σ.(locked_diskEnd_txn_id))) in Htxns_are.
      { rewrite Htxns_are. eauto. }
      lia.
    }
    rewrite /is_durable_txn.
    iExists σ.(memLog).(slidingM.mutable).
    iSplit.
    { iPureIntro.
      lia. }
    iSplit.
    { iPureIntro.
      simpl.
      rewrite circ_diskEnd_app.
      rewrite -> subslice_length by word.
      rewrite -> logIndex_diff by word.
      word. }
    { iPureIntro.
      admit. (* this is tricky - it's a txn pos, but that it's highest is due to
      some bounds *) }
  }
  rewrite -> subslice_length by word.
  iIntros "(Hpost&Hupds&Hcirc_appender&HdiskEnd_is)"; iNamed "Hpost".
  wp_loadField.
  wp_apply (acquire_spec with "His_lock").
  iIntros "(His_locked&Hlockinv)".
  iNamed "Hlockinv".
  iNamed "Hfields".
  iNamed "Hfield_ptsto".
  iRename "HdiskEnd_at_least" into "HdiskEnd_at_least_old".
  iNamed "HdiskEnd_circ".
  iMod (thread_own_put with "HdiskEnd_exactly HareLogging [HdiskEnd_is γdiskEnd_txn_id1]")
    as "[HdiskEnd_exactly HnotLogging]"; first by iAccu.
  wp_apply wp_slice_len.
  wp_loadField. wp_storeField.
  wp_loadField.
  wp_apply (wp_condBroadcast with "His_cond1").
  wp_loadField.
  wp_apply (wp_condBroadcast with "His_cond2").
  wp_pures.
  iApply "HΦ".
  iFrame "His_locked".
  iSplitR "Hcirc_appender HnotLogging Hown_diskEnd_txn_id".
  - (* TODO: come up with a simpler expression for new diskEnd *)
    iExists (set diskEnd (λ _, int.val σ.(diskEnd) + int.val s.(Slice.sz)) σ).
    simpl.
    iFrame.
    admit.
  - iFrame.
    iExists _; iFrame.
Admitted.

Theorem wp_Walog__logger l circ_l γ :
  {{{ "#Hwal" ∷ is_wal P l γ ∗
      "Hlogger" ∷ logger_inv γ circ_l
  }}}
    Walog__logger #l #circ_l
  {{{ RET #(); True }}}.
Proof.
  iIntros (Φ) "Hpre HΦ"; iNamed "Hpre".
  iMod (is_wal_read_mem with "Hwal") as "#Hmem".
  wp_call.
  iNamed "Hmem".
  iNamed "Hstfields".
  wp_loadField.
  wp_apply (acquire_spec with "[$]").
  iIntros "(Hlk_held&Hlkinv)".
  wp_pures.

  wp_apply (wp_inc_nthread with "[$st $Hlkinv]"); iIntros "Hlkinv".
  wp_pures.
  wp_bind (For _ _ _).
  wp_apply (wp_forBreak_cond (fun b => wal_linv σₛ.(wal_st) γ ∗ locked #σₛ.(memLock) ∗ logger_inv γ circ_l)%I
              with "[] [$]").
  { iIntros "!>" (Φ') "(Hlkinv&Hlk_held&Hlogger) HΦ".
    wp_apply (wp_load_shutdown with "[$st $Hlkinv]"); iIntros (shutdown) "Hlkinv".
    wp_pures.
    wp_if_destruct.
    - wp_pures.
      wp_apply (wp_Walog__logAppend with "[$Hlkinv $Hlk_held $Hlogger]").
      { iFrame "# ∗". }
      iIntros (progress) "(Hlkinv&Hlk_held&Hlogger)".
      wp_pures.
      wp_if_destruct.
      + wp_loadField.
        wp_apply (wp_condWait with "[$cond_logger $lk $Hlkinv $Hlk_held]").
        iIntros "(Hlk_held&Hlkinv)".
        wp_pures.
        iApply ("HΦ" with "[$]").
      + wp_pures. iApply ("HΦ" with "[$]").
    - iApply ("HΦ" with "[$]").
  }
  iIntros "(Hlkinv&Hlk_held&Hlogger)".
  wp_apply util_proof.wp_DPrintf.
  wp_apply (wp_dec_nthread with "[$st $Hlkinv]"); iIntros "Hlkinv".
  wp_loadField.
  wp_apply (wp_condSignal with "cond_shut").
  wp_loadField.
  wp_apply (release_spec with "[$lk $Hlk_held $Hlkinv]").
  iApply ("HΦ" with "[//]").
Qed.

End goose_lang.
