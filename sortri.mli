(* $I1: Unison file synchronizer: src/sortri.mli $ *)
(* $I2: Last modified by vouillon on Wed, 24 Jan 2001 10:09:52 -0500 $ *)
(* $I3: Copyright 1999-2002 (see COPYING for details) $ *)

(* Sort a list of recon items according to the current setting of 
   various preferences (defined in sort.ml, and accessible from the
   profile and via the functions below) *)
val sortReconItems : Common.reconItem list -> Common.reconItem list

(* The underlying comparison function for sortReconItems (in case we
   want to use it to sort something else, like stateItems in the UI) *)
val compareReconItems : unit -> (Common.reconItem -> Common.reconItem -> int)

(* Set the global preferences so that future calls to sortReconItems
   will sort in particular orders *)
val sortByName : unit -> unit
val sortBySize : unit -> unit
val sortNewFirst : unit -> unit
val restoreDefaultSettings : unit -> unit

