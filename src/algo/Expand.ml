open Base
open Either
open Lang
open Lang.Term
open AState
open Utils



let identify_rcalls (p : psi_def) (lam : variable) (t : term) : VarSet.t =
  let join = Set.union in
  let case _ t =
    match t.tkind with
    (* lam x *)
    | TApp({tkind = TVar lam';_}, [single_arg]) when Variable.(lam' = lam) ->
      (match single_arg.tkind with
       | TVar x -> Some (VarSet.singleton x)
       | TApp({tkind = TVar repr; _}, [{tkind = TVar x; _}]) ->
         if Variable.equal repr p.repr.pmain_symb then
           Some (VarSet.singleton x)
         else None
       | _ -> None)
    | _ -> None
  in
  reduce ~init:VarSet.empty ~case ~join t


let subst_recursive_calls (p : psi_def) (tl : term list) : (term * term) list =
  let fsymb = p.orig.pmain_symb and  gsymb = p.target.pmain_symb in
  let rcalls =
    let fold_f rcalled_vars t =
      let f_x = identify_rcalls p fsymb t in
      let g_x = identify_rcalls p gsymb t in
      VarSet.union_list [rcalled_vars; f_x; g_x]
    in
    List.fold ~init:VarSet.empty ~f:fold_f tl
  in
  let f var =
    let scalar_term = mk_composite_scalar !AState._alpha in
    [mk_app (mk_var fsymb) [mk_var var], scalar_term;
     mk_app (mk_var gsymb) [mk_var var], scalar_term;
     mk_app (mk_var fsymb) [mk_app (mk_var p.repr.pmain_symb) [mk_var var]], scalar_term]
  in
  List.concat (List.map ~f (Set.elements rcalls))


let subst_repr_calls (p : psi_def) (tl : term list) : (term * term) list =
  let fsymb = p.repr.pmain_symb in
  let rcalls =
    let fold_f rcalled_vars t =
      Set.union rcalled_vars (identify_rcalls p fsymb t)
    in
    List.fold ~init:VarSet.empty ~f:fold_f tl
  in
  let f var =
    let rtype_var = Variable.mk  ~t:(Some !AState._tau) (Alpha.fresh "x") in
    [mk_app (mk_var fsymb) [mk_var var], mk_var rtype_var]
  in
  List.concat (List.map ~f (Set.elements rcalls))


let maximally_reduced_app (p : psi_def) (func : term) (args : term list) : bool =
  (match func.tkind with
   | TVar x ->
     Variable.(x = p.orig.pmain_symb || x = p.target.pmain_symb || x = p.repr.pmain_symb)
   | _ -> false)
  &&
  (List.for_all args ~f:(fun x -> match x.tkind with TVar _ -> true | _ -> false))


let nonreduced_terms (p : psi_def) (non_terms : VarSet.t) (t : term)
  : (variable * term list) list =
  let join = (@) in
  let case _ t =
    match t.tkind with
    | TApp(func, args) ->
      (match func.tkind with
       | TVar func_var when Set.mem non_terms func_var ->
         if maximally_reduced_app p func args then None
         else Some [func_var, args]
       | _ -> None)
    | _ -> None
  in
  let init = [] in
  reduce ~init ~join ~case t


let nonreduced_terms_all (p : psi_def) (t : term) =
  let all_nont =
    VarSet.union_list [p.orig.pnon_terminals; p.target.pnon_terminals; p.orig.pnon_terminals]
  in
  nonreduced_terms p all_nont t


let replace_rhs_of_main (p : psi_def) (f : PMRS.t) (t0 : term) : term =
  let nr = nonreduced_terms p f.pnon_terminals t0 in
  let rule_set =
    Map.filter  f.prules ~f:(fun (nt, _, _, _) -> Variable.(nt = f.pmain_symb))
  in
  let replacements =
    let f (nt, args) =
      match Map.max_elt (PMRS.inverted_rule_lookup rule_set (mk_var nt) args) with
      | Some (_, lhs) -> Some (mk_app (mk_var nt) args, lhs)
      | None -> None
    in
    List.filter_map ~f:(fun x -> x) (List.map ~f nr)
  in
  substitution replacements t0


let expand_max (p : psi_def) (f : PMRS.t) (t0 : term)
  : (term * term) list * term list =
  let f_of_t0 = PMRS.reduce f t0 in
  let simpl_f_of_t0 = replace_rhs_of_main p f f_of_t0 in
  let nr = nonreduced_terms p f.pnon_terminals simpl_f_of_t0 in
  (* Collect all the variables that need to be expanded. *)
  let expand_reqs =
    let collect c (_, args) =
      match List.last args with
      | Some arg -> Set.union c (Analysis.free_variables arg)
      | None -> c
    in List.fold ~f:collect ~init:VarSet.empty nr
  in
  let substs =
    let expansions =
      List.map ~f:(fun x -> List.cartesian_product [mk_var x] (Analysis.expand_once (mk_var x)))
        (Set.to_list expand_reqs)
    in cartesian_nary_product expansions
  in
  let all_ts = List.map substs ~f:(fun s -> substitution s t0) in
  let check_max_exp t =
    let tr = replace_rhs_of_main p f (PMRS.reduce f t) in
    match nonreduced_terms p f.pnon_terminals tr with
      [] -> First(t, tr)
    | _ -> Second t
  in
  let mr_terms, rest =
    List.partition_map all_ts ~f:check_max_exp
  in
  let mr_terms =
    match check_max_exp t0 with
    | First x -> x :: mr_terms
    | _ -> mr_terms
  in
  Log.debug
    (fun frmt () -> Fmt.(pf frmt "@[<hov 2>%a -> %a@]"
                           pp_term t0
                           (list ~sep:comma (parens (pair ~sep:comma pp_term pp_term)))
                           mr_terms));
  (* Expand and replace in term *)
  mr_terms, rest


(** `maximal p t0 ` expands the term `t0 ` such that `p.orig (p.repr t0)` is a maximally
    reduced term.
*)
let maximal (p : psi_def) (t0 : term) : TermSet.t * TermSet .t =
  (* Expand with repr *)
  let tset0, uset0 =
    if p.repr_is_identity then
      [t0, t0], []
    else
      let tset0, uset0 = expand_max p p.repr t0 in
      let s1 = subst_repr_calls p (List.map ~f:second tset0) in
      let tset0 =
        List.map tset0 ~f:(fun (tin, tout) -> tin, Analysis.reduce_term (substitution s1 tout))
      in
      tset0, uset0
  in
  let f (tset, uset) (t_theta, t_tau) =
    match expand_max p p.orig t_tau with
    | [_,_], [] ->  tset @ [t_theta], uset
    | new_ts, new_us ->
      if p.repr_is_identity then tset @ (List.map ~f:first new_ts), uset @ new_us
      else  failwith "TODO : implement repr inversion." (* TODO implement inversion *)
  in
  let l1, l2 = List.fold tset0 ~f ~init:([], uset0) in
  TermSet.of_list l1, TermSet.of_list l2

