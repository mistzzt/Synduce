let cvc4_binary_path =
  try Some (FileUtil.which "cvc4") with
  | _ -> None
;;

let cvc5_binary_path =
  try Some (FileUtil.which "cvc5") with
  | _ -> None
;;

let z3_binary_path =
  try FileUtil.which "z3" with
  | _ -> failwith "Z3 not found (using 'which z3')."
;;