(* $I1: Unison file synchronizer: src/recon.mli $ *)
(* $I2: Last modified by zheyang on Wed, 12 Dec 2001 02:26:21 -0500 $ *)
(* $I3: Copyright 1999-2002 (see COPYING for details) $ *)

val reconcileAll : 
     Common.updateItem list Common.oneperpath
                                (* one updateItem per replica, per path *)
  -> Common.reconItem list      (* List of updates that need propagated *)
     * bool                     (* Any file updated equally on all roots*)
(* --------------- *)
      
val reconcileTwo : Path.t -> Common.updateItem -> Common.updateItem ->
  Common.reconItem list * bool

(* Use the current values of the '-prefer <ROOT>' and '-force <ROOT>'        *)
(* preferences to override the reconciler's choices                          *)
val overrideReconcilerChoices : Common.reconItem list -> unit

(* If the given reconItem's default direction is Conflict (or the third      *)
(* argument is `Force), then set it as specified by the second argument.     *)
val setDirection :
  Common.reconItem ->
  [`Older | `Newer | `Replica1ToReplica2 | `Replica2ToReplica1] ->
  [`Force | `Prefer] ->
  unit

(* Set the given reconItem's direction back to the default                   *)
val revertToDefaultDirection : Common.reconItem -> unit

(* Look up the preferred root and verify that it is OK (this is called at    *)
(* the beginning of the run, before we do anything time consuming, so that   *)
(* we don't have to wait to hear about errors                                *)
val checkThatPreferredRootIsValid : unit -> unit
