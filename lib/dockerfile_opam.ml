(*
 * Copyright (c) 2015 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

(** OPAM-specific Dockerfile rules *)

open Dockerfile
open Printf

(** Rules to get the cloud solver if no aspcud available *)
let install_cloud_solver =
  run "curl -o /usr/bin/aspcud 'http://cvsweb.openbsd.org/cgi-bin/cvsweb/~checkout~/ports/sysutils/opam/files/aspcud?rev=1.1&content-type=text/plain'" @@
  run "chmod 755 /usr/bin/aspcud"

(** RPM rules *)
module RPM = struct

  let install_base_packages =
    Linux.RPM.dev_packages ()

  let install_system_ocaml =
    Linux.RPM.install "ocaml ocaml-camlp4-devel ocaml-ocamldoc"

  let install_system_opam = function
  | `CentOS7 -> Linux.RPM.install "opam aspcud"
  | `CentOS6 -> Linux.RPM.install "opam" @@ install_cloud_solver
end

(** Debian rules *)
module Apt = struct

  let install_base_packages =
    Linux.Apt.update @@
    Linux.Apt.install "sudo pkg-config git build-essential m4 software-properties-common unzip curl libx11-dev"

  let install_system_ocaml =
    Linux.Apt.install "ocaml ocaml-native-compilers camlp4-extra"

  let install_system_opam =
    Linux.Apt.install "opam aspcud"
end

let run_as_opam fmt = Linux.run_as_user "opam" fmt
let opamhome = "/home/opam"

let opam_init
  ?(repo="git://github.com/ocaml/opam-repository")
  ?compiler_version () =
    let compiler = match compiler_version with
      | None -> ""
      | Some v -> "--comp " ^ v ^ " " in
    run_as_opam "git clone %s" repo @@
    run_as_opam "opam init -a -y %s%s/opam-repository" compiler opamhome @@
    maybe (fun _ -> run_as_opam "opam install -y camlp4") compiler_version

let install_opam_from_source ?prefix ?(branch="1.2") () =
  run "git clone -b %s git://github.com/ocaml/opam /tmp/opam" branch @@
  Linux.run_sh "cd /tmp/opam && make cold && make%s install && rm -rf /tmp/opam"
    (match prefix with None -> "" |Some p -> " prefix=\""^p^"\"")

let header ?maintainer img tag =
  let maintainer = match maintainer with None -> empty | Some t -> Dockerfile.maintainer "%s" t in
  comment "Autogenerated by OCaml-Dockerfile scripts" @@
  from ~tag img @@
  maintainer

let run_command fmt =
  ksprintf (fun cmd -> 
    eprintf "Exec: %s\n%!" cmd;
    match Sys.command cmd with
    | 0 -> ()
    | _ -> raise (Failure cmd)
  ) fmt

let write_to_file file dfile =
  eprintf "Open: %s\n%!" file;
  let fout = open_out file in
  output_string fout (string_of_t dfile);
  close_out fout

let generate_dockerfiles d output_dir =
  List.iter (fun (name, docker) ->
    printf "Generating: %s/%s/Dockerfile\n" output_dir name;
    run_command "mkdir -p %s/%s" output_dir name;
    write_to_file (output_dir ^ "/" ^ name ^ "/Dockerfile") docker
  ) d

let generate_dockerfiles_in_git_branches d output_dir =
  List.iter (fun (name, docker) ->
    printf "Switching to branch %s in %s\n" name output_dir;
    run_command "git -C \"%s\" checkout -q -B %s master" output_dir name;
    let file = output_dir ^ "/Dockerfile" in
    write_to_file file docker;
    run_command "git -C \"%s\" add Dockerfile" output_dir;
    run_command "git -C \"%s\" commit -q -m \"update %s Dockerfile\" -a" output_dir name
  ) d;
  run_command "git -C \"%s\" checkout -q master" output_dir
