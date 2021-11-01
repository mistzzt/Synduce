open Lang
open Base
open Fmt
open Parsers
open Utils

let parse_only = ref false

let print_usage () =
  pf stdout "Usage : Synduce [options] input_file@.";
  pf
    stdout
    "Options:\n\
    \    -h --help                      Print this message.\n\
    \    -d --debug                     Print debugging info.\n\
    \    -v --verbose                   Print verbose.\n\
    \    -m --style-math                Print math-style.\n\
    \    -i --info-off                  Print timing information only.\n\
    \    -o --output=PATH               Output solution in folder PATH.\n\
    \       --fuzzing=NUM               Fuzz SMT solutions on some problems.(Default=0, \
     no fuzzing).\n\
    \  Otimizations off/on:\n\
    \    -s --no-splitting              Do not split systems into subsystems.\n\
    \       --no-syndef                 Do not use syntactic definitions.\n\
    \    -t --no-detupling              Turn off detupling.\n\
    \    -c --simple-init               Initialize T naively.\n\
    \       --acegis                    Use the Abstract CEGIS algorithm. Turns bmc on.\n\
    \       --ccegis                    Use the Concrete CEGIS algorithm. Turns bmc on.\n\
    \       --no-assumptions            Don't  partial correctness assumptions.\n\
    \       --no-simplify               Don't simplify equations with partial evaluation.\n\
    \       --no-gropt                  Don't optimize grammars (level 0)\n\
    \       --set-gropt=NUM             Set grammar optimization level (NUM=0,1 or 2)\n\
    \       --no-lifting                Don't attempt lifting.\n\
    \       --max-lifting=NUM           Set how many times Synduce attempts to lift.\n\
    \    -u --no-check-unrealizable     Do not check if synthesis problems are \
     functionally realizable.\n\
    \       --sysfe-opt-off             Turn off optimizations to solve systems of \
     equations in parallel\n\
    \  Bounded checking:\n\
    \       --use-bmc                   Use acegis bounded model checking (bmc mode).\n\
    \    -b --bmc=MAX_DEPTH             Maximum depth of terms for bounded model \
     checking, in bmc mode.\n\
    \    -n --verification=NUM          Number of expand calls for bounded model \
     checking, in opt mode.\n\
    \  Background solver parameters:\n\
    \       --ind-tlimit=TIMEOUT        Set the solver to timeout after TIMEOUT ms when \
     doing an induction proof.\n\
    \       --cvc4                      Use CVC4 instead of CVC5 if both are available.\n\
    \       --cvc5                      Always use CVC5 instead of CVC4 if both are \
     available.\n\
    \       --verif-with=SOLVER         Don't use z3 for verification, use SOLVER \
     (=z3,cvc4,cvc5,yices)\n\
    \  Debugging:\n\
    \  -I   --interactive               Request additional lemmas interactively.\n\
    \  -J   --interactive-lifting       Request expressions for lifting.\n\
    \  -L   --interactive-loop          Request lemmas interactively in a loop.\n\
    \  -X   --classify-ctex             Manually classify ctex as pos or neg.\n\
    \  -N   --no-sat-as-unsat           No sat found in bounded checking is accepted as \
     unsat.\n\
    \  -B   --bounded-lemma-check       Use depth-bounded check to verify lemma \
     candidates and generate positive examples for lemma synth.\n\
    \  -C   --interactive-check-lemma   Manually set if a lemma is true and, if not, \
     give counterexample.\n\
    \       --parse-only                Just parse the input.\n\
    \       --show-vars                 Print variables and their types at the end.\n\
    \       --generate-benchmarks=DIR   Save SyGuS problems in DIR, including problems \
     that are provably unrealizable.\n\
    \       --generate-proof=FILE       Save a Dafny proof skeleton in file \
     (experimental).\n\
    \       --check-smt-unrealizable    Check unrealizability using a SMT query directly.\n\
    \     -> Try:\n\
     ./Synduce benchmarks/list/mps.ml@.";
  Caml.exit 0
;;

let main () =
  let filename = ref None in
  let options = Config.options print_usage parse_only in
  Getopt.parse_cmdline options (fun s -> filename := Some s);
  let filename =
    match !filename with
    | Some f -> ref f
    | None -> print_usage ()
  in
  Config.problem_name := Caml.Filename.basename (Caml.Filename.chop_extension !filename);
  set_style_renderer stdout `Ansi_tty;
  Caml.Format.set_margin 100;
  (match !SygusInterface.SygusSolver.default_solver with
  | CVC ->
    Utils.Log.debug_msg
      (if Config.using_cvc5 ()
      then "Using CVC5 ✔"
      else "Using CVC4. Please install CVC5.")
  | EUSolver -> failwith "EUSolver unsupported."
  | DryadSynth -> Syguslib.Sygus.use_v1 := true);
  Lib.Utils.Stats.glob_start ();
  (* Parse input file. *)
  let is_ocaml_syntax = Caml.Filename.check_suffix !filename ".ml" in
  let prog, psi_comps =
    if is_ocaml_syntax then parse_ocaml !filename else parse_pmrs !filename
  in
  (* Populate types.  *)
  let _ = seek_types prog in
  (* Translate the Caml or PRMS file into pmrs representation. *)
  let all_pmrs =
    try translate prog with
    | e ->
      if !Config.show_vars then Term.Variable.print_summary stdout ();
      raise e
  in
  if !parse_only then Caml.exit 1;
  (* Solve the problem proper. *)
  (match Algo.Refinement.solve_problem psi_comps all_pmrs with
  | pb, Ok soln -> ToolMessages.on_success ~is_ocaml_syntax filename pb soln
  | _, Error _ -> Utils.Log.error_msg "No solution found.");
  if !Config.show_vars then Term.Variable.print_summary stdout ()
;;

main ()
