(* $I1: Unison file synchronizer: src/uutil.mli $ *)
(* $I2: Last modified by vouillon on Mon, 25 Mar 2002 12:08:56 -0500 $ *)
(* $I3: Copyright 1999-2002 (see COPYING for details) $ *)

(* This module collects a number of low-level, Unison-specific utility
   functions.  It is kept separate from the Util module so that that module
   can be re-used by other programs. *)

(* Identification *)
val myVersion : string         (* version of the program : generated by PRCS *)
val myName : string            (* name of the program : generated by PRCS *)

(* Hashing *)
val hash2 : int -> int -> int

module type FILESIZE = sig
  type t
  val zero : t
  val dummy : t
  val add : t -> t -> t
  val neg : t -> t
  val toFloat : t -> float
  val toString : t -> string
  val ofInt : int -> t
  val hash : t -> int
  val percentageOfTotalSize : t -> t -> float
end

module Filesize : FILESIZE

(* FIX: We should eventually get rid of this... *)
(* An abstract type of file sizes                                            *)
type filesize
val zerofilesize : filesize
val dummyfilesize : filesize
val addfilesizes : filesize -> filesize -> filesize
val filesize2float : filesize -> float
val filesize2string : filesize -> string
val int2filesize : int -> filesize
val hashfilesize : filesize -> int
val percentageOfTotalSize :
  filesize ->   (* current value *)
  filesize ->   (* total value *)
  float         (* percentage of total *)
val extendfilesize : filesize -> Filesize.t

(* The UI may (if it likes) supply a function to be used to show progress of *)
(* file transfers.                                                           *)
module File :
  sig
    type t
    val ofLine : int -> t
    val toLine : t -> int
    val dummy : t
  end
val setProgressPrinter :
  (File.t -> Filesize.t ->  string -> unit) -> unit
val showProgress : File.t -> Filesize.t -> string -> unit

(* Utility function to transfer bytes from one file descriptor to another
   until EOF *)
val readWrite :
     Unix.file_descr            (* source *)
  -> Unix.file_descr            (* target *)
  -> (int -> unit)              (* progress notification *)
  -> unit
