(* $I1: Unison file synchronizer: src/os.ml $ *)
(* $I2: Last modified by zheyang on Sat, 06 Apr 2002 18:26:24 -0500 $ *)
(* $I3: Copyright 1999-2002 (see COPYING for details) $ *)

(* This file attempts to isolate operating system specific details from the  *)
(* rest of the program.                                                      *)

let debug = Util.debug "os"

let myCanonicalHostName = 
  try Unix.getenv "UNISONLOCALHOSTNAME"
  with Not_found -> Unix.gethostname()

let tempFilePrefix = ".#"
let tempFileSuffix = ".unison.tmp"
let backupFileSuffix = ".unison.bak"

(*****************************************************************************)
(*                      QUERYING THE FILESYSTEM                              *)
(*****************************************************************************)

let exists fspath path =
  (Fileinfo.get false fspath path).Fileinfo.typ <> `ABSENT

let readLink fspath path =
  Util.convertUnixErrorsToTransient
  "reading symbolic link"
    (fun () ->
       let abspath = Fspath.concatToString fspath path in
       Unix.readlink abspath)

(* Assumes that (fspath, path) is a directory, and returns the list of       *)
(* children, except for '.' and '..'.  Note that childrenOf and delete are   *)
(* mutually recursive: this is because one of the side-effects of childrenOf *)
(* is to delete old files left around by Unison.                             *)
let rec childrenOf fspath path =
  Util.convertUnixErrorsToTransient
  "scanning directory"
    (fun () ->
      let rec loop children directory =
        try
          let newFile = Unix.readdir directory in
          let newChildren =
            if newFile = "." || newFile = ".."
               || Util.endswith newFile backupFileSuffix then
              children
            else if (Util.endswith newFile tempFileSuffix &&
		     Util.startswith newFile tempFilePrefix)
	    then
              (let newPath = Path.child path (Name.fromString newFile) in
(* We comment out the following, since warning doesn't work nicely under     *)
(* multi-threading.  Instead, we make the suffix strange enough for tmp      *)
(* files                                                                     *)
(*                                                                         - *)
(*              Util.warn                                                    *)
(*                 (Printf.sprintf                                           *)
(*                    "WARNING: The file\n\n  %s\n\non\n\n  %s\n             *)
(*                     appears to be left over from a previous run of %s.\n  *)
(*                     I'll delete it."                                      *)
(*                    (Fspath.concatToString fspath newPath)                 *)
(*                    myCanonicalHostName                                    *)
(*                    Uutil.myName);                                          *)
(*                                                                         - *)
               delete fspath newPath;
               children)
            else
              newFile::children in
          loop newChildren directory
        with End_of_file -> children in
      let absolutePath = Fspath.concat fspath path in
      let directory = Fspath.opendir absolutePath in
      let result = loop [] directory in
      Unix.closedir directory;
      result)

(*****************************************************************************)
(*                        ACTIONS ON FILESYSTEM                              *)
(*****************************************************************************)

(* Deletes a file or a directory, but checks before if there is something    *)
and delete fspath path =
  Util.convertUnixErrorsToTransient
  "deleting"
    (fun () ->
       let absolutePath = Fspath.concatToString fspath path in
       match (Fileinfo.get false fspath path).Fileinfo.typ with
         `DIRECTORY ->
           Unix.chmod absolutePath 0o700;
           Safelist.iter
             (fun child -> delete fspath (Path.child path
                                            (Name.fromString child)))
             (childrenOf fspath path);
           Unix.rmdir absolutePath
       | `FILE ->
           if Util.osType <> `Unix then
             Unix.chmod absolutePath 0o600;
           Unix.unlink absolutePath
       | `SYMLINK ->
           (* Note that chmod would not do the right thing on links *)
           Unix.unlink absolutePath
       | `ABSENT ->
           ())

let rename sourcefspath sourcepath targetfspath targetpath =
  let source = Fspath.concatToString sourcefspath sourcepath in
  let target = Fspath.concatToString targetfspath targetpath in
  Util.convertUnixErrorsToTransient
  "renaming"
    (fun () ->
       debug (fun() -> Util.msg "rename %s to %s\n" source target);
       Unix.rename source target)

let symlink = 
  if Util.isCygwin || (Util.osType != `Win32) then
    fun fspath path l ->
      Util.convertUnixErrorsToTransient
      "writing symbolic link"
      (fun () -> 
       let abspath = Fspath.concatToString fspath path in
       Unix.symlink l abspath)
  else
    fun fspath path l ->
      raise (Util.Transient "symlink not supported under Win32")

(* Create a new directory, using the permissions from the given props        *)
let createDir fspath path props =
  Util.convertUnixErrorsToTransient
  "creating directory"
    (fun () ->
       let absolutePath = Fspath.concatToString fspath path in
       Unix.mkdir absolutePath (Props.perms props))

(*****************************************************************************)
(*                              FINGERPRINTS                                 *)
(*****************************************************************************)

(* NOTE: IF YOU CHANGE TYPE "FINGERPRINT", THE ARCHIVE FORMAT CHANGES;       *)
(* INCREMENT "UPDATE.ARCHIVEFORMAT"                                          *)
type fingerprint = string

(* Assumes that (fspath, path) is a file and gives its ``digest '', that is  *)
(* a short string of cryptographic quality representing it.                  *)
let fingerprint fspath path =
  Util.convertUnixErrorsToTransient
  "digesting file"
    (fun () ->
       let abspath = Fspath.concatToString fspath path in
       Digest.file abspath)

let int2hexa quartet =
  if quartet < 10 then
    (char_of_int ((int_of_char '0') + quartet))
  else char_of_int ((int_of_char 'a') + quartet - 10)

let hexaCode theChar =
  let intCode = int_of_char theChar in
  let first = intCode / 16 in
  let second = intCode mod 16 in
  (int2hexa first, int2hexa second)

let fingerprint2string md5 =
  let length = String.length md5 in
  let string = String.create (length * 2) in
  for i=0 to (length - 1) do
    let c1, c2 =  hexaCode (md5.[i]) in
    string.[2*i] <- c1;
    string.[2*i + 1] <- c2;
  done;
  string

let fingerprintString = Digest.string

(* FIX: not completely safe under Unix (with networked file system such as   *)
(* NFS)                                                                      *)
let safeFingerprint currfspath path info oldfingerprint =
  let rec retryLoop info count =
    if count = 0 then
      raise (Util.Transient
               (Printf.sprintf
                  "Failed to fingerprint file \"%s\": \
                   the file keeps on changing"
		  (Fspath.concatToString currfspath path)))
    else
      match Util.osType with
	`Win32 ->
	  (info, fingerprint currfspath path)
      | `Unix ->
	  let dig = fingerprint currfspath path in
	  let info' = Fileinfo.get true currfspath path in
	  if oldfingerprint<>None
              && Util.extractValueFromOption oldfingerprint = dig
	  then
            (info',dig)
	  else begin
        (* This only works for local filesystems... *)
            let t = Unix.time() in
            if Props.time info'.Fileinfo.desc = t then begin
              debug (fun() -> Util.msg
                  "File may have been modified during fingerprinting\n";
                Util.msg "  current time = %f, lastmod = %f"
                  t (Props.time info'.Fileinfo.desc);
                Util.msg "  retrying...\n");
              Unix.sleep 1;
              retryLoop info' (count - 1)
            end
	    else
              if not (Props.same_time info.Fileinfo.desc info'.Fileinfo.desc)
          || Fileinfo.stamp info <> Fileinfo.stamp info'
              then begin
		debug (fun() -> Util.msg
		    "  File may have been modified during fingerprinting: retry\n");
		retryLoop info' (count - 1)
              end else
		(info', dig)
	  end
  in
  retryLoop info 10  (* Maximum retries: 10 times *)

(*****************************************************************************)
(*                           UNISON DIRECTORY                                *)
(*****************************************************************************)

(* Gives the fspath of the archive directory on the machine, depending on    *)
(* which OS we use                                                           *)
let unisonDir =
  try Fspath.canonize (Some (Unix.getenv "UNISON"))
  with Not_found ->
    Fspath.canonize (Some (Util.fileInHomeDir (Printf.sprintf ".%s" Uutil.myName)))

(* build a fspath representing an archive child path whose name is given     *)
let fileInUnisonDir str =
  let n =
    try Name.fromString str
    with Invalid_argument _ ->
      raise (Util.Transient
               ("Ill-formed name of file in UNISON directory: "^str))
  in
    Fspath.child unisonDir n

(* Make sure archive directory exists                                        *)
let createUnisonDir() =
  try ignore (Fspath.stat unisonDir)
  with Unix.Unix_error(_) ->
    Util.convertUnixErrorsToFatal
      (Printf.sprintf "creating unison directory %s"
         (Fspath.toString unisonDir))
      (fun () ->
         ignore (Unix.mkdir (Fspath.toString unisonDir) 0o700))

(*****************************************************************************)
(*                           TEMPORARY FILES                                 *)
(*****************************************************************************)

(* Generates an unused fspath for a temporary file.                          *)
let freshPath fspath path prefix suffix =
  let rec f i =
    let tempPath =
      Path.addPrefixToFinalName 
	(Path.addSuffixToFinalName path (Printf.sprintf ".%d%s" i suffix))
	prefix
    in
    if exists fspath tempPath then f (i + 1) else tempPath
  in f 0

let tempPath fspath path = freshPath fspath path tempFilePrefix tempFileSuffix

let backupPath fspath path = freshPath fspath path "" backupFileSuffix

(*****************************************************************************)
(*                        PARENT VERIFICATION                                *)
(*****************************************************************************)

let isdir p =
  try
    (Fspath.stat p).Unix.st_kind = Unix.S_DIR
  with Unix.Unix_error _ -> false

let checkThatParentPathIsADir fspath path =
  if not (exists fspath path) then
    let (workingDir,realPath) = Fspath.findWorkingDir fspath path in
    if not (isdir workingDir) then
      raise (Util.Fatal (Printf.sprintf
                           "Path %s is not valid because %s is not a directory"
                           (Fspath.concatToString fspath path)
                           (Fspath.toString workingDir)))
