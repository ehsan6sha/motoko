(* Representation *)

type lab = string
type var = string

type control = Returns | Promises | Replies
type obj_sort = Object | Actor | Module
type shared_sort = Query | Write
type func_sort = Local | Shared of shared_sort
type eff = Triv | Await

type prim =
  | Null
  | Bool
  | Nat
  | Nat8
  | Nat16
  | Nat32
  | Nat64
  | Int
  | Int8
  | Int16
  | Int32
  | Int64
  | Word8
  | Word16
  | Word32
  | Word64
  | Float
  | Char
  | Text
  | Error

type t = typ
and typ =
  | Var of var * int                          (* variable *)
  | Con of con * typ list                     (* constructor *)
  | Prim of prim                              (* primitive *)
  | Obj of obj_sort * field list              (* object *)
  | Variant of field list                     (* variant *)
  | Array of typ                              (* array *)
  | Opt of typ                                (* option *)
  | Tup of typ list                           (* tuple *)
  | Func of func_sort * control * bind list * typ list * typ list  (* function *)
  | Async of typ                              (* future *)
  | Mut of typ                                (* mutable type *)
  | Any                                       (* top *)
  | Non                                       (* bottom *)
  | Typ of con                                (* type (field of module) *)
  | Pre                                       (* pre-type *)

and bind = {var : var; bound : typ}
and field = {lab : lab; typ : typ}

and con = kind Con.t
and kind =
  | Def of bind list * typ
  | Abs of bind list * typ

(* Function sorts *)

val is_shared_sort : func_sort -> bool

(* Short-hands *)

val unit : typ
val bool : typ
val nat : typ
val int : typ
val text : typ
val char : typ

val throwErrorCodes : field list
val catchErrorCodes : field list
val throw : typ
val catch : typ


val iter_obj : typ -> typ

val prim : string -> prim


(* Projection *)

val is_non : typ -> bool
val is_prim : prim -> typ -> bool
val is_obj : typ -> bool
val is_variant : typ -> bool
val is_array : typ -> bool
val is_opt : typ -> bool
val is_tup : typ -> bool
val is_unit : typ -> bool
val is_pair : typ -> bool
val is_func : typ -> bool
val is_async : typ -> bool
val is_mut : typ -> bool
val is_typ : typ -> bool

val as_prim : prim -> typ -> unit
val as_obj : typ -> obj_sort * field list
val as_variant : typ -> field list
val as_array : typ -> typ
val as_opt : typ -> typ
val as_tup : typ -> typ list
val as_unit : typ -> unit
val as_pair : typ -> typ * typ
val as_func : typ -> func_sort * control * bind list * typ list * typ list
val as_async : typ -> typ
val as_mut : typ -> typ
val as_immut : typ -> typ
val as_typ : typ -> con

val as_prim_sub : prim -> typ -> unit
val as_obj_sub : string list -> typ -> obj_sort * field list
val as_variant_sub : string -> typ -> field list
val as_array_sub : typ -> typ
val as_opt_sub : typ -> typ
val as_tup_sub : int -> typ -> typ list
val as_unit_sub : typ -> unit
val as_pair_sub : typ -> typ * typ
val as_func_sub : func_sort -> int -> typ -> func_sort * bind list * typ * typ
val as_mono_func_sub : typ -> typ * typ
val as_async_sub : typ -> typ


(* Argument/result sequences *)

val seq : typ list -> typ
val codom : control -> typ list -> typ
val as_seq : typ -> typ list (* This needs to go away *)
val seq_of_tup : typ -> typ list
val arity : typ -> int

(* Fields *)

val lookup_val_field : string -> field list -> typ
val lookup_typ_field : string -> field list -> con

val compare_field : field -> field -> int


(* Constructors *)

val set_kind : con -> kind -> unit

module ConEnv : Env.S with type key = con
module ConSet : Dom.S with type elt = con


(* Normalization and Classification *)

val normalize : typ -> typ
val promote : typ -> typ

exception Unavoidable of con
val avoid : ConSet.t -> typ -> typ (* raise Unavoidable *)
val avoid_cons : ConSet.t -> ConSet.t -> unit (* raise Unavoidable *)

val opaque : typ -> bool
val concrete : typ -> bool
val shared : typ -> bool
val find_unshared : typ -> typ option
val is_shared_func : typ -> bool
val inhabited : typ -> bool
val span : typ -> int option


(* Cons occuring in kind *)

val cons_kind : kind -> ConSet.t


(* Equivalence and Subtyping *)

val eq : typ -> typ -> bool
val eq_kind : kind -> kind -> bool

val sub : typ -> typ -> bool
val compatible : typ -> typ -> bool

val lub : typ -> typ -> typ
val glb : typ -> typ -> typ


(* First-order substitution *)

val close : con list -> typ -> typ
val close_binds : con list -> bind list -> bind list

val open_ : typ list -> typ -> typ
val open_binds : bind list -> typ list


(* Environments *)

module Env : Env.S with type key = string

(* Pretty printing *)

val string_of_obj_sort : obj_sort -> string
val string_of_func_sort : func_sort -> string
val string_of_con : con -> string
val string_of_prim : prim -> string
val string_of_typ : typ -> string
val string_of_kind : kind -> string
val strings_of_kind : kind -> string * string * string
val string_of_typ_expand : typ -> string
