open Base
open Common
open Counterexamples
open Elim
open Lang
open Lwt
open Lwt.Syntax
open ProblemDefs
open Term
open SmtInterface
open Utils
module S = Smtlib.SmtLib

let placeholder_ctex (det : term_info) : ctex =
  { ctex_eqn =
      { eterm = det.term
      ; eprecond = det.current_preconds
      ; esplitter = None
      ; eelim = det.recurs_elim
      ; (* Placeholder values for elhs, erhs, these don't matter for us *)
        elhs = det.term
      ; erhs = det.term
      }
  ; ctex_vars = VarSet.of_list det.scalar_vars
  ; ctex_model = VarMap.empty
  ; ctex_stat = Unknown
  }
;;

(** Generates a set of smt equations that correspond to the recursion elimination. *)
let smt_of_recurs_elim_eqns ~(ctx : Context.t) (elim : (term * term) list) ~(p : PsiDef.t)
    : S.smtTerm
  =
  let lst =
    List.map
      ~f:(fun (t1, t2) ->
        S.mk_eq (smt_of_term ~ctx (mk_f_compose_r_orig ~ctx ~p t1)) (smt_of_term ~ctx t2))
      elim
  in
  if equal (List.length lst) 0 then S.mk_true else S.mk_assoc_and lst
;;

(** Returns a set of smt constraints that assert the know invariants on the functions in
    the problem. *)
let smt_of_ensures ~(fctx : PMRS.Functions.ctx) ~(ctx : Context.t) ~(p : PsiDef.t)
    : S.smtTerm list
  =
  let mk_sort maybe_rtype =
    match maybe_rtype with
    | None -> S.mk_int_sort
    | Some rtype -> SmtInterface.sort_of_rtype rtype
  in
  let pmrss : PMRS.t list =
    [ p.PsiDef.reference; p.PsiDef.target; p.PsiDef.reference ]
    @
    match p.tinv with
    | None -> []
    | Some tinv -> [ tinv ]
  in
  let vars : variable list =
    List.concat
      (List.map
         ~f:(fun (pmrs : PMRS.t) ->
           List.filter
             ~f:(fun v ->
               (not Variable.(v = pmrs.pmain_symb)) && not Variable.(v = pmrs.pvar))
             (Set.elements pmrs.pnon_terminals))
         pmrss)
  in
  List.fold
    ~init:[]
    ~f:(fun acc v ->
      let maybe_ens = Specifications.get_ensures ~ctx v in
      match maybe_ens with
      | None -> acc
      | Some t ->
        let arg_types = fst (RType.fun_typ_unpack (Variable.vtype_or_new ctx v)) in
        let arg_vs =
          List.map
            ~f:(fun t -> Variable.mk ctx ~t:(Some t) (Alpha.fresh ctx.names))
            arg_types
        in
        let args = List.map ~f:(mk_var ctx) arg_vs in
        let quants =
          List.map
            ~f:(fun var -> S.SSimple var.vname, mk_sort (Variable.vtype ctx var))
            arg_vs
        in
        let ens = Reduce.reduce_term ~fctx ~ctx (mk_app t [ mk_app_v ctx v args ]) in
        let smt = S.mk_forall quants (smt_of_term ~ctx ens) in
        smt :: acc)
    vars
;;

let smt_of_tinv_app ~(ctx : Context.t) ~(p : PsiDef.t) (det : term_info) =
  match p.tinv with
  | None -> failwith "No TInv has been specified. Cannot make smt of tinv app."
  | Some pmrs -> S.mk_simple_app pmrs.pvar.vname [ smt_of_term ~ctx det.term ]
;;

let smt_of_lemma_app (det : term_info) =
  S.mk_simple_app
    det.lemma.vname
    (List.map ~f:(fun var -> S.mk_var var.vname) det.scalar_vars)
;;

let smt_of_lemma_validity ~(ctx : Context.t) ~(p : PsiDef.t) (det : term_info) =
  let mk_sort maybe_rtype =
    match maybe_rtype with
    | None -> S.mk_int_sort
    | Some rtype -> SmtInterface.sort_of_rtype rtype
  in
  let quants =
    List.map
      ~f:(fun var -> S.SSimple var.vname, mk_sort (Variable.vtype ctx var))
      (Set.elements (Analysis.free_variables ~ctx det.term)
      @ List.concat_map
          ~f:(fun (_, b) -> Set.elements (Analysis.free_variables ~ctx b))
          det.recurs_elim)
  in
  let preconds =
    match det.current_preconds with
    | None -> []
    | Some pre -> [ smt_of_term ~ctx pre ]
  in
  let if_condition =
    S.mk_assoc_and
      ([ smt_of_tinv_app ~ctx ~p det; smt_of_recurs_elim_eqns ~ctx det.recurs_elim ~p ]
      @ preconds)
  in
  let if_then = smt_of_lemma_app det in
  [ S.mk_assert (S.mk_exists quants (S.mk_not (S.mk_or (S.mk_not if_condition) if_then)))
  ]
;;

let inductive_solver_preamble
    ~(fctx : PMRS.Functions.ctx)
    ~(ctx : Context.t)
    ~(p : PsiDef.t)
    solver
    (det : term_info)
  =
  let loc_smt_ = smt_of_pmrs ~fctx ~ctx in
  let preamble =
    Commands.mk_preamble
      ~logic:
        (SmtLogic.infer_logic
           ~ctx
           ~quantifier_free:false
           ~with_uninterpreted_functions:true
           ~for_induction:true
           ~logic_infos:(Common.ProblemDefs.PsiDef.logics p)
           [])
      ~incremental:false
      ~induction:true
      ~models:true
      ()
  in
  let lemma_body = det.lemma_candidate in
  match lemma_body with
  | Some lemma_body ->
    let%lwt () = AsyncSmt.exec_all solver preamble in
    let%lwt () =
      Lwt_list.iter_p
        (fun x ->
          let%lwt _ = AsyncSmt.exec_command solver x in
          return ())
        ((* Start by defining tinv. *)
         Option.(map ~f:loc_smt_ p.tinv |> value ~default:[])
        (* PMRS definitions.*)
        (* Reference function. *)
        @ loc_smt_ p.PsiDef.reference
        (* Representation function. *)
        @ (if p.PsiDef.repr_is_identity then [] else loc_smt_ p.PsiDef.repr)
        (* Assert invariants on functions *)
        @ List.map ~f:S.mk_assert (smt_of_ensures ~fctx ~ctx ~p)
        (* Declare lemmas. *)
        @ [ Commands.mk_def_fun
              ~ctx
              det.lemma.vname
              (List.map
                 ~f:(fun v -> v.vname, Variable.vtype_or_new ctx v)
                 det.scalar_vars)
              RType.TBool
              lemma_body
          ])
    in
    return ()
  | None ->
    (* Nothing to do! *)
    return ()
;;

let smt_of_disallow_ctex_values ~(ctx : Context.t) (det : term_info) : S.smtTerm =
  let ctexs = det.positive_ctexs in
  let of_one_ctex ctex =
    Map.fold
      ~f:(fun ~key ~data acc ->
        let var =
          let subs = subs_from_elim_to_elim ~ctx det.recurs_elim ctex.ctex_eqn.eelim in
          Term.substitution subs (mk_var ctx key)
        in
        smt_of_term ~ctx Terms.(var == data) :: acc)
      ~init:[]
      ctex.ctex_model
  in
  S.mk_assoc_and
    (List.map ~f:(fun ctex -> S.mk_not (S.mk_assoc_and (of_one_ctex ctex))) ctexs)
;;

let set_up_to_get_model ~(ctx : Context.t) ~(p : PsiDef.t) solver (det : term_info) =
  (* Step 1. Declare vars for term, and assert that term satisfies tinv. *)
  let%lwt () =
    AsyncSmt.exec_all
      solver
      (Commands.decls_of_vars ~ctx (Analysis.free_variables ~ctx det.term))
  in
  let%lwt _ = AsyncSmt.smt_assert solver (smt_of_tinv_app ~ctx ~p det) in
  (* Step 2. Declare scalars (vars for recursion elimination & spec param) and their constraints (preconds & recurs elim eqns) *)
  let%lwt () =
    AsyncSmt.exec_all
      solver
      (Commands.decls_of_vars ~ctx (VarSet.of_list det.scalar_vars))
  in
  let%lwt _ =
    AsyncSmt.exec_command
      solver
      (S.mk_assert (smt_of_recurs_elim_eqns ~ctx det.recurs_elim ~p))
  in
  let%lwt () =
    match det.current_preconds with
    | None -> return ()
    | Some pre -> AsyncSmt.smt_assert solver (smt_of_term ~ctx pre)
  in
  (* Step 3. Disallow repeated positive examples. *)
  let%lwt () =
    if List.length det.positive_ctexs > 0
    then AsyncSmt.smt_assert solver (smt_of_disallow_ctex_values ~ctx det)
    else return ()
  in
  (* Step 4. Assert that lemma candidate is false. *)
  AsyncSmt.smt_assert solver (S.mk_not (smt_of_lemma_app det))
;;

let mk_model_sat_asserts
    ~(fctx : PMRS.Functions.ctx)
    ~(ctx : Context.t)
    det
    f_o_r
    instantiate
  =
  let f v =
    let v_val =
      mk_var ctx (List.find_exn ~f:(fun x -> equal v.vid x.vid) det.scalar_vars)
    in
    match List.find_map ~f:(find_original_var_and_proj v) det.recurs_elim with
    | Some (original_recursion_var, proj) ->
      (match original_recursion_var.tkind with
      | TVar ov when Option.is_some (instantiate ov) ->
        let instantiation = Option.value_exn (instantiate ov) in
        if proj >= 0
        then (
          let t = Reduce.reduce_term ~fctx ~ctx (mk_sel ctx (f_o_r instantiation) proj) in
          smt_of_term ~ctx Terms.(t == v_val))
        else smt_of_term ~ctx Terms.(f_o_r instantiation == v_val)
      | _ ->
        Log.error_msg
          Fmt.(
            str "Warning: skipped instantiating %a." (pp_term ctx) original_recursion_var);
        S.mk_true)
    | None -> smt_of_term ~ctx Terms.(mk_var ctx v == v_val)
  in
  List.map ~f det.scalar_vars
;;

let verify_lemma_bounded
    ~(fctx : PMRS.Functions.ctx)
    ~(ctx : Context.t)
    ~(p : PsiDef.t)
    (det : term_info)
    : (Utils.Stats.verif_method * S.solver_response) Lwt.t * int Lwt.u
  =
  let logic =
    SmtLogic.infer_logic ~ctx ~logic_infos:(Common.ProblemDefs.PsiDef.logics p) []
  in
  let task (solver, starter) =
    let%lwt _ = starter in
    let%lwt () =
      AsyncSmt.exec_all
        solver
        Commands.(
          mk_preamble
            ~incremental:(String.is_prefix ~prefix:"CVC" solver.s_name)
            ~logic
            ()
          @ decls_of_vars ~ctx (VarSet.of_list det.scalar_vars))
    in
    let steps = ref 0 in
    let rec check_bounded_sol accum terms =
      let f accum t =
        let rec_instantation =
          Option.value ~default:VarMap.empty (Matching.matches ~ctx t ~pattern:det.term)
        in
        let%lwt _ = accum in
        let f_compose_r t =
          let repr_of_v =
            if p.PsiDef.repr_is_identity
            then t
            else Reduce.reduce_pmrs ~fctx ~ctx p.PsiDef.repr t
          in
          Reduce.reduce_term
            ~fctx
            ~ctx
            (Reduce.reduce_pmrs ~fctx ~ctx p.PsiDef.reference repr_of_v)
        in
        let subs =
          List.map
            ~f:(fun (orig_rec_var, elimv) ->
              match orig_rec_var.tkind with
              | TVar rec_var when Map.mem rec_instantation rec_var ->
                elimv, f_compose_r (Map.find_exn rec_instantation rec_var)
              | _ -> failwith "all elimination variables should be substituted.")
            det.recurs_elim
          (* Map.fold ~init:[] ~f:(fun ~key ~data acc -> (mk_var key, data) :: acc) rec_instantation *)
        in
        let preconds =
          Option.to_list
            (Option.map ~f:(fun t -> substitution subs t) det.current_preconds)
        in
        let model_sat =
          mk_model_sat_asserts ~fctx ~ctx det f_compose_r (Map.find rec_instantation)
        in
        let%lwt () = AsyncSmt.spush solver in
        (* Assert that preconditions hold and map original term's recurs elim variables to the variables that they reduce to for this concrete term. *)
        let%lwt _ =
          AsyncSmt.exec_all
            solver
            (Commands.decls_of_vars
               ~ctx
               (List.fold
                  ~init:VarSet.empty
                  ~f:(fun acc t -> Set.union acc (Analysis.free_variables ~ctx t))
                  (preconds @ Map.data rec_instantation)))
        in
        let%lwt () =
          AsyncSmt.smt_assert
            solver
            (S.mk_assoc_and (List.map ~f:(smt_of_term ~ctx) preconds @ model_sat))
        in
        (* Assert that TInv is true for this concrete term t *)
        let%lwt _ =
          match p.tinv with
          | None -> return ()
          | Some tinv ->
            let tinv_t = Reduce.reduce_pmrs ~fctx ~ctx tinv t in
            let%lwt _ =
              AsyncSmt.exec_all
                solver
                (Commands.decls_of_vars ~ctx (Analysis.free_variables ~ctx tinv_t))
            in
            let%lwt _ = AsyncSmt.smt_assert solver (smt_of_term ~ctx tinv_t) in
            return ()
        in
        (* Assert that lemma is false for this concrete term t  *)
        let%lwt _ =
          match det.lemma_candidate with
          | Some lemma ->
            AsyncSmt.exec_command
              solver
              (S.mk_assert (S.mk_not (smt_of_term ~ctx (substitution subs lemma))))
          | _ -> return S.Unknown
        in
        let%lwt resp = AsyncSmt.check_sat solver in
        (* Note that I am getting a model after check-sat unknown response. This may not halt.  *)
        let%lwt result =
          match resp with
          | S.Sat | S.Unknown ->
            let%lwt model = AsyncSmt.get_model solver in
            return (Some model)
          | _ -> return None
        in
        let%lwt () = AsyncSmt.spop solver in
        return (resp, result)
      in
      match terms with
      | [] -> accum
      | t0 :: tl ->
        let%lwt accum' = f accum t0 in
        (match accum' with
        | status, Some model -> return (status, Some model)
        | _ -> check_bounded_sol (return accum') tl)
    in
    let rec expand_loop u =
      match Set.min_elt u, !steps < !Config.Optims.num_expansions_check with
      | Some t0, true ->
        let tset, u' = Expand.simple ~ctx t0 in
        let%lwt check_result =
          check_bounded_sol (return (S.Unknown, None)) (Set.elements tset)
        in
        steps := !steps + Set.length tset;
        (match check_result with
        | _, Some model ->
          Log.debug_msg
            "Bounded lemma verification has found a counterexample to the lemma \
             candidate.";
          return model
        | _ -> expand_loop (Set.union (Set.remove u t0) u'))
      | None, true ->
        (* All expansions have been checked. *)
        return S.Unsat
      | _, false ->
        (* Check reached limit. *)
        Log.debug_msg "Bounded lemma verification has reached limit.";
        if !Config.bounded_lemma_check then return S.Unsat else return S.Unknown
    in
    let* res = expand_loop (TermSet.singleton det.term) in
    let* () = AsyncSmt.close_solver solver in
    return (Utils.Stats.BoundedChecking, res)
  in
  AsyncSmt.(cancellable_task (make_solver "z3") task)
;;

let verify_lemma_unbounded
    ~(fctx : PMRS.Functions.ctx)
    ~(ctx : Context.t)
    ~(p : PsiDef.t)
    (det : term_info)
    : (Utils.Stats.verif_method * S.solver_response) Lwt.t * int Lwt.u
  =
  let build_task (cvc4_instance, task_start) =
    let%lwt _ = task_start in
    let%lwt () = inductive_solver_preamble cvc4_instance ~fctx ~ctx ~p det in
    let%lwt () =
      (Lwt_list.iter_p (fun x ->
           let%lwt _ = AsyncSmt.exec_command cvc4_instance x in
           return ()))
        (smt_of_lemma_validity ~ctx ~p det)
    in
    let%lwt resp = AsyncSmt.check_sat cvc4_instance in
    let%lwt final_response =
      match resp with
      | Sat | Unknown ->
        let%lwt _ = set_up_to_get_model cvc4_instance ~ctx ~p det in
        let%lwt resp' = AsyncSmt.check_sat cvc4_instance in
        (match resp' with
        | Sat | Unknown -> AsyncSmt.get_model cvc4_instance
        | _ -> return resp')
      | _ -> return resp
    in
    let%lwt () = AsyncSmt.close_solver cvc4_instance in
    Log.debug_msg "Unbounded lemma verification is complete.";
    return (Utils.Stats.Induction, final_response)
  in
  AsyncSmt.(cancellable_task (AsyncSmt.make_solver "cvc") build_task)
;;

(** Verify a lemma candidate with two parallel calls: one call to an induction solver,
  another call to a SMT solver. The induction solver attempts to prove that the solution
  is correct while the smt solver attempt to find a counterexample.
*)
let verify_lemma_candidate
    ~(fctx : PMRS.Functions.ctx)
    ~(ctx : Context.t)
    ~(p : PsiDef.t)
    (det : term_info)
    : Utils.Stats.verif_method * SyncSmt.solver_response
  =
  match det.lemma_candidate with
  | None -> failwith "Cannot verify lemma candidate; there is none."
  | Some _ ->
    Log.verbose (fun f () -> Fmt.(pf f "Checking lemma candidate..."));
    let resp =
      try
        Lwt_main.run
          (let pr1, resolver1 = verify_lemma_bounded ~fctx ~ctx ~p det in
           let pr2, resolver2 = verify_lemma_unbounded ~fctx ~ctx ~p det in
           Lwt.wakeup resolver2 1;
           Lwt.wakeup resolver1 1;
           (* The first call to return is kept, the other one is ignored. *)
           Lwt.pick [ pr1; pr2 ])
      with
      | End_of_file ->
        Log.error_msg "Solvers terminated unexpectedly  ⚠️ .";
        Log.error_msg "Please inspect logs.";
        BoundedChecking, S.Unknown
    in
    resp
;;