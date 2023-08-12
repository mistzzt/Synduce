open Lang
open Base
open Common
open Env
open Term

let env = Lib.load_ctx_of_file "/home/victorn/repos/Synduce/benchmarks/list/sum.ml"

let _dtype_test =
  Alcotest.testable
    (fun fmt x -> Fmt.pf fmt "%s" (Analysis.DType.show_type_constr x))
    Analysis.DType.equal_type_constr
;;

let list_dtype_test =
  Alcotest.testable
    (fun fomt x ->
      Fmt.(pf fomt "%a" (list string) (List.map ~f:Analysis.DType.show_type_constr x)))
    (List.equal Analysis.DType.equal_type_constr)
;;

let test_dep0 () =
  let open Analysis in
  let dt_conslist =
    DType.get_t ~ctx:env.ctx 0 RType.(TParam ([ TInt ], TNamed "conslist"))
  in
  let dt_concatlist =
    DType.get_t ~ctx:env.ctx 0 RType.(TParam ([ TInt ], TNamed "clist"))
  in
  List.iter dt_conslist ~f:(fun d -> Fmt.(pf stdout "%s@." (DType.show_type_constr d)));
  let b1 = not (List.is_empty dt_conslist) in
  let b2 = not (List.is_empty dt_concatlist) in
  Alcotest.(check bool) "non-empty" true (b1 && b2);
  Alcotest.(check list_dtype_test)
    "check-res-conslist"
    dt_conslist
    [ DType.Rec ("Nil", []) ];
  Alcotest.(check list_dtype_test)
    "check-res-concatlist"
    dt_concatlist
    [ DType.Rec ("CNil", []); DType.Rec ("Single", [ DType.Scalar (0, TInt) ]) ]
;;

let test_dep_1 () =
  let open Analysis in
  let dt_conslist =
    DType.get_t ~ctx:env.ctx 1 RType.(TParam ([ TInt ], TNamed "conslist"))
  in
  let dt_concatlist =
    DType.get_t ~ctx:env.ctx 1 RType.(TParam ([ TInt ], TNamed "clist"))
  in
  List.iter dt_conslist ~f:(fun d -> Fmt.(pf stdout "%s@." (DType.show_type_constr d)));
  let c1 = List.length dt_conslist in
  let c2 = List.length dt_concatlist in
  Alcotest.(check int) "len-conslist-d1" 2 c1;
  Alcotest.(check int) "len-concatlist-d1" 6 c2;
  Alcotest.(check list_dtype_test)
    "check-res-conslist"
    dt_conslist
    [ DType.Rec ("Nil", [])
    ; DType.Rec ("Cons", [ DType.Scalar (0, RType.TInt); DType.Rec ("Nil", []) ])
    ];
  Alcotest.(check list_dtype_test)
    "check-res-concatlist"
    dt_concatlist
    DType.
      [ Rec ("CNil", [])
      ; Rec ("Single", [ Analysis.DType.Scalar (0, TInt) ])
      ; Rec
          ("Concat", [ Analysis.DType.Rec ("CNil", []); Analysis.DType.Rec ("CNil", []) ])
      ; Rec
          ( "Concat"
          , [ Analysis.DType.Rec ("Single", [ Analysis.DType.Scalar (0, TInt) ])
            ; Analysis.DType.Rec ("CNil", [])
            ] )
      ; Rec
          ( "Concat"
          , [ Analysis.DType.Rec ("CNil", [])
            ; Analysis.DType.Rec ("Single", [ Analysis.DType.Scalar (0, TInt) ])
            ] )
      ; Rec
          ( "Concat"
          , [ Rec ("Single", [ Scalar (0, TInt) ])
            ; Analysis.DType.Rec ("Single", [ Analysis.DType.Scalar (0, TInt) ])
            ] )
      ]
;;

let sizes = [| 1; 6; 38; 1446; 2090918 |]

let test_dep_n n =
  let open Analysis in
  let dt_conslist =
    DType.get_t ~ctx:env.ctx n RType.(TParam ([ TInt ], TNamed "conslist"))
  in
  let dt_concatlist =
    DType.get_t ~ctx:env.ctx n RType.(TParam ([ TInt ], TNamed "clist"))
  in
  List.iter dt_conslist ~f:(fun d -> Fmt.(pf stdout "%s@." (DType.show_type_constr d)));
  let c1 = List.length dt_conslist in
  let c2 = List.length dt_concatlist in
  Alcotest.(check int) "len-conslist-dn" (n + 1) c1;
  Alcotest.(check int) "len-concatlist-dn" (Array.get sizes n) c2 (* 1446 *)
;;

let test_subsequent_call_speed n =
  let open Analysis in
  let t0 = Unix.gettimeofday () in
  let _ = DType.get_t ~ctx:env.ctx n RType.(TParam ([ TInt ], TNamed "clist")) in
  let tfin = Unix.gettimeofday () -. t0 in
  Alcotest.(check bool) "time_limit" true Float.(tfin < 0.001)
;;

let test_looping () =
  let x, y, a, _ =
    ( Variable.mk env.ctx ~t:(Some RType.(TParam ([ TInt ], TNamed "clist"))) "x"
    , Variable.mk env.ctx ~t:(Some RType.(TParam ([ TInt ], TNamed "clist"))) "y"
    , Variable.mk env.ctx ~t:(Some RType.TInt) "a"
    , Variable.mk env.ctx ~t:(Some RType.TInt) "b" )
  in
  let initial_term =
    mk_data
      env.ctx
      "Concat"
      [ mk_data env.ctx "Elt" [ mk_var env.ctx a ]
      ; mk_data env.ctx "Concat" [ mk_var env.ctx x; mk_var env.ctx y ]
      ]
  in
  let terms_to_check =
    let vars_to_expand =
      Set.to_list
        (Set.filter
           (Analysis.free_variables ~include_functions:false ~ctx:env.ctx initial_term)
           ~f:(fun v -> Option.is_some (Analysis.is_expandable_var ~ctx:env.ctx v)))
    in
    let n = 60 in
    let subs =
      List.map vars_to_expand ~f:(fun v ->
        List.map
          ~f:(fun t -> mk_var env.ctx v, t)
          (Analysis.DType.gen_terms ~ctx:env.ctx (Variable.vtype_or_new env.ctx v) n))
    in
    List.map
      ~f:(fun subs -> substitution subs initial_term)
      (Utils.cartesian_nary_product subs)
  in
  Alcotest.(check int) "len-check" (List.length terms_to_check) 3600
;;

let () =
  let open Alcotest in
  run
    "GeneratingListTerms"
    [ "list-depth-0", [ test_case "depth=0" `Quick (fun () -> test_dep0 ()) ]
    ; "list-depth-1", [ test_case "depth=1" `Quick (fun () -> test_dep_1 ()) ]
    ; "list-depth-2", [ test_case "depth=2" `Quick (fun () -> test_dep_n 2) ]
    ; "list-depth-3", [ test_case "depth=3" `Quick (fun () -> test_dep_n 3) ]
    ; "list-depth-4", [ test_case "depth=4" `Quick (fun () -> test_dep_n 4) ]
    ; ( "test-speed-1"
      , [ test_case "speed(3)" `Quick (fun () -> test_subsequent_call_speed 3) ] )
    ; ( "test-speed-2"
      , [ test_case "speed(4)" `Quick (fun () -> test_subsequent_call_speed 4) ] )
    ; "test-looping", [ test_case "looping" `Quick test_looping ]
    ]
;;
