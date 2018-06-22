open Syntax
open Source
open Types

(* todo: compute refutability of pats and enforce accordingly (refutable in all cases but last, irrefutable elsewhere) *)

type typ =
  | VarT of string * typ list                     (* constructor *)
  | PrimT of Types.prim                        (* primitive *)
  | ObjT of actor' * typ_field list             (* object *)
  | ArrayT of mut' * typ                        (* array *)
  | OptT of typ                                (* option *)
  | TupT of typ list                           (* tuple *)
  | FuncT of typ_bind list * typ * typ         (* function *)
  | AsyncT of typ                              (* future *)
  | LikeT of typ                               (* expansion *)
(*
  | AnyT                                       (* top *)
  | UnionT of type * typ                       (* union *)
  | AtomT of string                            (* atom *)
*)
and typ_bind = {var:string; bound: typ }
and typ_field = {var:string; typ: typ; mut: mut'}

module Env = Map.Make(String)



type kind = typ_bind list * typ

type context = {values: (typ*mut') Env.t; constructors: kind Env.t ; label: string option;  breaks: typ Env.t; continues: unit Env.t ; returns: typ option; awaitable: bool}

let union env1 env2 = Env.union (fun k v1 v2 -> Some v2) env1 env2
let union_values c ve = {c with values = union c.values ve}
let add_value c v tm = {c with values = Env.add v tm c.values}
let union_constructors c ce = {c with constructors = union c.constructors ce}
let add_constructor c v d = {c with constructors = Env.add v d c.constructors}

let prelude = {values = Env.empty;
    	       constructors = Env.empty;
               label = None;
	       breaks = Env.empty;
	       continues = Env.empty;
	       returns = None;
	       awaitable = false}

let addBreak context labelOpt t =
    match labelOpt with
    | None -> context
    | Some label -> { context with breaks = Env.add label t context.breaks }

let addBreakAndContinue context labelOpt t =
    match labelOpt with
    | None -> context
    | Some label -> {{ context with breaks = Env.add label t context.breaks } with continues = Env.add label () context.continues }

let sprintf = Printf.sprintf

exception KindError of Source.region * string
exception TypeError of Source.region * string

let lookup map k = try Some (Env.find k map)  with _ -> None (* TODO: use find_opt in 4.05 *)

let kindError region fmt = 
     Printf.ksprintf (fun s -> raise (KindError(region,s))) fmt

let typeError region fmt = 
     Printf.ksprintf (fun s -> raise (TypeError(region,s))) fmt

let check_bounds region tys bounds = 
     if List.length bounds = List.length tys
     then ()
     else kindError region "constructor expecting %i arguments used with %i arguments" (List.length bounds) (List.length tys)

(* todo: add context unless we normalize type abbreviations *)
let eq_typ ty1 ty2 = ty1 = ty2  (* TBC: need to use equational var env *)

(* types one can switch on - all primitives except floats *)
(* TBR - switch on option type? *)
let switchable_type t =
    match t with
    | PrimT p ->
      (match p with
       | FloatT -> false
       | _ -> true)
    | _ -> false

(* types one can iterate over using `for`  *)
let iterable_typ t =
    match t with
    | ArrayT(_,_) -> true
    | _ -> false
(* element type of iterable_type  *)
let element_typ t =
    match t with
    | ArrayT(mut,t) -> t
    | _ -> assert(false)

(* Poor man's pretty printing - replace with Format client *)
let mut_to_string m = (match m with VarMut -> " var " |  ConstMut -> "")
let rec typ_to_string t =
    match t with
    | PrimT p ->
     (match p with
      | NullT -> "Null"
      | IntT -> "Int"
      | BoolT -> "Bool"
      | FloatT -> "Float"
      | NatT -> "Nat"
      | CharT -> "Char"
      | WordT w ->
        (match w with
	| Width8 -> "Word8"
	| Width16 -> "Word16"
	| Width32 -> "Word32"
	| Width64 -> "Word66")
      | TextT -> "Text")
    | VarT (c,[]) ->
       c
    | VarT (c,ts) ->
       sprintf "%s<%s>" c (String.concat "," (List.map typ_to_string ts))
    | ArrayT (m,t) ->
      sprintf "%s%s[]" (match m with VarMut -> " var " |  ConstMut -> "") (typ_to_string t)  
    | TupT ts ->
      sprintf "(%s)"  (String.concat "," (List.map typ_to_string ts))
    | FuncT([],dom,rng) ->
      sprintf "%s->%s" (typ_to_string dom) (typ_to_string rng)      
    | FuncT(ts,dom,rng) ->
      sprintf "<%s>%s->%s"  (String.concat "," (List.map (fun {var;bound} -> var) ts)) (typ_to_string dom) (typ_to_string rng)
    | OptT t ->
      sprintf "%s?"  (typ_to_string t)
    | AsyncT t -> 
      sprintf "async %s" (typ_to_string t)
    | LikeT t -> 
      sprintf "like %s" (typ_to_string t)
    | ObjT(a,fs) ->
      sprintf "%s{%s}" (match a with Actor -> "actor" | Object -> "object")
      	      	       (String.concat ";" (List.map (fun {var;mut;typ} ->
		       		       		          sprintf "%s:%s %s" var (mut_to_string mut) (typ_to_string typ))
				           fs))


let unitT = TupT[]
let boolT = PrimT(BoolT)

let rec check_typ_binds context ts =
        let bind_context = context in (* TBR: allow parameters in bounds? - not for now*)
        let ts = List.map (fun (bind:Syntax.typ_bind) ->
                  {var=bind.it.Syntax.var.it;bound=check_typ bind_context bind.it.Syntax.bound}
                 ) ts in
        let constructors  =
          List.fold_left (fun c bind -> Env.add bind.var ([],bind.bound) c) context.constructors ts in
	ts,constructors

(*TBD do we want F-bounded checking with mutually recursive bounds? *)

and check_typ context t = match t.it with
    | Syntax.VarT (c,tys) ->
      (match lookup context.constructors c.it with
          | Some (bounds,_) -> 
            let ts = List.map (check_typ context) tys in
            check_bounds t.at ts bounds ;
            VarT(c.it,ts)
          | None -> kindError c.at "unbound constructor %s" c.it)
    | Syntax.PrimT p -> PrimT p      
    | Syntax.ArrayT (m,t) ->
      ArrayT(m.it,check_typ context t)
    | Syntax.TupT ts ->
        let ts = List.map (check_typ context) ts in
        TupT ts
    | Syntax.FuncT(ts,dom,rng) ->
        let ts,constructors = check_typ_binds context ts in
        let context = {context with constructors = constructors} in
        FuncT(ts,check_typ context dom, check_typ context rng)
    | Syntax.OptT t -> OptT (check_typ context t)
    | Syntax.AsyncT t -> AsyncT (check_typ context t)
    | Syntax.LikeT t -> LikeT (check_typ context t)
    | Syntax.ObjT(a,fs) ->
      (* fields distinct? *)
      let _ = List.fold_left (fun (dom:string list) ({it={var;typ;mut};at}:Syntax.typ_field)->
                               if List.mem var.it dom
                               then kindError var.at "duplicate field name %s in object type" var.it
                               else (var.it::dom)) ([]:string list) fs in
      let fs = List.map (fun (f:Syntax.typ_field) ->
      	  {var=f.it.var.it;typ=check_typ context f.it.typ;mut=f.it.mut.it}) fs in
      (* sort by name (for indexed access *)
      let fs_sorted = List.sort (fun (f:typ_field)(g:typ_field) -> String.compare f.var g.var) fs in
      ObjT(a.it,fs_sorted)
    
and inf_lit l =
  match l with
    | NullLit -> PrimT NullT (* TBR *)
    | BoolLit _ -> PrimT BoolT
    | NatLit _ -> PrimT NatT
    | IntLit _ -> PrimT IntT
    | WordLit w ->
        PrimT (WordT (match w with 
	              | Word8 _ -> Width8
                      | Word16 _ -> Width16
                      | Word32 _ -> Width32
                      | Word64 _ -> Width64))
    | FloatLit _ -> PrimT FloatT
    | CharLit _ -> PrimT CharT
    | TextLit _ -> PrimT TextT

and inf_exp context e =
    let t = inf_exp' context e in
    (*TODO: record t in e *)
    t
and inf_exp' context e =
let labelOpt = context.label in
let context = {context with label = None} in
match e.it with
| VarE x ->
  (match lookup context.values x.it with
    | Some (ty,_) -> ty
    | None -> typeError x.at "unbound identifier %s" x.it)
| LitE l ->
   inf_lit l
| TupE es ->
   let ts = List.map (inf_exp context) es in
   TupT ts
| ProjE(e,n) ->
  (match inf_exp context e with
   | TupT(ts) ->
     (try List.nth ts n
      with Failure _ -> typeError e.at "tuple projection %i >= %n is out-of-bounds" n (List.length ts))
   | t -> typeError e.at "expecting tuple type, found %s" (typ_to_string t))
| DotE(e,v) ->
  (match inf_exp context e with
   |(ObjT(a,fts) as t) ->
     (try let ft = List.find (fun (fts:typ_field) -> fts.var = v.it) fts in
         ft.typ
      with  _ -> typeError e.at "object of type %s has no field named %s" (typ_to_string t) v.it)
   | t -> typeError e.at "expecting object type, found %s" (typ_to_string t))   
| AssignE(e1,e2) ->
 (match e1.it with
  (*TODO: array and object update *)
  |  VarE v ->
     (match lookup context.values v.it with
       | Some (t1,VarMut) ->
           let t2 = inf_exp context e2 in
	   if eq_typ t1 t2
	   then unitT
	   else typeError e.at "location of type %s cannot store value of type %s" (typ_to_string t1) (typ_to_string t2)
       | Some (_,ConstMut) ->
          typeError e.at "cannot assign to immutable location")
  | IdxE(a,i) ->
     failwith "NYI" (* TBC *))
| ArrayE [] ->
     typeError e.at "cannot infer type of empty array"
| ArrayE ((_::_) as es) ->
  let t1::ts = List.map (inf_exp context) es in
  if List.for_all (eq_typ t1) ts
  then ArrayT(VarMut,t1) (* TBR how do we create immutable arrays? *)
  else typeError e.at "array contains elements of distinct types"
| CallE(e1,e2) ->
 (match inf_exp context e1 with
  | FuncT([],dom,rng) -> (* TBC polymorphic instantiation, perhaps by matching? *)
    let t2 = inf_exp context e2 in
    if eq_typ t2 dom
    then rng
    else typeError e.at "illegal application: argument of wrong type"  
  | _ -> typeError e.at "illegal application: not a function")
| BlockE es ->
  let t = check_block context es in
  t
| NotE(e) ->
  check_exp context boolT e;
  boolT
| AndE(e1,e2) ->
  check_exp context boolT e1;
  check_exp context boolT e2;
  boolT
| OrE(e1,e2) ->
  check_exp context boolT e1;
  check_exp context boolT e2;
  boolT
| IfE(e0,e1,e2) ->
  check_exp context boolT e0;
  let t1 = inf_exp context e1 in
  let t2 = inf_exp context e2 in
  if eq_typ t1 t2
  then t1
  else typeError e.at "branches of if have different types"
| SwitchE(e,cs) ->
  let t = inf_exp context e in
  if switchable_type t
  then match inf_cases context t cs None with
       | Some t -> t
       | None -> (* assert(false); *)
                 typeError e.at "couldn't infer type of case"
  else typeError e.at "illegal type for switch"
| WhileE(e0,e1) ->
  check_exp context boolT e0;
  let context' = addBreakAndContinue context labelOpt unitT in
  check_exp context' unitT e1;
  unitT
| LoopE(e,None) ->
  let context' = addBreakAndContinue context labelOpt unitT in
  check_exp context' unitT e;
  unitT (* absurdTy? *)
| LoopE(e0,Some e1) ->
  let context' = addBreakAndContinue context labelOpt unitT in
  check_exp context' unitT e0;
  (* TBR currently can't break or continue from guard *)
  check_exp context boolT e1;
  unitT
| ForE(p,e0,e1)->
  let t = inf_exp context e0 in (*TBR is this for arrays only? If so, what about mutability*)
  if iterable_typ t
  then 
    let ve = check_pat context p (element_typ t) in
    let context' = addBreakAndContinue {context with values = union context.values ve} labelOpt unitT in
    check_exp context' unitT e1;
    unitT
  else typeError e.at "cannot iterate over this type"
(* labels *)
| LabelE(l,e) ->
  let context = {context with label = Some l.it} in
  inf_exp context e
| BreakE(l,[e]) ->
  (match lookup context.breaks l.it  with
   | Some t -> 
     (* todo: check type of e against ts! *)
     check_exp context t e ;
     unitT (*TBR actually, this could be polymorphic at least in a checking context*)
   | None -> typeError e.at "break to unknown label %s" l.it)
| ContE l ->
  (match lookup context.continues l.it  with
   | Some _ -> 
     unitT (*TBR actually, this could be polymorphic at least in a checking context*)
   | None -> typeError e.at "continue to unknown label %s" l.it)
| RetE [e0] ->
  (match context.returns with
   | Some t ->
     check_exp context t e0;
     unitT (*TBR actually, this could be polymorphic at least in a checking context*)
   | None -> typeError e.at "illegal return")
| AsyncE e0 ->
    let context = {values = context.values;
                   constructors = context.constructors;
		   breaks = Env.empty;
		   label = context.label;
		   continues = Env.empty;
		   returns = Some unitT; (* TBR *)
		   awaitable = true} in
    let t = inf_exp context e0 in
    AsyncT t
| AwaitE e0 ->
    if context.awaitable
    then
      match inf_exp context e0 with
      | AsyncT t -> t
      | t -> typeError e0.at "expecting expression of async type, found expression of type %s" (typ_to_string t)
    else typeError e.at "illegal await in synchronous context"
| IsE(e,t) ->
    let _ = inf_exp context e in
    let _ = check_typ context t in (*TBR what if T has free type variables? How will we check this, sans type passing *) 
    boolT
| AnnotE(e,t) ->
    let t = check_typ context t in 
    check_exp context t e;
    t
| DecE d ->
    let _ = check_dec context d in
    unitT
    
and inf_cases context pt cs t_opt  =
  match cs with
  | [] -> t_opt
  | {it={pat=p;exp=e};at}::cs ->
    let ve = check_pat context p pt in
    let t = inf_exp {context with values = union context.values ve} e in
    let t_opt' = match t_opt with
    	      | None -> Some t
 	      | Some t' ->
	         if eq_typ t t'
    		 then Some t'
		 else typeError at "illegal case of different type from preceeding cases" in
    inf_cases context pt cs t_opt'
and check_exp context t e =
  match e.it with
  | ArrayE es ->
    (match t with
    | ArrayT (mut,t) ->
      List.iter (check_exp context t) es
    | _ -> typeError e.at "array cannot produce expected type")
  | _ ->
    let t' = inf_exp context e in
    if (eq_typ t t')
    then ()
    else typeError e.at "expecting expression of type %s found expression of type %s" (typ_to_string t) (typ_to_string t')
    
and check_block context es =
  match es with
  | [] -> unitT
  | {it = DecE d;at}::es ->
    let ve,ce = check_dec context d in
    check_block (union_constructors (union_values context ve) ce) es
  | e::es ->
    match inf_exp context e with 
    | TupT[] -> check_block context es
    | _ -> typeError e.at "expression used as statement must have unit type"  (* TBR: is this too strict? do we want to allow implicit discard? *)

and check_dec context d =
    let ve , ce = check_dec' context d in
    (* TBC store ve *)
    ve, ce

and check_dec' context d =     
    match d.it with
    | LetD (p,e) ->
      let ve,t = inf_pat context p in (* be more clever here and use t' to check p, eg. for let _ = e *)
      let t' = inf_exp context e in
      if eq_typ t t'
      then ve,Env.empty
      else typeError d.at "type of pattern doesn't match type of expressions"
    | VarD (v,t,None) ->
      let t = check_typ context t in
      Env.singleton v.it (t,VarMut),Env.empty
    | VarD (v,t,Some e) ->
      let t = check_typ context t in
      check_exp context t e;
      Env.singleton v.it (t,VarMut),
      Env.empty
    | FuncD(v,ts,p,t,e) ->
      let ts,constructors = check_typ_binds context ts in
      let context' = {context with constructors = union context.constructors constructors} in
      let ve,dom = inf_pat context' p in
      let rng = check_typ context' t in
      let funcT = FuncT(ts,dom,rng) (* TBR: we allow polymorphic recursion *) in
      let context'' =
      	  {values = union (Env.add v.it (funcT,ConstMut)  context.values) ve;
	   constructors = union context.constructors constructors;
           label = None;
	   breaks = Env.empty;
	   continues = Env.empty;
	   returns = Some rng;
	   awaitable = false}
      in
      check_exp context'' rng e;
      Env.singleton v.it (funcT,ConstMut), Env.empty
    | ClassD(a,v,ts,p,efs) ->
      let ts,constructors = check_typ_binds context ts in
      let context_ts = union_constructors context constructors in
      let class_ = VarT (v.it , List.map (fun tb -> (VarT (tb.var,[]))) ts) in
      let context_ts_v = add_constructor (union_constructors context constructors) v.it (ts,class_) in
      let ve,dom = inf_pat context_ts_v p in
      let context_ts_v_dom =
          {context_ts_v with values = union context_ts_v.values ve} in
      let rec pre_members context field_env efs =
      	  match efs with
	  | [] -> field_env
	  | {it={var;mut;priv;exp={it=AnnotE(e,t);at}}}::efs ->
	    let t = check_typ context t in
	    let field_env = Env.add var.it (mut.it,priv.it,t) field_env in
	    pre_members context field_env efs
	  | {it={var;mut;priv;exp={it=DecE({it=FuncD(v,us,p,t,e);at=_});at=_}}}::efs ->
	    let us,constructors = check_typ_binds context us in
	    let context_us = { context with constructors = union context.constructors constructors} in
	    let _,dom = inf_pat context_us p in
	    let rng = check_typ context_us t in
	    let funcT = FuncT(us,dom,rng) in
	    let field_env = Env.add var.it (mut.it,priv.it,funcT) field_env in
    	    pre_members context field_env efs
          | {it={var;mut;priv;exp=e}}::efs ->
	    let t = inf_exp context e in
	    let field_env = Env.add var.it (mut.it,priv.it,t) field_env in
	    pre_members context field_env efs
      in
      let pre_members = pre_members context_ts_v_dom Env.empty efs in
      let public_fields =
      	  let bindings = Env.bindings pre_members in
	  let public = List.filter (fun (v,(m,p,t)) -> p = Public) bindings in
	  List.map (fun (v,(m,p,t)) -> {var=v;typ=t;mut=m}) public
      in	  
      let private_context = Env.map (fun (m,p,t) -> (t,m)) pre_members in

      let objT  = ObjT(a.it,public_fields) in
      let class_def = objT in

      let consT = FuncT(ts,dom,class_) (* TBR: we allow polymorphic recursion *) in

      let field_context = add_value (union_values context_ts_v_dom private_context) v.it (consT,VarMut) in
      (*TODO, add type def *)				  
      let _ = List.map (fun {it={var;mut;exp}} -> inf_exp field_context exp) efs in
      (*TODO, export type def *)
      Env.singleton v.it (consT,ConstMut),
      Env.singleton v.it (ts,objT)


and inf_pats context ve ts ps =
   match ps with
   | [] -> ve, TupT(List.rev ts)
   | p::ps ->
     let ve',t = inf_pat context p in
     inf_pats context (union ve ve') (t::ts) ps

and inf_pat context p =
   match p.it with
   | WildP ->  typeError p.at "can't infer type of pattern"
   | VarP v -> typeError p.at "can't infer type of pattern"
   | LitP l ->
     Env.empty,inf_lit l
   | TupP ps ->
     inf_pats context Env.empty [] ps
   | AnnotP(p,t) ->
     let t = check_typ context t in
     check_pat context p t,t
     
and check_pat context p t =
   match p.it with
   | WildP -> Env.empty
   | VarP v -> Env.singleton v.it (t,ConstMut)
   | LitP l -> Env.empty
   | TupP ps ->
     (match t with
      | TupT ts ->
        check_pats p.at context Env.empty ps ts 
      | _ -> typeError p.at "expected pattern of non-tuple type, found pattern of tuple type")
   | AnnotP(p',t') ->
     let t' = check_typ context t' in
     if eq_typ t t'
     then check_pat context p' t'
     else typeError p.at "expected pattern of one type, found pattern of unequal type"
and check_pats at context ve ps ts =
   match ps,ts with
   | [],[] -> ve
   | p::ps,t::ts ->
     let ve' = check_pat context p t in
     check_pats at context (union ve ve') ps ts  (*TBR reject shadowing *)
   | [],ts -> typeError at "tuple pattern has %i fewer components than expected type" (List.length ts)
   | ts,[] -> typeError at "tuple pattern has %i more components than expected type" (List.length ts)
         
      
let rec check_decs context ds = match ds with
   |  [] -> context
   |  d::ds ->
      let ve,ce = check_dec context d in
      check_decs (union_constructors (union_values context ve) ce) ds


let check_prog p =
    let context = check_decs prelude p.it in
    () 
    
    






