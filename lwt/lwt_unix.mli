(* Module [Lwt_unix]: thread-compatible system calls *)

val sleep : float -> unit Lwt.t
      (* [sleep d] is a threads which remain suspended for [d] seconds
         (letting other threads run) and then terminates. *)
val yield : unit -> unit Lwt.t
      (* [yield ()] is a threads which suspends itself (letting other
         thread run) and then resumes as soon as possible and
         terminates. *)

val run : 'a Lwt.t -> 'a
      (* [run t] lets the thread [t] run until it terminates.  It
         evaluates to the return value of [t], or raise the exception
         associated to [t] if [t] fails.

         You should avoid using [run] inside threads:
         - The calling threads will not resume before [run]
           returns.
         - Successive invocations of [run] are serialized: an
           invocation of [run] will not terminate before all
           subsequent invocations are terminated. *)

(****)

(* These functions behaves as their [Unix] counterparts, but let other
   threads run while waiting for the completion of the system call.

   PITFALL
   If you want to read or write from stdin, stdout or stderr using
   this library, you must first turn them into non-blocking mode
   using [Unix.set_nonblock]. *)

val read : Unix.file_descr -> string -> int -> int -> int Lwt.t
val write : Unix.file_descr -> string -> int -> int -> int Lwt.t
val pipe : unit -> (Unix.file_descr * Unix.file_descr) Lwt.t
val socket :
  Unix.socket_domain -> Unix.socket_type -> int -> Unix.file_descr Lwt.t
val socketpair :
  Unix.socket_domain -> Unix.socket_type -> int ->
  (Unix.file_descr * Unix.file_descr) Lwt.t
val accept : Unix.file_descr -> (Unix.file_descr * Unix.sockaddr) Lwt.t
val connect : Unix.file_descr -> Unix.sockaddr -> unit Lwt.t

val wait : unit -> (int * Unix.process_status) Lwt.t
val waitpid : Unix.wait_flag list -> int -> (int * Unix.process_status) Lwt.t

val system : string -> Unix.process_status Lwt.t

val open_process_in: string -> in_channel Lwt.t
val open_process_out: string -> out_channel Lwt.t
val open_process: string -> (in_channel * out_channel) Lwt.t
val open_process_full:
  string -> string array -> (in_channel * out_channel * in_channel) Lwt.t
val close_process_in: in_channel -> Unix.process_status Lwt.t
val close_process_out: out_channel -> Unix.process_status Lwt.t
val close_process: in_channel * out_channel -> Unix.process_status Lwt.t
val close_process_full:
  in_channel * out_channel * in_channel -> Unix.process_status Lwt.t
