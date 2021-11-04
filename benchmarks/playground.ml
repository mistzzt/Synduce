(** @synduce --no-gropt *)

type 'a list =
  | Elt of 'a
  | Cons of 'a * 'a list

(* Representation function: sort a list in increasing order. *)
let rec repr = function
  | Elt x -> Elt x
  | Cons (hd, tl) -> insert hd (repr tl)

and insert y = function
  | Elt x -> if y < x then Cons (y, Elt x) else Cons (x, Elt y)
  | Cons (hd, tl) -> if y < hd then Cons (y, Cons (hd, tl)) else Cons (hd, insert y tl)
;;

(* Invariant: length >= 2 *)
let rec is_length_lt2 l = len l >= 2

and len = function
  | Elt x -> 1
  | Cons (hd, tl) -> 1 + len tl
;;

let rec spec l = f 0 l

and f s = function
  | Elt x -> x
  | Cons (hd, tl) -> if s = 2 then hd else f (s + 1) tl
;;

let rec target = function
  | Elt x -> [%synt base_case] x
  | Cons (hd, tl) -> [%synt join] hd (target tl)
  [@@requires is_length_lt2]
;;
