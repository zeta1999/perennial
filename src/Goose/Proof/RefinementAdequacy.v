From iris.algebra Require Import auth gmap frac agree.
Require Import Helpers.RelationTheorems.
Require Import Goose.Proof.Interp.
Require Import Spec.Proc.
Require Import Spec.ProcTheorems.
Require Import Spec.Layer.
From RecoveryRefinement.Goose Require Import Machine GoZeroValues Heap GoLayer.
Require Export CSL.WeakestPre CSL.Lifting CSL.Adequacy CSL.RefinementAdequacy.
Import Data.
Import Filesys.FS.
Import GoLayer.Go.


Class fsPreG (m: GoModel) {wf: GoModelWf m} Σ :=
  FsPreG {
      go_fs_dlocks_preG :> Count_Heap.gen_heapPreG string unit Σ;
      go_fs_dirs_preG :> gen_heapPreG string (gset string) Σ;
      go_fs_paths_preG :> gen_dirPreG string string (Inode) Σ;
      go_fs_inodes_preG :> gen_heapPreG Inode (List.list byte) Σ;
      go_fs_fds_preG :> gen_heapPreG File (Inode * OpenMode) Σ;
}.

Definition fsΣ (m: GoModel) {wf: GoModelWf m} : gFunctors :=
  #[gen_heapΣ string (gset string);
    Count_Heap.gen_heapΣ string unit;
    gen_dirΣ string string (Inode);
    gen_heapΣ Inode (List.list byte);
    gen_heapΣ File (Inode * OpenMode)
   ].

Instance subG_fsPreG m {wf: GoModelWf m} {Σ} : subG (fsΣ m) Σ → (fsPreG m) Σ.
Proof. solve_inG. Qed.

Class goosePreG (goose_model: GoModel) {wf: GoModelWf goose_model} Σ := GoosePreG {
  goose_preG_iris :> invPreG Σ;
  goose_preG_heap :> Count_Heap.gen_heapPreG (sigT Ptr) (sigT ptrRawModel) Σ;
  goose_preG_fs :> fsPreG goose_model Σ;
  goose_preG_treg_inG :> inG Σ (csumR countingR (authR (optionUR (exclR unitC))));
}.

Definition gooseΣ (m: GoModel) {wf: GoModelWf m} : gFunctors :=
  #[invΣ; fsΣ m; gen_typed_heapΣ Ptr ptrRawModel;
      GFunctor (csumR countingR (authR (optionUR (exclR unitC))))].
Instance subG_goosePreG (m: GoModel) {wf: GoModelWf m} {Σ} : subG (gooseΣ m) Σ → goosePreG m Σ.
Proof. solve_inG. Qed.


Section refinement.
  Context `{@goosePreG gm gmHwf Σ}.
  Context OpT (Λa: Layer OpT).
  Context `{cfgPreG OpT Λa Σ}.
  Context (impl: LayerImpl GoLayer.Op OpT).
  Notation compile_op := (compile_op impl).
  Notation compile_rec := (compile_rec impl).
  Notation compile_seq := (compile_seq impl).
  Notation compile := (compile impl).
  Notation recover := (recover impl).
  Notation compile_proc_seq := (compile_proc_seq impl).
  Context (crash_inner: forall {_ : @cfgG OpT Λa Σ} {_: gooseG gm Σ}, iProp Σ).
  Context (exec_inner: forall {_ : @cfgG OpT Λa Σ} {_ : gooseG gm Σ}, iProp Σ).
  Context (crash_param: forall (_ : @cfgG OpT Λa Σ) (_ : gooseG gm Σ), Type).
  Context (crash_inv: forall {H1 : @cfgG OpT Λa Σ} {H2 : gooseG gm Σ}, @crash_param _ _ → iProp Σ).
  Context (crash_starter: forall {H1 : @cfgG OpT Λa Σ} {H2 : gooseG gm Σ}, @crash_param _ _ → iProp Σ).
  Context (exec_inv: forall {_ : @cfgG OpT Λa Σ} {_ : gooseG gm Σ}, iProp Σ).

  Context (einv_persist: forall {H1 : @cfgG OpT Λa Σ} {H2 : gooseG gm Σ}, Persistent (exec_inv H1 H2)).
  Context (cinv_persist: forall {H1 : @cfgG OpT Λa Σ} {H2 : gooseG gm Σ}
            {P: crash_param _ _}, Persistent (crash_inv H1 H2 P)).

  Context (E: coPset).
  Context (nameIncl: nclose sourceN ⊆ E).
  (* TODO: we should get rid of rec_seq if we're not exploiting vertical comp anymore *)
  Context (recv: proc GoLayer.Op unit).
  Context (recsingle: recover = rec_singleton recv).

  Context (refinement_op_triples:
             forall {H1 H2 T1 T2} j K `{LanguageCtx OpT T1 T2 Λa K} (op: OpT T1),
               j ⤇ K (Call op) ∗ Registered ∗ (@exec_inv H1 H2) ⊢
                 WP compile (Call op) {{ v, j ⤇ K (Ret v) ∗ Registered }}).

  Context (exec_inv_source_ctx: ∀ {H1 H2}, exec_inv H1 H2 ⊢ source_ctx).

  Lemma refinement_triples:
             forall {H1 H2 T1 T2} j K `{LanguageCtx OpT T1 T2 Λa K} (e: proc OpT T1),
               wf_client e →
               j ⤇ K e ∗ Registered ∗ (@exec_inv H1 H2) ⊢
                 WP compile e {{ v, j ⤇ K (Ret v) ∗ Registered }}.
  Proof.
    intros ???? j K Hctx e Hwf.
    iIntros "(Hj&Hreg&#Hinv)".
    iAssert (⌜∃ ea: Layer.State Λa, True⌝)%I as %[? _].
    {
      iDestruct (exec_inv_source_ctx with "Hinv") as ((?&?)) "#Hctx".
      eauto.
    }
    assert (Inhabited (Layer.State Λa)).
    { eexists. eauto. }
    assert (Inhabited Λa.(OpState)).
    { eexists. destruct x; eauto. }
    iInduction e as [] "IH" forall (j T2 K Hctx).
    - iApply refinement_op_triples; iFrame; eauto.
    - wp_ret. iFrame.
    - wp_bind.
      iApply wp_wand_l. iSplitL ""; last first.
      * unshelve (iApply ("IH1" $! _ _ _ (fun x => K (Bind x p2)) with "[] Hj"); try iFrame).
        { eapply Hwf. }
        { iPureIntro. apply comp_ctx; auto. apply _. }
      * iIntros (?) "(Hj&Hreg)".
        iDestruct (exec_inv_source_ctx with "Hinv") as "#Hctx".
        iMod (ghost_step_bind_ret with "Hj []") as "Hj".
        { set_solver+. }
        { eauto. }
        iApply ("IH" with "[] [] Hj Hreg"); auto.
        { iPureIntro. eapply Hwf. }
    - iLöb as "IHloop" forall (init Hwf).
      iDestruct (exec_inv_source_ctx with "Hinv") as "#Hctx".
      iMod (ghost_step_loop with "Hj []") as "Hj".
      { set_solver+. }
      { eauto. }
      wp_loop.
      iApply wp_wand_l.
      iSplitL ""; last first.
      * rewrite /loop1. simpl.
        unshelve (iApply ("IH" $! _ _ _ _ (fun x => K (Bind x
                               (fun out => match out with
                               | ContinueOutcome x => Loop body x
                               | DoneWithOutcome r => Ret r
                               end))) with "[] Hj Hreg")%proc).
        { eauto. }
        { iPureIntro. apply comp_ctx; auto. apply _. }
      * iIntros (out) "(Hj&Hreg)".
        destruct out.
        ** iNext.
           iMod (ghost_step_bind_ret with "Hj []") as "Hj".
           { set_solver+. }
           { eauto. }
           iApply ("IHloop" with "[] Hj Hreg").
           { eauto. }
        ** iNext.
           iMod (ghost_step_bind_ret with "Hj []") as "Hj".
           { set_solver+. }
           { eauto. }
           wp_ret. iFrame.
   - inversion Hwf.
   - inversion Hwf.
   - iDestruct (exec_inv_source_ctx with "Hinv") as "#Hctx".
     iMod (ghost_step_spawn with "Hj []") as "(Hj&Hj')".
     { set_solver+. }
     { eauto. }
     iDestruct "Hj'" as (j') "Hj'".
     iApply (wp_spawn with "Hreg [Hj'] [Hj]").
     { iNext. iIntros "Hreg'".
       { wp_bind.
         iApply (wp_wand with "[Hj' Hreg'] []").
         { unshelve (iApply ("IH" $! _ _ _ (fun x => Bind x (fun _ => Unregister))
                               with "[] Hj' Hreg'")).
           { eauto. }
           { iPureIntro. apply _. }
         }
         { iIntros (?) "(?&?)". iApply (wp_unregister with "[$]"). iIntros "!> ?". eauto. }
       }
     }
     iIntros "!> ?". iFrame.
  Qed.

  Context (recv_triple:
             forall {H1 H2} param,
               (@crash_inv H1 H2 param) ∗ Registered ∗ (@crash_starter H1 H2 param) ⊢
                    WP recv @ NotStuck; ⊤ {{ v, |={⊤,E}=> ∃ σ2a σ2a', source_state σ2a
                    ∗ ⌜Proc.crash_step Λa σ2a (Val σ2a' tt)⌝ ∗
                    ∀ `{Hcfg': cfgG OpT Λa Σ} (Hinv': invG Σ) tr',
                      source_ctx ∗ source_state σ2a'  ={⊤}=∗
                      exec_inner Hcfg' (GooseG _ _ Σ Hinv' go_heap_inG go_fs_inG tr')
                                               }}).

  Context (init_absr: Λa.(OpState) → State → Prop).
  Context (init_wf: ∀ σ1a σ1c, init_absr σ1a σ1c → dom (gset string) σ1c.(fs).(dirents) =
                                                   dom (gset string) σ1c.(fs).(dirlocks)).

  Context (init_exec_inner: ∀ σ1a σ1c, init_absr σ1a σ1c →
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ},
          (([∗ map] d ↦ ents ∈ σ1c.(fs).(dirents), d ↦ dom (gset string) ents) ∗
           source_ctx ∗ source_state σ1a) ={⊤}=∗ exec_inner _ _)).

  (* Helper to update collection of ghost algebra for file system to use new
     "generation" mapping for fds/dlocks post crash. *)
  Definition crash_fsG {Σ} (curr: @fsG _ _ Σ) newDirLocks newFds : @fsG _ _ Σ :=
    FsG _ _ _ newDirLocks (go_fs_dirs_inG) (go_fs_paths_inG) (go_fs_inodes_inG) newFds.

  Context (exec_inv_preserve_crash:
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ},
          exec_inv Hcfg Hex ={⊤, E}=∗ ∀ Hmem' Hdlocks' Hfds' Hreg',
            (let Hex := GooseG _ _ Σ (go_invG) Hmem' (crash_fsG _ Hdlocks' Hfds') Hreg' in
           (* TODO: should get dirlocks + uninit global*)
           True ={E}=∗ crash_inner Hcfg Hex))).

  Context (crash_inv_preserve_crash:
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ} param,
          crash_inv Hcfg Hex param ={⊤, E}=∗ ∀ Hmem' Hdlocks' Hfds' Hreg',
          (let Hex := GooseG _ _ Σ (go_invG) Hmem' (crash_fsG _ Hdlocks' Hfds') Hreg' in
           (* TODO: should get dirlocks + uninit global *)
           True ={E}=∗ crash_inner Hcfg Hex))).

  (* TODO: Much of this business is just to capture the fact that exec_inner/crash_inner
     should not really mention invariants, because those old invariants are 'dead' *)
  Context (crash_inner_inv :
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ},
          (∃ Hinv, crash_inner Hcfg (GooseG _ _ Σ Hinv (go_heap_inG) (go_fs_inG) (go_treg_inG))) ∗
          source_ctx ={⊤}=∗ ∃ param, crash_inv Hcfg Hex param ∗ crash_starter Hcfg Hex param)).

  Context (exec_inner_inv :
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ},
          (∃ Hinv, exec_inner Hcfg (GooseG _ _ Σ Hinv (go_heap_inG) (go_fs_inG) (go_treg_inG))) ∗
          source_ctx ={⊤}=∗ exec_inv Hcfg Hex)).

  Context (exec_inv_preserve_finish:
      (∀ `{Hex: @gooseG gm gmHwf Σ} `{Hcfg: cfgG OpT Λa Σ},
          AllDone -∗ exec_inv Hcfg Hex ={⊤, E}=∗ ∃ (σ2a σ2a' : Λa.(OpState)), source_state σ2a
          ∗ ⌜Λa.(finish_step) σ2a (Val σ2a' tt)⌝ ∗
          ∀ `{Hcfg': cfgG OpT Λa Σ} (Hinv': invG Σ) Hmem' Hdlocks' Hfds' Hreg',
            (let Hex := GooseG _ _ Σ Hinv' Hmem' (crash_fsG _ Hdlocks' Hfds') Hreg' in
             source_ctx ∗ source_state σ2a' ∗
            (* TODO: should get fresh global/dirlocks *) True ={⊤}=∗ exec_inner Hcfg' Hex))%I).


  Lemma exmach_crash_refinement_seq {T} σ1c σ1a (es: proc_seq OpT T) :
    init_absr σ1a σ1c →
    wf_client_seq es →
    ¬ proc_exec_seq Λa es (rec_singleton (Ret ())) (1, σ1a) Err →
    ∀ σ2c res, proc_exec_seq GoLayer.Go.l (compile_proc_seq es)
                                        (rec_singleton recv) (1, σ1c) (Val σ2c res) →
    ∃ σ2a, proc_exec_seq Λa es (rec_singleton (Ret tt)) (1, σ1a) (Val σ2a res).
  Proof.
    rewrite /compile_proc_seq. intros Hinit Hwf_seq Hno_err σ2c0 ?.
    unshelve (eapply wp_proc_seq_refinement_adequacy with
                  (Λc := l)
                  (φ := fun _ _ _ => True%I)
                  (E0 := E); eauto).
    clear Hno_err.
  iAssert (∀ invG H1 ρ, |={⊤}=>
       ∃ hM hD tR
         (*
            (Hmpf_eq : hM.(@gen_heap_inG addr nat Σ nat_eq_dec nat_countable) =
          H.(@exm_preG_disk Σ).(@gen_heap_preG_inG addr nat Σ nat_eq_dec nat_countable))
            (Hdpf_eq : hD.(@gen_heap_inG addr nat Σ nat_eq_dec nat_countable) =
          H.(@exm_preG_disk Σ).(@gen_heap_preG_inG addr nat Σ nat_eq_dec nat_countable))
          *),
             ((@state_interp _ _ _ (@gooseG_irisG _ _ _ (GooseG _ _ Σ _ hM hD {| treg_name := tR; treg_counter_inG := _ |}))) (1, σ1c)) ∗
         (source_ctx' (ρ, σ1a) -∗ source_state σ1a ={⊤}=∗
         own tR (Cinl (Count (-1))) ∗
          exec_inner H1 (GooseG _ _ Σ invG hM hD {| treg_name := tR; treg_counter_inG := _ |})))%I
      as "Hpre".
  {
  iIntros.
  iMod (gen_typed_heap_strong_init (σ1c.(fs).(heap).(allocs))) as (hM Hmpf_eq) "(Hmc&Hm)".
  iMod (gen_heap_strong_init (fmap (dom (gset string)) (σ1c.(fs).(dirents)))) as (hD Hdpf_eq) "(Hdc&Hd)".
  iMod (gen_heap_strong_init (σ1c.(fs).(fds))) as (hFDs HFDpf_eq) "(Hfdc&Hfd)".
  iMod (gen_heap_strong_init (σ1c.(fs).(inodes))) as (hIs HIpf_eq) "(Hidc&Hi)".
  iMod (gen_dir_strong_init (σ1c.(fs).(dirents))) as (hP HPpf_eq) "(Hpc&Hp)".
  iMod (Count_Heap.gen_heap_strong_init (λ s, (σ1c.(fs).(dirlocks)) !! s)) as (hL HLpf_eq) "(Hlc&Hl)".
  iMod (own_alloc (Cinl (Count 0))) as (tR) "Ht".
  { constructor. }
  set (tR' := {| treg_name := tR; treg_counter_inG := _ |}).
  iAssert (own tR (Cinl (Count 1)) ∗ own tR (Cinl (Count (-1))))%I with "[Ht]" as "(Ht&Hreg)".
  { rewrite /Registered -own_op Cinl_op counting_op' //=. }
  set (hFG := (FsG _ _ Σ hL hD hP hIs hFDs)).
  iModIntro. iExists hM, hFG, tR. (* Hmpf_eq, Hdpf_eq. *)
  iSplitL "Hmc Hdc Hfdc Hidc Hpc Hlc Ht".
  { iFrame. iPureIntro. eapply init_wf; eauto. }
  iIntros.
  iPoseProof (init_exec_inner σ1a σ1c Hinit (GooseG _ _ Σ _ hM hFG tR') _) as "H".
  iMod ("H" with "[-Hreg]") as "$".
  { iFrame.  iSplitL "Hd".
    * iPoseProof (@gen_heap_init_to_bigOp _ _ _ _ _ hD with "[Hd]") as "Hfoo".
      { by rewrite Hdpf_eq. }
      by rewrite big_opM_fmap.
    * iExists _; eauto.
  }
  iFrame; eauto.
  }

  clear Hinit.
  iInduction es as [|es] "IH" forall (σ1a σ1c) "Hpre"; first by eauto.
  - iSplit; first by eauto.
  iExists (fun cfgG s => ∃ (Hex : @gooseG _ _ Σ), state_interp s ∗
            (∃ hM hDlock' hFds'  tr
               (*
               (Hmpf_eq : hM.(@gen_heap_inG addr nat Σ nat_eq_dec nat_countable) =
                          H.(@exm_preG_disk Σ).(@gen_heap_preG_inG addr nat Σ
                                                                   nat_eq_dec nat_countable))
               (Hdpf_eq : (@exm_disk_inG Σ Hex).(@gen_heap_inG addr nat Σ
                                                               nat_eq_dec nat_countable)=
                          H.(@exm_preG_disk Σ).(@gen_heap_preG_inG addr nat Σ
                                                                   nat_eq_dec nat_countable)) 
                *),
                gen_typed_heap_ctx ∅ ∗ own tr (Cinl (Count 0))
                                   ∗ gen_heap_ctx (∅: gmap File (Inode * OpenMode))
                                   ∗ crash_inner cfgG
                                   (GooseG _ _ Σ _ hM (crash_fsG (go_fs_inG) hDlock' hFds')
 {| treg_name := tr; treg_counter_inG := _ |})))%I; auto.
  iIntros (invG0 Hcfg0).
  iMod ("Hpre" $! invG0 _ _) as (hM hD tr (* ?? *) ) "(Hstate0&H)".
  set (tR' := {| treg_name := tr; treg_counter_inG := _ |}).
  set (hG := (GooseG _ _ Σ _ hM hD tR')).
  iExists (@state_interp _ _ _ (@gooseG_irisG _ _ _ hG)).
  (*
  iExists (@state_interp _ _ _ (@gooseG_irisG _ _ _ hG)).
   *)
  iIntros "!> (#Hsrc&Hpt0&Hstate)".
  iMod ("H" with "Hsrc Hstate") as "(Hreg&Hinv)".
  iMod (exec_inner_inv hG _ with "[Hinv]") as "#Hinv".
  { iSplitR ""; last by (iExists _; iFrame). iExists _. iFrame. }
  simpl.
  iModIntro.
  iFrame "Hstate0".
  iSplitL "Hpt0 Hreg".
  {  iPoseProof (@wp_mono with "[Hpt0 Hreg]") as "H"; swap 1 2.
     { iApply refinement_triples. destruct (Hwf_seq) as (?&?). eauto. iFrame. iFrame "Hinv".
     }
     { reflexivity. }
     rewrite /compile_whole.
     wp_bind.
     iApply (wp_wand with "H [Hinv]").
     iIntros (v) "(Hpt0&Hreg)". iFrame.
     wp_bind.
     iApply (wp_wait with "Hreg").
     iIntros "!> Hdone".
     wp_ret. iFrame. iIntros (σ2c) "Hmach".
     iMod (exec_inv_preserve_finish with "Hdone Hinv") as (σ2a σ2a') "(H&Hfina&Hfinish)".
     iDestruct "Hfina" as %Hfina.
     iModIntro. iExists _; iFrame; auto.
     rewrite -/wp_proc_seq_refinement.
     iIntros (σ2c'). iIntros.
     unshelve (iExists σ2a', _); [eauto |]; [].
     iApply "IH".
     { iPureIntro. destruct Hwf_seq. eauto. }
     { iIntros.
       destruct σ2c as (n&σ2c). iDestruct "Hmach" as "(?&Hmach)".
       iMod (gen_typed_heap_strong_init ∅) as (hM' Hmpf_eq') "(Hmc&Hm)".
       iMod (gen_heap_strong_init (∅: gmap File (Inode * OpenMode)))
         as (hFds' Hfds'_eq') "(Hfdsc&Hfd)".
       iMod (Count_Heap.gen_heap_strong_init 
               (λ s, ((λ _ : LockStatus * (), (Unlocked, ())) <$> σ2c.(fs).(dirlocks)) !! s))
         as (hDlocks' Hdlocks'_eq') "(Hdlocksc&Hlocks)".
       iMod (own_alloc (Cinl (Count 0))) as (tR_fresh') "Ht".
       { constructor. }
       iAssert (own tR_fresh' (Cinl (Count 1))
                    ∗ own tR_fresh' (Cinl (Count (-1))))%I with "[Ht]" as "(Ht&Hreg)".
       { rewrite /Registered -own_op Cinl_op counting_op' //=. }
       set (tR''' := {| treg_name := tR_fresh'; treg_counter_inG := _ |}).
       iModIntro.
       iExists hM'. iExists (crash_fsG hD hDlocks' hFds'). iExists tR_fresh'.
       (* unshelve (iExists _, _); try eauto. *)
       iFrame.
       iSplitL ("Hmc Hmach Hfdsc Hdlocksc").
       { iClear "IH".
         iDestruct "Hmach" as "(?&?&?&?&?&?&?)".
         repeat deex. inv_step.
         rewrite H4. simpl.
         iFrame. simpl.
         rewrite dom_fmap_L.
         iFrame.
       }
       iIntros "Hctx' Hsrc'". iMod ("Hfinish" $! _ _ hM' with "[-]").
       iSplitL "Hctx'"; first by (iExists _; iFrame). iFrame.
       unfold hG. simpl. unfold tR'''. iFrame.
       eauto.
     }
  }
  iSplit.
  { iIntros (σ2c) "Hmach".
    destruct σ2c as (n&σ2c). iDestruct "Hmach" as "(?&Hmach)".
    iMod (exec_inv_preserve_crash with "Hinv") as "Hinv_post".
    iMod (gen_typed_heap_strong_init ∅) as (hM' Hmpf_eq') "(Hmc&Hm)".
    iMod (gen_heap_strong_init (∅: gmap File (Inode * OpenMode)))
      as (hFds' Hfds'_eq') "(Hfdsc&Hfd)".
    iMod (Count_Heap.gen_heap_strong_init 
            (λ s, ((λ _ : LockStatus * (), (Unlocked, ())) <$> σ2c.(fs).(dirlocks)) !! s))
      as (hDlocks' Hdlocks'_eq') "(Hdlocksc&Hlocks)".
    iMod (own_alloc (Cinl (Count 0))) as (tR_fresh') "Ht".
    { constructor. }
    set (tR''' := {| treg_name := tR_fresh'; treg_counter_inG := _ |}).
    iMod ("Hinv_post" with "[Hm]") as "Hinv'".
    auto.
    iIntros. iModIntro.
    unfold hG.
    simpl.


    iExists (GooseG _ _ Σ (@go_invG _ _ _ hG) hM hD tR'). iFrame.
    iExists hM', _, _, tR_fresh'. iFrame.
  }
  iClear "Hsrc".
  iModIntro. iIntros (invG Hcfg' ?? Hcrash) "(Hinv0&#Hsrc)".
  iDestruct "Hinv0" as (HexmachG') "(Hinterp&Hinv0)".
  iDestruct "Hinv0" as (hM' hDl' hFd' tR_fresh' (* Hmpf_eq' Hmdpf_eq' *)) "(Hmc'&Hreg&Hfdc'&Hcrash_inner)".
  iClear "Hinv".
  set (tR''' := {| treg_name := tR_fresh'; treg_counter_inG := _ |}).
  iMod (crash_inner_inv (GooseG _ _ Σ _
                                 hM' (crash_fsG (go_fs_inG) hDl' hFd') tR''') Hcfg'
                         with "[Hcrash_inner]") as (param) "(#Hinv&Hstarter)".
  { iIntros. simpl. iSplitR ""; last by (iExists _; iFrame).
    iExists (gooseG_irisG.(@iris_invG GoLayer.Op (Layer.State l) Σ)). iFrame. }
  iModIntro.
  iAssert (own tR_fresh' (Cinl (Count 1)) ∗ own tR_fresh' (Cinl (Count (-1))))%I
    with "[Hreg]" as "(Ht&Hreg)".
  { rewrite /Registered -own_op Cinl_op counting_op' //=. }
  iExists (@state_interp _ _ _ (@gooseG_irisG _ _ _ (GooseG _ _ _ _ hM' (crash_fsG (@go_fs_inG _ _ _ HexmachG') hDl' hFd') tR'''))).
  (*
  iExists (@state_interp _ _ _ (@gooseG_irisG _ _ tR''' hG)).
   *)
  (*
  iExists (@ex_mach_interp Σ hM' (exm_disk_inG) tR''').
   *)
  iSplitL "Hinterp Ht Hmc' Hfdc'".
  { (* shows ex_mach_interp is holds after crash for next gen *)
    destruct a, a0.
    iDestruct "Hinterp" as "(?&Hinterp)".
    destruct Hcrash as ([]&(?&?)&Hput&Hrest).
    inversion Hput. subst. inv_step.
    inversion Hrest; subst. inversion H1. subst.
    deex. inv_step.
    inv_step. inversion H2. inv_step. inversion H3. subst.
    inv_step. subst.
    inversion H4. subst. deex. inv_step. subst.
    rewrite H6.
    simpl.
    iSplitL "Ht".
    { iFrame. }
    iFrame.
    simpl.
    iFrame.
    unfold RecordSet.set. simpl.
    iDestruct "Hinterp" as "(?&?&?&?&?&?&?)".
    unfold crash_fsG. simpl. unfold fs_interp. simpl.
    iFrame.
    iSplitL "".
    { (* todo: need to include dirlocks in the invariant, but to do that
         we have to keep track of what directories there are throughout *)
      admit. }
    rewrite dom_fmap_L. auto.
  }
  iSplitL "Hinv Hreg Hstarter".
  {
    iPoseProof (@wp_mono with "[Hinv Hreg Hstarter IH]") as "H"; swap 1 2.
    { iApply recv_triple. iFrame "Hstarter". iFrame. iApply "Hinv". }
    { reflexivity. }
    iApply (@wp_wand with "H [IH]").
    iIntros (_) "H". iIntros (σ2c) "Hinterp".
    iMod "H". iModIntro.
    iDestruct "H" as (σ2a σ2a') "(Hsource&Hinner&Hfinish)".
    iExists (1, σ2a), (1, σ2a'). iFrame.
     rewrite -/wp_proc_seq_refinement.
     iDestruct "Hinner" as %?.
     iSplitL "".
     { iPureIntro. exists tt, (1, σ2a); split; eauto. econstructor. split; eauto. eauto.
       econstructor; eauto.
     }
     iApply "IH".
     { destruct Hwf_seq. eauto. }
     { iIntros.
       iMod (@own_alloc _ _ H.(@goose_preG_treg_inG gm gmHwf Σ)
                        (Cinl (Count 0))) as (tR_fresh'') "Ht".
       { constructor. }
       iAssert (@own _ _ H.(@goose_preG_treg_inG gm gmHwf Σ) tR_fresh'' (Cinl (Count 1))
                    ∗ @own _ _ H.(@goose_preG_treg_inG gm gmHwf Σ) tR_fresh'' (Cinl (Count (-1))))%I with "[Ht]" as "(Ht&Hreg)".
       { rewrite /Registered -own_op Cinl_op counting_op' //=. }
       set (tR'''' := {| treg_name := tR_fresh''; treg_counter_inG := H.(@goose_preG_treg_inG gm gmHwf Σ) |}).
       iModIntro.
       iExists hM'.
       iExists (crash_fsG (HexmachG'.(@go_fs_inG _ _ Σ)) hDl' hFd'). iExists tR_fresh''.
       destruct σ2c.
       iDestruct "Hinterp" as "(?&?&?&?&?&?&?&?)".
       iFrame. iIntros.
       iFrame.
       iMod ("Hfinish" with "[-]"). iSplitL ""; first by (iExists _; iFrame).
       iFrame. simpl. unfold tR''''. eauto.
     }
  }
  {
    iIntros (σ2c) "Hmach".
    destruct σ2c as (n&σ2c). iDestruct "Hmach" as "(?&Hmach)".
    iMod (crash_inv_preserve_crash with "Hinv") as "Hinv_post".
    iMod (gen_typed_heap_strong_init ∅) as (hM'' Hmpf_eq'') "(Hmc&Hm)".
    iMod (gen_heap_strong_init (∅: gmap File (Inode * OpenMode)))
      as (hFds' Hfds'_eq') "(Hfdsc&Hfd)".
    iMod (Count_Heap.gen_heap_strong_init
            (λ s, ((λ _ : LockStatus * (), (Unlocked, ())) <$> σ2c.(fs).(dirlocks)) !! s))
      as (hDlocks' Hdlocks'_eq') "(Hdlocksc&Hlocks)".
    iMod (own_alloc (Cinl (Count 0))) as (tR_fresh'') "Ht".
    { constructor. }
    set (tR'''' := {| treg_name := tR_fresh''; treg_counter_inG := _ |}).
    iMod ("Hinv_post" with "[Hm]") as "Hinv'".
    { eauto. }
    iIntros. iModIntro.
    unfold hG.
    simpl.
    iDestruct "Hmach" as "(?&?&?&?&?&?&?)".
    iExists (GooseG _ _ Σ invG hM'
               (crash_fsG HexmachG'.(@go_fs_inG _ _ Σ) hDl' hFd') tR'''). iFrame.
    iExists hM'', _, _, tR_fresh''. iFrame.
  Admitted.

End refinement.
