(** @synduce -s 2 -NB -n 30 --no-lifting *)

type list =
  | Elt of int
  | Cons of int * list

type nested_list =
  | Line of list
  | NCons of list * nested_list

let rec is_sorted = function
  | Line x -> true
  | NCons (hd, tl) -> aux (lmax hd) tl

and lmax = function
  | Elt x -> x
  | Cons (hd, tl) -> max (lmax tl) hd

and aux prev = function
  | Line x -> prev <= lmax x
  | NCons (hd, tl) -> prev <= lmax hd && aux (lmax hd) tl
;;

let rec spec = function
  | Line a ->
    let lo, hi = interval a in
    lo, hi, true
  | NCons (hd, tl) ->
    let plo, phi, pyramidal = spec tl in
    let lo, hi = interval hd in
    min lo plo, max hi phi, pyramidal && plo <= lo && hi >= phi

and interval = function
  | Elt x -> x, x
  | Cons (hd, tl) ->
    let lo, hi = interval tl in
    min hd lo, max hd hi
;;

let rec target = function
  | Line x -> [%synt s0] (inter x) true
  | NCons (hd, tl) -> [%synt s1] (plmin hd) (target tl)
[@@requires is_sorted]

and inter = function
  | Elt x -> x, x
  | Cons (hd, tl) ->
    let lo, hi = inter tl in
    min hd lo, max hd hi

and plmin = function
  | Elt x -> x
  | Cons (hd, tl) ->
    let lo = plmin tl in
    min hd lo
;;

assert (target = clist_to_list @@ spec)
