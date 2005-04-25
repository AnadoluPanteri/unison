(* $I1: Unison file synchronizer: src/copy.ml $ *)
(* $I2: Last modified by vouillon on Wed, 01 Sep 2004 07:35:22 -0400 $ *)
(* $I3: Copyright 1999-2004 (see COPYING for details) $ *)

let (>>=) = Lwt.bind

let debug = Trace.debug "copy"

(****)

let openFileIn fspath path kind =
  match kind with
    `DATA   -> Unix.openfile (Fspath.concatToString fspath path)
                 [Unix.O_RDONLY] 0o444
  | `RESS _ -> Osx.openRessIn fspath path

let openFileOut fspath path kind =
  match kind with
    `DATA     -> Unix.openfile (Fspath.concatToString fspath path)
                   [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600
  | `RESS len -> Osx.openRessOut fspath path len

let protect f g =
  try
    f ()
  with Sys_error _ | Unix.Unix_error _ | Util.Transient _ as e ->
    begin try g () with Sys_error _  | Unix.Unix_error _ -> () end;
    raise e

let lwt_protect f g =
  Lwt.catch f
    (fun e ->
       begin match e with
         Sys_error _ | Unix.Unix_error _ | Util.Transient _ ->
           begin try g () with Sys_error _  | Unix.Unix_error _ -> () end
       | _ ->
           ()
       end;
       Lwt.fail e)

(****)

let localFile
     fspathFrom pathFrom fspathTo pathTo realPathTo update desc ressLength id =
  Util.convertUnixErrorsToTransient
    "copying locally"
    (fun () ->
       Uutil.showProgress id Uutil.Filesize.zero "l";
       debug (fun () ->
         Util.msg "copylocal (%s,%s) to (%s, %s)\n"
           (Fspath.toString fspathFrom) (Path.toString pathFrom)
           (Fspath.toString fspathTo) (Path.toString pathTo));
       let inFd = openFileIn fspathFrom pathFrom `DATA in
       protect (fun () ->
         let outFd = openFileOut fspathTo pathTo `DATA in
         protect (fun () ->
           Uutil.readWrite inFd outFd
             (fun l -> Uutil.showProgress id (Uutil.Filesize.ofInt l) "l"))
           (fun () -> Unix.close outFd);
         Unix.close outFd)
         (fun () -> Unix.close inFd);
       Unix.close inFd;
       if ressLength > Uutil.Filesize.zero then begin
         let inFd = openFileIn fspathFrom pathFrom (`RESS ressLength) in
         protect (fun () ->
           let outFd = openFileOut fspathTo pathTo (`RESS ressLength) in
           protect (fun () ->
             Uutil.readWriteBounded inFd outFd ressLength
               (fun l -> Uutil.showProgress id (Uutil.Filesize.ofInt l) "l"))
             (fun () -> Unix.close outFd);
             Unix.close outFd)
           (fun () -> Unix.close inFd);
         Unix.close inFd;
       end;
       match update with
         `Update _ ->
           Fileinfo.set fspathTo pathTo (`Copy realPathTo) desc
       | `Copy ->
           Fileinfo.set fspathTo pathTo (`Set Props.fileDefault) desc)

(****)

(* The file transfer functions here depend on an external module
   'transfer' that implements a generic transmission and the rsync
   algorithm for optimizing the file transfer in the case where a
   similar file already exists on the target. *)

(* BCPFIX: This preference is probably not needed any more. *)
let rsyncActivated =
  Prefs.createBool "rsync" true
    "activate the rsync transfer mode"
    ("Unison uses the 'rsync algorithm' for 'diffs-only' transfer "
     ^ "of updates to large files.  Setting this flag to false makes Unison "
     ^ "use whole-file transfers instead.  Under normal circumstances, "
     ^ "there is no reason to do this, but if you are having trouble with "
     ^ "repeated 'rsync failure' errors, setting it to "
     ^ "false should permit you to synchronize the offending files.")

(* Lazy creation of the destination file *)
let destinationFd fspath path kind outfd =
  match !outfd with
    None    ->
      let fd = openFileOut fspath path kind in
      outfd := Some fd;
      fd
  | Some fd ->
      fd

let decompressor = ref Remote.MsgIdMap.empty

let startReceivingFile
      fspath path realPath fileKind update srcFileSize id file_id =
  debug (fun() ->
    Util.msg "startReceivingFile: %s\n" (Fspath.concatToString fspath path));
  (* We delay the opening of the file so that there are not too many
     temporary files remaining after a crash *)
  let outfd = ref None in
  let showProgress count =
    Uutil.showProgress id (Uutil.Filesize.ofInt count) "r" in
  (* Install a simple generic decompressor *)
  decompressor :=
    Remote.MsgIdMap.add file_id
      (fun ti ->
         let fd = destinationFd fspath path fileKind outfd in
         Transfer.receive fd showProgress ti)
      !decompressor;
  if Prefs.read rsyncActivated then begin
    match update with
      `Update (destFileDataSize, destFileRessSize) when
          let destFileSize =
            match fileKind with
              `DATA   -> destFileDataSize
            | `RESS _ -> destFileRessSize
          in
          Transfer.Rsync.aboveRsyncThreshold destFileSize
            &&
          Transfer.Rsync.aboveRsyncThreshold srcFileSize ->
        let infd = openFileIn fspath realPath fileKind in
        (* Now that we've successfully opened the original version
           of the file, install a more interesting decompressor *)
        decompressor :=
          Remote.MsgIdMap.add file_id
            (fun ti ->
               let fd = destinationFd fspath path fileKind outfd in
               Transfer.Rsync.rsyncDecompress infd fd showProgress ti)
            !decompressor;
        let bi =
          protect (fun () -> Transfer.Rsync.rsyncPreprocess infd)
            (fun () -> Unix.close infd)
        in
        Lwt.return (outfd, ref (Some infd), Some bi)
    | _ ->
        Lwt.return (outfd, ref None, None)
  end else
    Lwt.return (outfd, ref None, None)

let processTransferInstruction conn (file_id, ti) =
  Util.convertUnixErrorsToTransient
    "processTransferInstruction"
    (fun () ->
       ignore (Remote.MsgIdMap.find file_id !decompressor ti));
  Lwt.return ()

let marshalTransferInstruction =
  (fun (file_id, (data, pos, len)) rem ->
     ((Remote.encodeInt file_id, 0, 4) :: (data, pos, len) :: rem, len + 4)),
  (fun buf pos ->
     let len = String.length buf - pos - 4 in
     (Remote.decodeInt (String.sub buf pos 4), (buf, pos + 4, len)))

let processTransferInstructionRemotely =
  Remote.registerSpecialServerCmd
    "processTransferInstruction" marshalTransferInstruction
    Remote.defaultMarshalingFunctions processTransferInstruction

let compress conn
     (biOpt, fspathFrom, pathFrom, fileKind, sizeFrom, id, file_id) =
  Lwt.catch
    (fun () ->
       let infd = openFileIn fspathFrom pathFrom fileKind in
       lwt_protect (fun () ->
         let showProgress count =
           Uutil.showProgress id (Uutil.Filesize.ofInt count) "r" in
         let compr =
           match biOpt with
             None     -> Transfer.send infd sizeFrom showProgress
           | Some bi  -> Transfer.Rsync.rsyncCompress
                           bi infd sizeFrom showProgress
         in
         compr
           (fun ti -> processTransferInstructionRemotely conn (file_id, ti))
               >>= (fun () ->
         Unix.close infd;
         Lwt.return ()))
       (fun () ->
          Unix.close infd))
    (fun e ->
       Util.convertUnixErrorsToTransient
         "rsyncSender" (fun () -> raise e))

let compressRemotely = Remote.registerServerCmd "compress" compress

(****)

let fileSize (fspath, path) =
  Util.convertUnixErrorsToTransient
    "fileSize"
    (fun () ->
       Lwt.return
        (Props.length (Fileinfo.get false fspath path).Fileinfo.desc))

let fileSizeOnHost =
  Remote.registerServerCmd  "fileSize" (fun _ -> fileSize)

(****)

(* We limit the size of the output buffers to about 512 KB
   (we cannot go above the limit below plus 64) *)
let transmitFileReg = Lwt_util.make_region 440

let bufferSize sz =
  min 64 ((truncate (Uutil.Filesize.toFloat sz) + 1023) / 1024)
    (* Token queue *)
    +
  8 (* Read buffer *)

(****)

let close_all infd outfd =
  begin match !infd with
    Some fd -> infd := None; Unix.close fd
  | None    -> ()
  end;
  begin match !outfd with
    Some fd -> outfd := None; Unix.close fd
  | None    -> ()
  end

let close_all_no_error infd outfd =
  try
    close_all infd outfd
  with Unix.Unix_error _ ->
    ()

let reallyTransmitFile
    connFrom fspathFrom pathFrom fspathTo pathTo realPathTo
    update desc ressLength id =
  debug (fun() -> Util.msg "getFile(%s,%s) -> (%s,%s,%s,%s)\n"
      (Fspath.toString fspathFrom) (Path.toString pathFrom)
      (Fspath.toString fspathTo) (Path.toString pathTo)
      (Path.toString realPathTo) (Props.toString desc));

  let srcFileSize = Props.length desc in
  debug (fun () ->
    Util.msg "src file size = %s bytes\n"
      (Uutil.Filesize.toString srcFileSize));
  let file_id = Remote.newMsgId () in
  (* Data fork *)
  startReceivingFile
    fspathTo pathTo realPathTo `DATA update srcFileSize id file_id
    >>= (fun (outfd, infd, bi) ->
  Lwt.catch (fun () ->
    Lwt_util.run_in_region transmitFileReg (bufferSize srcFileSize) (fun () ->
      Uutil.showProgress id Uutil.Filesize.zero "f";
      compressRemotely connFrom
        (bi, fspathFrom, pathFrom, `DATA, srcFileSize, id, file_id))
            >>= (fun () ->
    decompressor :=
      Remote.MsgIdMap.remove file_id !decompressor; (* For GC *)
    close_all infd outfd;
    Lwt.return ()))
    (fun e ->
       decompressor :=
         Remote.MsgIdMap.remove file_id !decompressor; (* For GC *)
       close_all_no_error infd outfd;
       Lwt.fail e) >>= (fun () ->
  (* Ressource fork *)
  if ressLength > Uutil.Filesize.zero then begin
    startReceivingFile
      fspathTo pathTo realPathTo
      (`RESS ressLength) update ressLength id file_id
        >>= (fun (outfd, infd, bi) ->
    Lwt.catch (fun () ->
      Lwt_util.run_in_region transmitFileReg (bufferSize ressLength) (fun () ->
        Uutil.showProgress id Uutil.Filesize.zero "f";
        compressRemotely connFrom
          (bi, fspathFrom, pathFrom,
           `RESS ressLength, ressLength, id, file_id))
              >>= (fun () ->
        decompressor :=
          Remote.MsgIdMap.remove file_id !decompressor; (* For GC *)
        close_all infd outfd;
        Lwt.return ()))
    (fun e ->
       decompressor :=
         Remote.MsgIdMap.remove file_id !decompressor; (* For GC *)
       close_all_no_error infd outfd;
       Lwt.fail e))
  end else
    Lwt.return ()) >>= (fun () ->
  begin match update with
    `Update _ -> Fileinfo.set fspathTo pathTo (`Copy realPathTo) desc
  | `Copy     -> Fileinfo.set fspathTo pathTo (`Set Props.fileDefault) desc
  end;
  Lwt.return ()))

(****)

let tryCopyMovedFile fspathTo pathTo realPathTo update desc fp ress id =
  Prefs.read Xferhint.xferbycopying
    &&
  begin
    debug (fun () -> Util.msg "tryCopyMovedFile: -> %s /%s/\n"
      (Path.toString pathTo) (Os.fullfingerprint_to_string fp));
    match Xferhint.lookup fp with
      None ->
        false
    | Some (candidateFspath, candidatePath) ->
        debug (fun () ->
          Util.msg
            "tryCopyMovedFile: found match at %s,%s. Try local copying\n"
            (Fspath.toString candidateFspath)
            (Path.toString candidatePath));
        try
          localFile
            candidateFspath candidatePath fspathTo pathTo realPathTo
            update desc (Osx.ressLength ress) id;
          let info = Fileinfo.get false fspathTo pathTo in
          let fp' = Os.fingerprint fspathTo pathTo info in
          if fp' = fp then begin
            debug (fun () -> Util.msg "tryCopyMoveFile: success.\n");
            Xferhint.insertEntry (fspathTo, pathTo) fp;
            true
          end else begin
            debug (fun () ->
              Util.msg "tryCopyMoveFile: candidate file modified!");
            Xferhint.deleteEntry (candidateFspath, candidatePath);
            Os.delete fspathTo pathTo;
            false
          end
        with
          Util.Transient s ->
            debug (fun () ->
              Util.msg "tryCopyMovedFile: failed local copy [%s]" s);
            Xferhint.deleteEntry (candidateFspath, candidatePath);
            Os.delete fspathTo pathTo;
            false
  end

let transmitFileLocal
  connFrom
  (fspathFrom, pathFrom, fspathTo, pathTo, realPathTo,
   update, desc, fp, ress, id) =
  if
    tryCopyMovedFile
      fspathTo pathTo realPathTo update desc fp ress id
  then
    Lwt.return ()
  else
    reallyTransmitFile
      connFrom fspathFrom pathFrom fspathTo pathTo realPathTo
      update desc (Osx.ressLength ress) id

let transmitFileOnRoot =
  Remote.registerRootCmdWithConnection "transmitFile" transmitFileLocal

let transmitFile
    rootFrom pathFrom rootTo fspathTo pathTo realPathTo
    update desc fp ress id =
  transmitFileOnRoot rootTo rootFrom
    (snd rootFrom, pathFrom, fspathTo, pathTo, realPathTo,
     update, desc, fp, ress, id)

(****)

let file
      rootFrom pathFrom rootTo fspathTo pathTo realPathTo
      update desc fp ress id =
  debug (fun() -> Util.msg "copyRegFile(%s,%s) -> (%s,%s,%s,%s,%s)\n"
      (Common.root2string rootFrom) (Path.toString pathFrom)
      (Common.root2string rootTo) (Path.toString realPathTo)
      (Fspath.toString fspathTo) (Path.toString pathTo)
      (Props.toString desc));
  let timer = Trace.startTimer "Transmitting file" in
  begin match rootFrom, rootTo with
    (Common.Local, fspathFrom), (Common.Local, realFspathTo) ->
      localFile
        fspathFrom pathFrom fspathTo pathTo realPathTo
        update desc (Osx.ressLength ress) id;
      Lwt.return ()
  | _ ->
      transmitFile
        rootFrom pathFrom rootTo fspathTo pathTo realPathTo
        update desc fp ress id
  end >>= (fun () ->
  Trace.showTimer timer;
  Lwt.return ())