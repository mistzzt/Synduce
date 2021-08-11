open Base
open Term

val simplify : term -> term
(** Simplifies a term using rules rewriting terms containing constants.
    If all the leaves of the term are constants, evaluates the term to
    a constant.
*)

val in_model : (int, term, Int.comparator_witness) Map.t -> term -> term
