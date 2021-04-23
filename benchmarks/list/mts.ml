type 'a clist = CNil | Single of 'a | Concat of 'a clist * 'a clist

type 'a list = Nil | Cons of 'a * 'a list

let rec mts = function
  | Nil -> (0, 0)
  | Cons (hd, tl) ->
      let _mts, _sum = mts tl in
      let new_sum = _sum + hd in
      (max _mts new_sum, new_sum)
  (* the mts is always positive *)
  [@@ensures fun (x, y) -> x >= 0]

let rec clist_to_list = function
  | CNil -> Nil
  | Single a -> Cons (a, Nil)
  | Concat (x, y) -> dec y x

and dec l1 = function
  | CNil -> clist_to_list l1
  | Single a -> Cons (a, clist_to_list l1)
  | Concat (x, y) -> dec (Concat (y, l1)) x

let rec hom = function
  | CNil -> [%synt s0]
  | Single a -> [%synt f0] a
  | Concat (x, y) -> [%synt join] (hom x) (hom y)

;;
assert (hom = clist_to_list @@ mts)