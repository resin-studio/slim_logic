import Std.Data.BinomialHeap
import Init.Data.Hashable
import Lean.Data.PersistentHashMap
import Lean.Data.PersistentHashSet

import Util

open Lean PersistentHashMap PersistentHashSet
open Std
-- open Lean PHashMap PHashSet

open PHashSet


partial def multi_step {T : Type} [BEq T] (step : T -> T) (source : T): T :=
  let sink := step source 
  if sink == source then
    sink
  else 
    multi_step step sink

namespace Nameless 

  def bind_nl (i_xs : Nat × List α) 
  (f : Nat -> α -> (Nat × List β)) :
  (Nat × List β) :=
    let (i, xs) := i_xs
    List.foldl (fun (i, u_acc) env_ty =>
      let (i, xs) := (f i env_ty)
      (i, u_acc ++ xs)
    ) (i, []) xs 

  inductive Ty : Type
  | bvar : Nat -> Ty  
  | fvar : Nat -> Ty
  | unit : Ty
  | top : Ty
  | bot : Ty
  | tag : String -> Ty -> Ty
  | field : String -> Ty -> Ty
  | union : Ty -> Ty -> Ty
  | inter : Ty -> Ty -> Ty
  | impli : Ty -> Ty -> Ty
  | exis : Nat -> Ty -> Ty -> Ty -> Ty
  | univ : Option Ty -> Ty -> Ty
  | induc : Ty -> Ty
  deriving Repr, Inhabited, Hashable, BEq
  -- #check List.repr

  namespace Ty

    structure Context where
      -- invariant: simple_to_relational.contains key --> 
      --              exsists ty_lower , ty_lower == simple_to_relational.find key  && env_relational.contains ty_lower   
      env_simple : PHashMap Nat Ty
      env_keychain : PHashMap Nat (PHashSet Ty)
      env_relational : PHashMap Ty Ty
    deriving Repr


    def infer_abstraction (start : Nat) : Ty -> Nat
    | .bvar idx => (idx + 1) - start
    | .fvar id => 0 
    | .unit => 0 
    | .top => 0 
    | .bot => 0 
    | .tag l ty =>
      infer_abstraction start ty 
    | .field l ty => 
      infer_abstraction start ty 
    | .union ty1 ty2 => 
      let n1 := infer_abstraction start ty1 
      let n2 := infer_abstraction start ty2
      if n1 > n2 then n1 else n2 
    | .inter ty1 ty2 => 
      let n1 := infer_abstraction start ty1 
      let n2 := infer_abstraction start ty2
      if n1 > n2 then n1 else n2 
    | .impli ty1 ty2 =>
      let n1 := infer_abstraction start ty1 
      let n2 := infer_abstraction start ty2
      if n1 > n2 then n1 else n2 
    | .exis n ty_c1 ty_c2 ty_pl =>
      let n_c1 := infer_abstraction (start + n) ty_c1 
      let n_c2 := infer_abstraction (start + n) ty_c2
      let n_pl := infer_abstraction (start + n) ty_pl  
      Nat.max (Nat.max n_c1 n_c2) n_pl
    | .univ op_ty_c ty_pl =>
      let n_c := match op_ty_c with 
      | some ty_c => infer_abstraction (start + 1) ty_c 
      | none => 0
      let n_pl := infer_abstraction (start + 1) ty_pl  
      Nat.max n_c n_pl
    | .induc content =>
      infer_abstraction (start + 1) content 

    partial def free_vars: Ty -> PHashSet Nat 
    | .bvar id => {} 
    | .fvar id => PersistentHashSet.empty.insert id 
    | .unit => {} 
    | .top => {} 
    | .bot => {} 
    | .tag l ty => (free_vars ty) 
    | .field l ty => (free_vars ty)
    | .union ty1 ty2 => (free_vars ty1).fold insert (free_vars ty2)
    | .inter ty1 ty2 => (free_vars ty1).fold insert (free_vars ty2)
    | .impli ty1 ty2 => (free_vars ty1).fold insert (free_vars ty2)
    | .exis n ty_c1 ty_c2 ty =>
      (free_vars ty_c1) + (free_vars ty_c2) + (free_vars ty)
    | .univ op_ty_c ty =>
      match op_ty_c with
      | some ty_c => (free_vars ty_c) + (free_vars ty)
      | none => (free_vars ty)
    | .induc ty => (free_vars ty)

    -- def neg_vars (neg : Bool) : Ty -> PHashSet Nat 
    -- | .bvar id => empty 
    -- | .fvar id => 
    --   if neg then
    --     empty.insert id
    --   else
    --     empty
    -- | .unit => empty 
    -- | .top => empty 
    -- | .bot => empty 
    -- | .tag l ty => (neg_vars neg ty) 
    -- | .field l ty => (neg_vars neg ty)
    -- | .union ty1 ty2 => (neg_vars neg ty1).fold insert (neg_vars neg ty2)
    -- | .inter ty1 ty2 => (neg_vars neg ty1).fold insert (neg_vars neg ty2)
    -- | .impli ty1 ty2 => (neg_vars true ty1).fold insert (neg_vars neg ty2)
    -- | .exis n ty_c1 ty_c2 ty =>
    --   (neg_vars neg ty_c1) + (neg_vars neg ty_c2) + (neg_vars neg ty)
    -- | .univ op_ty_c ty =>
    --   match op_ty_c with
    --   | some ty_c => (neg_vars neg ty_c) + (neg_vars neg ty)
    --   | none => (neg_vars neg ty)
    -- | .induc ty => (neg_vars neg ty)

    partial def abstract (fids : List Nat) (start : Nat) : Ty -> Ty
    | .bvar id => .bvar id 
    | .fvar id => 
      match (fids.enumFrom start).find? (fun (_, fid) => fid == id) with
      | .some (bid, _) => .bvar bid
      | .none => .fvar id
    | .unit => .unit
    | .top => .top
    | .bot => .bot
    | .tag l ty => .tag l (abstract fids start ty) 
    | .field l ty => .field l (abstract fids start ty)
    | .union ty1 ty2 => .union (abstract fids start ty1) (abstract fids start ty2)
    | .inter ty1 ty2 => .inter (abstract fids start ty1) (abstract fids start ty2)
    | .impli ty1 ty2 => .impli (abstract fids start ty1) (abstract fids start ty2)
    | .exis n ty_c1 ty_c2 ty => 
      (.exis n
        (abstract fids (start + n) ty_c1) (abstract fids (start + n) ty_c2)
        (abstract fids (start + n) ty)
      )
    | .univ op_ty_c ty => 
      (.univ (Option.map (abstract fids (start + 1)) op_ty_c) (abstract fids (start + 1) ty))
    | .induc ty => .induc (abstract fids (start + 1) ty)

    -- assuming no cycles; (assuming occurs check has been properly applied before hand) 
    partial def subst (m : PHashMap Nat Ty) : Ty -> Ty
    | .bvar id => .bvar id 
    | .fvar id => (match m.find? id with
      | some ty => 
        subst m ty 
      | none => .fvar id
    )
    | .unit => .unit
    | .top => .top
    | .bot => .bot
    | .tag l ty => .tag l (subst m ty) 
    | .field l ty => .field l (subst m ty)
    | .union ty1 ty2 => .union (subst m ty1) (subst m ty2)
    | .inter ty1 ty2 => .inter (subst m ty1) (subst m ty2)
    | .impli ty1 ty2 => .impli (subst m ty1) (subst m ty2)
    | .exis n ty_c1 ty_c2 ty => (.exis n
      (subst m ty_c1) (subst m ty_c2) 
      (subst m ty)
    )
    | .univ op_ty_c ty => 
      (.univ (op_ty_c.map (subst m)) (subst m ty))
    | .induc ty => .induc (subst m ty)

    -- assume assoc right
    def inter_contains : Ty -> Ty -> Bool 
    | ty1, .inter ty21 ty22 => 
      inter_contains ty1 ty21 ||
      inter_contains ty1 ty22
    | ty1, ty2 => ty1 == ty2

    -- make assoc right
    partial def intersect : Ty -> Ty -> Ty
    | .top, ty2 => ty2 
    | .unit, .tag _ _ => Ty.bot 
    | .tag _ _, .unit  => Ty.bot 
    | .tag l1 ty1, .tag l2 ty2  => 
      if l1 != l2 then
        Ty.bot 
      else
        .tag l1 (intersect ty1 ty2)
    | .tag l1 ty1, Ty.union ty21 ty22  => 
      Ty.union 
        (intersect (.tag l1 ty1) ty21) 
        (intersect (.tag l1 ty1) ty22)

    | Ty.union ty21 ty22, .tag l1 ty1 => 
      Ty.union 
        (intersect (.tag l1 ty1) ty21) 
        (intersect (.tag l1 ty1) ty22)

    | .bot, _ => .bot 
    | .inter ty11 ty12, ty2 => intersect ty11 (intersect ty12 ty2) 
    | ty1, .top => ty1 
    | _, .bot => .bot 
    | ty1, ty2 => 
        if ty1 == ty2 then
          ty1
        else if inter_contains ty1 ty2 then
          ty1
        else if inter_contains ty2 ty1 then
          ty2
        else
          .inter ty1 ty2


    -- assume assoc right
    def union_contains : Ty -> Ty -> Bool 
    | ty1, .union ty21 ty22 => 
      union_contains ty1 ty21 ||
      union_contains ty1 ty22
    | ty1, ty2 => ty1 == ty2

    -- make assoc right
    def unionize : Ty -> Ty -> Ty
    | .top, _ => .top
    | .bot, ty2 => ty2
    | .union ty11 ty12, ty2 => unionize ty11 (unionize ty12 ty2) 
    | _, .top => .top 
    | ty1, .bot => ty1
    | ty1, ty2 => 
        if ty1 == ty2 then
          ty1
        else if union_contains ty1 ty2 then
          ty1
        else if union_contains ty2 ty1 then
          ty2
        else
          .union ty1 ty2

    def intersect_over (f : (Ty × Ty) -> Ty) (constraints : List (Ty × Ty)) : Ty :=
      (constraints.foldr (fun (lhs, rhs) ty_acc =>
        intersect (f (lhs, rhs)) ty_acc 
      ) Ty.top)

    partial def simplify : Ty -> Ty
    | .bvar id => .bvar id  
    | .fvar id => .fvar id
    | .unit => .unit 
    | .top => .top
    | .bot => .bot 
    | .tag l ty => .tag l (simplify ty) 
    | .field l ty => .field l (simplify ty) 
    | .union ty1 ty2 => unionize (simplify ty1) (simplify ty2)
    | .inter ty1 ty2 => intersect (simplify ty1) (simplify ty2)
    | .impli ty1 ty2 => .impli (simplify ty1) (simplify ty2)
    | .exis n cty1 cty2 ty => 
      .exis n (simplify cty1) (simplify cty2) (simplify ty)
    | .univ op_ty_c ty => 
      .univ (op_ty_c.map simplify) (simplify ty)
    | .induc ty => .induc (simplify ty)


    def record_fields : Ty -> PHashMap String Ty
    | .field l ty => empty.insert l ty
    | .inter (.field l ty1) ty2 => 
      let linear_ty2 := (record_fields ty2) 
      match linear_ty2.find? l with
      | some ty_old => linear_ty2.insert l (Ty.inter ty1 ty_old)
      | none => linear_ty2.insert l ty1
    | .inter ty1 (.field l ty2) => 
      let linear_ty1 := (record_fields ty1)
      match linear_ty1.find? l with
      | some ty_old => linear_ty1.insert l (Ty.inter ty2 ty_old)
      | none => linear_ty1.insert l ty2
    | _ => empty 

    partial def wellformed_key : Ty -> Bool
    | .bvar id => false 
    | .fvar id => true 
    | .unit => false 
    | .top => false 
    | .bot => false 
    | .tag l ty => (wellformed_key ty) 
    | .field l ty => (wellformed_key ty)
    | .union ty1 ty2 => false 
    | .inter ty1 ty2 => 
      let fields := (record_fields (.inter ty1 ty2)).toList
      fields.all (fun (l, ty) => wellformed_key ty)
    | .impli ty1 ty2 => false 
    | .exis n ty_c1 ty_c2 ty => false
    | .univ op_ty_c ty => false
    | .induc ty => false

    partial def subst_while (f : Ty -> Bool) (m : PHashMap Nat Ty) : Ty -> Ty
    | .bvar id => .bvar id 
    | .fvar id => (match m.find? id with
      | some ty => 
        let ty := simplify ty
        if f ty then
          subst_while f m ty 
        else
          .fvar id
      | none => .fvar id
    )
    | .unit => .unit
    | .top => .top
    | .bot => .bot
    | .tag l ty => .tag l (subst_while f m ty) 
    | .field l ty => .field l (subst_while f m ty)
    | .union ty1 ty2 => .union (subst_while f m ty1) (subst_while f m ty2)
    | .inter ty1 ty2 => .inter (subst_while f m ty1) (subst_while f m ty2)
    | .impli ty1 ty2 => .impli (subst_while f m ty1) (subst_while f m ty2)
    | .exis n ty_c1 ty_c2 ty => (.exis n
      (subst_while f m ty_c1) (subst_while f m ty_c2) 
      (subst_while f m ty)
    )
    | .univ op_ty_c ty => 
      (.univ (op_ty_c.map (subst_while f m)) (subst_while f m ty))
    | .induc ty => .induc (subst_while f m ty)

    partial def sub_nonneg (boundary : Nat) (m : PHashMap Nat Ty) (negs : PHashSet Nat) : Ty -> Ty
    | .bvar id => .bvar id 
    | .fvar id => 
      if id >= boundary && negs.contains id then
        (match m.find? id with
          | some ty => 
            sub_nonneg boundary m negs ty 
          | none => .fvar id
        )
      else .fvar id 
    | .unit => .unit
    | .top => .top
    | .bot => .bot
    | .tag l ty => .tag l (sub_nonneg boundary m negs ty) 
    | .field l ty => .field l (sub_nonneg boundary m negs ty)
    | .union ty1 ty2 => .union (sub_nonneg boundary m negs ty1) (sub_nonneg boundary m negs ty2)
    | .inter ty1 ty2 => .inter (sub_nonneg boundary m negs ty1) (sub_nonneg boundary m negs ty2)
    | .impli ty1 ty2 => 
      let new_negs := free_vars ty1
      .impli ty1 (sub_nonneg boundary m (negs + new_negs) ty2)
    | .exis n ty_c1 ty_c2 ty => (.exis n
      (sub_nonneg boundary m negs ty_c1) (sub_nonneg boundary m negs ty_c2) 
      (sub_nonneg boundary m negs ty)
    )
    | .univ op_ty_c ty => 
      (.univ (op_ty_c.map (sub_nonneg boundary m negs)) (sub_nonneg boundary m negs ty))
    | .induc ty => .induc (sub_nonneg boundary m negs ty)


    declare_syntax_cat lesstype


    syntax:100 num : lesstype 
    syntax:100 ident : lesstype
    syntax:90 "β["lesstype:100"]" : lesstype
    syntax:90 "α["lesstype:100"]" : lesstype
    syntax:90 "unit" : lesstype
    syntax:90 "⊤" : lesstype
    syntax:90 "⊥" : lesstype
    syntax:90 "?" lesstype:100 lesstype:90 : lesstype
    syntax:90 lesstype:100 ":" lesstype:90 : lesstype
    syntax:50 lesstype:51 "->" lesstype:50 : lesstype
    syntax:60 lesstype:61 "|" lesstype:60 : lesstype
    syntax:70 lesstype:71 "&" lesstype:70 : lesstype
    syntax:70 lesstype:71 "*" lesstype:70 : lesstype


    -- constraints
    syntax:40 lesstype "<:" lesstype : lesstype
    syntax:40 lesstype "<:" lesstype "," lesstype: lesstype
    ------------

    syntax "{" lesstype "//" lesstype:41 "with" lesstype "}": lesstype 
    syntax "{" lesstype "//" lesstype:41 "}" : lesstype 

    syntax "{" lesstype:41 "with" lesstype "}": lesstype 
    syntax "{" lesstype:41 "}" : lesstype 

    syntax:50 lesstype:51 ">>" lesstype:50 : lesstype 
    syntax:50 "?" ">>" lesstype:50 : lesstype 

    syntax "induct" lesstype:40 : lesstype 

    syntax "(" lesstype ")" : lesstype

    syntax "⟨" term "⟩" : lesstype 

    syntax "[lesstype| " lesstype "]" : term

    macro_rules
    -- terminals
    | `([lesstype| $n:num ]) => `($n)
    | `([lesstype| $a:ident]) => `($(Lean.quote (toString a.getId)))
    -- Ty 
    | `([lesstype| β[$n] ]) => `(Ty.bvar [lesstype| $n ])
    | `([lesstype| α[$n:lesstype] ]) => `(Ty.fvar [lesstype| $n ])
    | `([lesstype| unit ]) => `(Ty.unit)
    | `([lesstype| ⊤ ]) => `(Ty.top)
    | `([lesstype| ⊥ ]) => `(Ty.bot)
    | `([lesstype| ? $a $b:lesstype ]) => `(Ty.tag [lesstype| $a ] [lesstype| $b ])
    | `([lesstype| $a : $b:lesstype ]) => `(Ty.field [lesstype| $a ] [lesstype| $b ])
    | `([lesstype| $a -> $b ]) => `(Ty.impli [lesstype| $a ] [lesstype| $b ])
    | `([lesstype| $a | $b ]) => `(Ty.union [lesstype| $a ] [lesstype| $b ])
    | `([lesstype| $a & $b ]) => `(Ty.inter [lesstype| $a ] [lesstype| $b ])
    | `([lesstype| $a * $b ]) => `(Ty.inter (Ty.field "l" [lesstype| $a ]) (Ty.field "r" [lesstype| $b ]))


    -- constraints
    | `([lesstype| $b <: $c  ]) => `([([lesstype| $b ],[lesstype| $c ])])
    | `([lesstype| $b <: $c , $xs ]) => `(([lesstype| $b ],[lesstype| $c ]) :: [lesstype| $xs])
    --------------

    | `([lesstype| { $n // $d with $xs }  ]) => 
      `(intersect_over (fun (lhs, rhs) => Ty.exis [lesstype| $n ] lhs rhs [lesstype| $d ]) [lesstype| $xs ])

    | `([lesstype| { $n // $b:lesstype } ]) => `(Ty.exis [lesstype| $n ] Ty.unit Ty.unit [lesstype| $b ] )

    | `([lesstype| { $d with $xs}  ]) => 
      `(intersect_over 
        (fun (lhs, rhs) => Ty.exis (Ty.infer_abstraction 0 [lesstype| $d ]) lhs rhs [lesstype| $d ])
        [lesstype| $xs]
      )

    | `([lesstype| { $b:lesstype } ]) => 
      `(Ty.exis (Ty.infer_abstraction 0 [lesstype| $b ]) Ty.unit Ty.unit [lesstype| $b ] )

    | `([lesstype| ? >> $d  ]) => 
      `(Ty.univ none [lesstype| $d ])

    | `([lesstype| $a >> $d  ]) => 
      `(Ty.univ (some [lesstype| $a ]) [lesstype| $d ])

    | `([lesstype| induct $a ]) => `(Ty.induc [lesstype| $a ])

    | `([lesstype| ($a) ]) => `([lesstype| $a ])

    | `([lesstype| ⟨ $e ⟩ ]) => pure e


    partial def repr (ty : Ty) (n : Nat) : Format :=
    match ty with
    | .bvar id => 
      "β[" ++ Nat.repr id ++ "]"
    | .fvar id =>
      "α[" ++ Nat.repr id ++ "]"
    | .unit => "unit" 
    | .top => "⊤" 
    | .bot => "⊥" 
    | .tag l ty1 => 
      ("?" ++ l ++ " " ++ (repr ty1 n))
    | .field l ty1 => 
      Format.bracket "(" (l ++ " : " ++ (repr ty1 n)) ")"

    | .union ty1 ty2 =>
      let _ : ToFormat Ty := ⟨fun ty' => repr ty' n ⟩
      let tys := [ty1, ty2] 
      Format.bracket "("
        (Format.joinSep tys (" |" ++ Format.line))
      ")"
  
    | .inter (.field "l" l) (.field "r" r) =>
      Format.bracket "(" ((repr l n) ++ " * " ++ (repr r n)) ")"
    | .inter ty1 ty2 =>
      Format.bracket "(" ((repr ty1 n) ++ " & " ++ (repr ty2 n)) ")"
    | .impli ty1 ty2 =>
      Format.bracket "(" ((repr ty1 n) ++ " ->" ++ Format.line ++ (repr ty2 n)) ")"
    | .exis var_count ty_c1 ty_c2 ty_pl =>
      if (ty_c1, ty_c2) == (.unit, .unit) then
        Format.bracket "{" (
          (Nat.repr var_count) ++ " // " ++
          repr ty_pl n
        ) "}"
      else
        Format.bracket "{" (
          (Nat.repr var_count) ++ " // " ++
          (repr ty_pl n) ++ " with " ++
          (repr ty_c1 n) ++ " <: " ++ (repr ty_c2 n)
        ) "}"
    | .univ op_ty_c ty_pl =>
      match op_ty_c with
      | none =>
        Format.bracket "(" ("? >> " ++ (repr ty_pl n)) ")"
      | some ty_c =>
        Format.bracket "(" (
          (repr ty_c n) ++ " >> " ++ (repr ty_pl n)
        ) ")"
    | .induc ty1 =>
      Format.bracket "(" (
        "induct " ++ (repr ty1 n)
      ) ")"

    instance : Repr Ty where
      reprPrec := repr


  def PHashMap.repr [Repr α] [Repr β] [Repr (α × β)] [BEq α] [Hashable α] 
  (m : PHashMap α β) (n : Nat) : Format :=
    Format.bracket "<" (List.repr (toList m) n) ">"

  instance [Repr α] [Repr β] [Repr (α × β)] [BEq α] [Hashable α] : Repr (PHashMap α β) where
    reprPrec := PHashMap.repr


  def PHashSet.repr [Repr α] [BEq α] [Hashable α] 
  (m : PHashSet α) (n : Nat) : Format :=
    Format.bracket "{" (List.repr (toList m) n) "}"

  instance [Repr α] [BEq α] [Hashable α] : Repr (PHashSet α) where
    reprPrec := PHashSet.repr

------------------------------------------------------------

    #eval [lesstype| {β[0] with β[0] <: ?ooga unit, β[0] <: ?booga unit} ]
    #eval [lesstype| {β[0] with β[0] <: ?ooga unit} ]

    #eval [lesstype| {1 // β[0] with (β[1] * β[0]) <: ?booga unit} ] 
    #eval [lesstype| {1 // β[0] with β[1] * β[0] <: ?booga unit} ] 
    #eval [lesstype| ?ooga unit >> β[0] -> {1 // β[0] with β[1] * β[0] <: ?booga unit} ] 

------------------------------------------------------------


    def nested_pairs : (List Ty) -> Ty 
    | [] => .unit 
    | ty :: tys => [lesstype| ⟨ty⟩ * ⟨nested_pairs tys⟩ ]

    def no_function_types: Ty -> Bool
    | .bvar _ => true  
    | .fvar _ => true  
    | .unit => true 
    | .top => true 
    | .bot => true 
    | .tag _ content => no_function_types content
    | .field _ content => no_function_types content
    | .union ty1 ty2 => 
      no_function_types ty1 && 
      no_function_types ty2
    | .inter ty1 ty2 => 
      no_function_types ty1 && 
      no_function_types ty2
    | .impli _ _ => false
    | .exis n ty_c1 ty_c2 ty_pl =>
      no_function_types ty_c1 && 
      no_function_types ty_c2 && 
      no_function_types ty_pl
    | .univ op_ty_c ty_pl =>
      (match op_ty_c with 
      | none => true
      | some ty_c => no_function_types ty_c
      ) && 
      no_function_types ty_pl
    | .induc content => no_function_types content 

    partial def index_free_vars (initial : PHashMap Nat (PHashSet Ty)) (ty : Ty) : PHashMap Nat (PHashSet Ty) :=
      let fids := toList (free_vars ty)
      fids.foldl (fun acc fid =>
        match acc.find? fid with
        | some keys => 
          if keys.contains ty then 
            acc
          else
            acc.insert fid (keys.insert ty)
        | none => acc.insert fid (empty.insert ty)
      ) initial 


      ---------------------------------------
      -- let constraints_acc := (
      --     if constraints_acc.contains (Ty.fvar fid) then
      --       match context.env_simple.find? fid with
      --       | some ty_simple =>
      --         let constraints_acc := constraints_acc.insert (Ty.fvar fid) ty_simple 
      --         (reachable_constraints context ty_simple constraints_acc)
      --       | none => constraints_acc
      --     else
      --       constraints_acc
      -- )
      -------------------------------------------

    partial def reachable_constraints (context : Context) (ty : Ty) (constraints_acc : PHashMap Ty Ty) : PHashMap Ty Ty :=
      (free_vars ty).fold (fun constraints_acc fid =>
        let constraints_acc := (
          match context.env_keychain.find? fid with
          | some keychain =>
            keychain.fold (fun constraints_acc key =>
              if constraints_acc.contains key then
                constraints_acc
              else
                (match context.env_relational.find? key with
                | some relation => 
                  let constraints_acc := constraints_acc.insert key relation 
                  (reachable_constraints context relation constraints_acc)
                | none => 
                  -- invariant: this impli should never happen
                  constraints_acc 
                )
            ) constraints_acc
          | none => constraints_acc
        )
        constraints_acc 
      ) constraints_acc


    partial def pack (boundary : Nat) (context : Context) (negs : PHashSet Nat) (ty : Ty) :=
      -----------------------
      -- assumption: env_simple is cycle-free  
      -- keep variables that exist in parameter position; substitute variables that are only in return position 
      -- avoid substitution to allow constraint refinements
      -- recursively pack referenced variables as constraints
      -----------------------

      let ty := sub_nonneg boundary context.env_simple negs ty

      let fids := (free_vars ty)
      if fids.isEmpty then
        ty
      else 

        let constraints : PHashMap Ty Ty := empty

        -- simple constraints
        let constraints : PHashMap Ty Ty := fids.fold (fun constraints fid =>
          if fid >= boundary then
            match context.env_simple.find? fid with
            | some ty_simple =>
              constraints.insert (Ty.fvar fid) (pack boundary context (negs + fids) ty_simple) 
            | none => constraints
          else
            constraints
        ) constraints 

        -- relational constraints
        let constraints : PHashMap Ty Ty := fids.fold (fun constraints fid => 
          if fid >= boundary then
            match context.env_keychain.find? fid with
            | some keychain =>
              keychain.fold (fun constraints key =>
                (match context.env_relational.find? key with
                | some relation => 
                  let key := sub_nonneg boundary context.env_simple (negs + fids) key
                  if constraints.contains key then
                    constraints
                  else
                    constraints.insert key (pack boundary context (negs + fids) relation) 
                | none => 
                  -- invariant: this impli should never happen
                  constraints 
                )
              ) constraints
            | none => constraints
          else
            constraints
        ) constraints 


        if constraints.isEmpty then
          let list_fids := toList fids
          [lesstype| {⟨list_fids.length⟩ // ⟨abstract list_fids 0 ty⟩}  ]
        else
          intersect_over (fun (ty_lhs, ty_rhs) => 
            let fvs_constraints := fids + (free_vars ty_lhs) + (free_vars ty_rhs)
            let fids_c := List.filter (fun id => id >= boundary) (toList fvs_constraints)
            [lesstype|
              {⟨fids_c.length⟩ // ⟨abstract fids_c 0 ty⟩ with ⟨abstract fids_c 0 ty_lhs⟩ <: ⟨abstract fids_c 0 ty_rhs⟩}
            ]
          ) constraints.toList





    partial def instantiate (start : Nat) (args : List Ty) : Ty -> Ty
    | .bvar id => 
        if h : start ≤ id ∧ (id - start) < args.length then
          let i : Fin args.length := {
            val := (id - start),
            isLt := (match h with | And.intro _ h' => h') 
          } 
          args.get i 
        else
          .bvar id
    | .fvar id => .fvar id
    | .unit => .unit
    | .top => .top
    | .bot => .bot
    | .tag l ty => .tag l (instantiate start args ty) 
    | .field l ty => .field l (instantiate start args ty)
    | .union ty1 ty2 => .union (instantiate start args ty1) (instantiate start args ty2)
    | .inter ty1 ty2 => .inter (instantiate start args ty1) (instantiate start args ty2)
    | .impli ty1 ty2 => .impli (instantiate start args ty1) (instantiate start args ty2)
    | .exis n ty_c1 ty_c2 ty => 
      (.exis n
        (instantiate (start + n) args ty_c1) (instantiate (start + n) args ty_c2)
        (instantiate (start + n) args ty)
      )
    | .univ op_ty_c ty => 
      (.univ (Option.map (instantiate (start + 1) args) op_ty_c) (instantiate (start + 1) args ty)
      )
    | .induc ty => .induc (instantiate (start + 1) args ty)


    partial def occurs (m : Ty.Context) (key : Nat): Ty -> Bool 
    | .bvar id => false 
    | .fvar id => 
      (key == id) || 
      (match m.env_simple.find? id with
      | some ty => occurs m key ty 
      | none => 
        (match m.env_keychain.find? id with
        | some keychain => 
          (toList keychain).any (fun lower => 
            (match m.env_relational.find? lower with
            | some relation => occurs m key relation 
            | none => false
            )
          )
        | none => false
        )
      )
    | .unit => false 

    | .top => false 
    | .bot => false 
    | .tag l ty => occurs m key ty 
    | .field l ty => occurs m key ty
    | .union ty1 ty2 => (occurs m key ty1) || (occurs m key ty2)
    | .inter ty1 ty2 => (occurs m key ty1) || (occurs m key ty2)
    | .impli ty1 ty2 => (occurs m key ty1) || (occurs m key ty2)
    | .exis n ty_c1 ty_c2 ty => 
      (occurs m key ty_c1) || (occurs m key ty_c2) || (occurs m key ty)
    | .univ op_ty_c ty => 
      (match op_ty_c with
      | none => false
      | some ty_c => (occurs m key ty_c)) || (occurs m key ty)
    | .induc ty => (occurs m key ty)

    partial def subst_default (sign : Bool) : Ty -> Ty
    | .bvar id => .bvar id  
    | .fvar id => if sign then .bot else [lesstype| ⊤ ] 
    | .unit => .unit 
    | .top => .top
    | .bot => .bot 
    | .tag l ty => .tag l (subst_default sign ty) 
    | .field l ty => .field l (subst_default sign ty) 
    | .union ty1 ty2 =>
      .union (subst_default sign ty1) (subst_default sign ty2)
    | .inter ty1 ty2 =>
      .inter (subst_default sign ty1) (subst_default sign ty2)
    | .impli ty1 ty2 => .impli (subst_default (!sign) ty1) (subst_default sign ty2)
    | .exis n cty1 cty2 ty => 
      -- can't sub away if constrained
      .exis n cty1 cty2 ty
    | .univ op_ty_c ty => 
      -- can't sub away if constrained
      .univ op_ty_c ty
    | .induc ty => .induc (subst_default sign ty)

    partial def equiv (env_ty : PHashMap Nat Ty) (ty1 : Ty) (ty2 : Ty) : Bool :=
      let ty1 := simplify (subst env_ty ty1)
      let ty2 := simplify (subst env_ty ty2)
      ty1 == ty2

    def split_intersections : Ty -> List Ty 
    | Ty.inter ty1 ty2 =>
      (split_intersections ty1) ++ (split_intersections ty2)
    | ty => [ty]

    -- def linearize_fields : Ty -> Option (List (String × Ty))
    -- | .field l ty => some [(l, ty)]
    -- | .inter (.field l ty1) ty2 => 
    --   bind (linearize_fields ty2) (fun linear_ty2 =>
    --     (l, ty1) :: linear_ty2
    --   )
    -- | .inter ty1 (.field l ty2) => 
    --   bind (linearize_fields ty1) (fun linear_ty1 =>
    --     (l, ty2) :: linear_ty1
    --   )
    -- | .fvar _ => some [] 
    -- | _ => none

    -- def extract_nested_fields : Ty -> (List Ty)
    -- | .field l ty => [ty]
    -- | .inter (.field l ty1) ty2 => 
    --   match extract_nested_fields ty1 with
    --   | [] => ty1 :: (extract_nested_fields ty2)
    --   | nested_fields =>
    --     nested_fields ++ (extract_nested_fields ty2)
    -- | .inter ty1 (.field l ty2) => 
    --   match extract_nested_fields ty2 with
    --   | [] => ty2 :: (extract_nested_fields ty1)
    --   | nested_fields => nested_fields ++ (extract_nested_fields ty1)
    -- | _ => [] 


    partial def extract_record_labels : Ty -> PHashSet String
    | .field l ty => 
      empty.insert l
    | .union ty1 ty2 => 
      (extract_record_labels ty1) + (extract_record_labels ty2)
    | .inter ty1 ty2 => 
      let fields := toList (record_fields (Ty.inter ty1 ty2))
      from_list (fields.map (fun (l, _) => l))
    | .exis n ty_c1 ty_c2 ty => (extract_record_labels ty)
    | .induc ty => extract_record_labels ty
    | _ => {} 

    partial def extract_label_list (ty : Ty) : List String :=
      toList (extract_record_labels ty)

    def part_of_relational_key (context: Context) (key : Nat): Bool := 
      context.env_relational.toList.find? (fun (key_rel, _ ) =>
        let fids := free_vars key_rel
        fids.contains key
      ) != none

    def split_unions : Ty -> List Ty 
    | Ty.union ty1 ty2 =>
      (split_unions ty1) ++ (split_unions ty2)
    | ty => [ty]

    def extract_field (label : String) (ty : Ty) : Option Ty := do
      let fields := toList (record_fields ty)
      let fields_filt := fields.filter (fun (l, _) => l == label)
      if h : fields_filt.length > 0 then
        let (_, ty_fd) := (fields_filt.get ⟨0, h⟩)
        some ty_fd
      else
        none

    def extract_field_induct (label : String): Ty -> Option Ty 
    | .exis n ty (.bvar id) ty_pl => 
      -- assume β[n] is the inductive fixed point 
      if id == n then
        Option.bind (extract_field label ty) (fun ty => 
        Option.bind (extract_field label ty_pl) (fun ty_pl =>
          (Ty.exis n  ty (.bvar id) ty_pl)
        ))
      else 
        none
    | .exis n Ty.unit Ty.unit ty_pl => 
      Option.bind (extract_field label ty_pl) (fun ty_pl =>
        (Ty.exis n  Ty.unit Ty.unit ty_pl)
      )
    | ty => extract_field label ty 


    partial def factor_out_map (labels : List String) : Ty -> PHashMap String Ty 
    | Ty.induc ty =>
      let unions := split_unions ty
      labels.foldl (fun acc label =>
        let ty_col := unions.foldr (fun ty_row ty_col =>
          match extract_field_induct label ty_row with
          | some ty_field => Ty.union ty_field ty_col 
          | none => Ty.top
        ) Ty.bot 
        acc.insert label (Ty.induc (Ty.simplify ty_col))
      ) empty 
    | _ => 
      empty

    partial def factor_out_relation (labels : List String) (ty : Ty) : Ty :=
      let fields := toList (factor_out_map labels ty)
      fields.foldr (fun (label, ty_rec) ty_acc =>
        Ty.inter (Ty.field label ty_rec) ty_acc 
      ) Ty.top

    -- | Ty.induc ty =>
    --   let unions := split_unions ty
    --   labels.foldr (fun label ty_acc =>
    --     let ty_col := unions.foldr (fun ty_row ty_col =>
    --       match extract_field_induct label ty_row with
    --       | some ty_field => Ty.union ty_field ty_col 
    --       | none => Ty.top
    --     ) Ty.bot 
    --     Ty.inter (Ty.field label (Ty.induc ty_col)) ty_acc 
    --   ) Ty.top
    -- | ty => 
    --   Ty.top
    --   -- let unions := split_unions ty
    --   -- labels.foldr (fun label ty_acc =>
    --   --   let ty_col := unions.foldr (fun ty_row ty_col =>
    --   --     match extract_field label ty_row with
    --   --     | some ty_field => Ty.union ty_field ty_col 
    --   --     | none => Ty.top
    --   --   ) Ty.bot 
    --   --   Ty.inter (Ty.field label ty_col) ty_acc 
    --   -- ) Ty.top



    partial def decreasing (id_induct : Nat) : Ty -> Bool
    | .bvar id => id != id_induct 
    | .fvar _ => true 
    | .unit => true 
    | .top => true 
    | .bot => true 
    | .tag _ _ => true 
    | .field _ ty => decreasing id_induct ty
    | .union ty1 ty2 =>
      decreasing id_induct ty1 && decreasing id_induct ty2
    | .inter ty1 ty2 =>
      decreasing id_induct ty1 && decreasing id_induct ty2
    | .impli _ _ => false
    | .exis n' ty_c1 ty_c2 ty' => 
      match ty' with 
      | .tag _ _ => 
        decreasing (id_induct + n') ty_c1
      | _ =>
        decreasing (id_induct + n') ty_c1 &&
        decreasing (id_induct + n') ty_c2 && 
        decreasing (id_induct + n') ty'
    | .univ _ _ => false 
    | .induc _ => false 

    -- (fun ty_u => 
    --   match ty_u with
    --   | (Ty.tag _ _) => true
    --   | Ty.exis _ _ _ (Ty.tag _ _) => true
    --   | _ => false
    -- )


    -- check that ty_rec is wellfounded with respect to reducible column in ty_key
    partial def reducible (context : Ty.Context) (ty_key ty_rec : Ty) : Bool :=
      let ty_key := simplify (subst context.env_simple ty_key)  
      let fields := record_fields ty_key
      if fields.isEmpty then
        match ty_key with
        | Ty.fvar _ => false
        | Ty.tag _ _ =>
          match ty_rec with
          | Ty.induc ty_body =>
            let unions := split_unions ty_body
            unions.all (decreasing 0)
          | _ => false 
        | _ => false
      else
        -- for each label in ty_rec there is a label in keys
        let labels := toList (extract_record_labels ty_rec)
        let ty_factored := toList (factor_out_map labels ty_rec)
        ty_factored.any (fun (l, ty_rec) =>
          match fields.find? l with
          | some ty_key => reducible context ty_key ty_rec
          | none => false
        )  


    def merge_contexts (c1 c2 : Ty.Context) : Ty.Context :=
      {
        env_simple := c1.env_simple;c2.env_simple,
        env_keychain := c1.env_keychain;c2.env_keychain
        env_relational := c1.env_relational;c2.env_relational
      }



    def constraint_unchanged (id : Nat) (context : Ty.Context) (contexts' : List Ty.Context) : Bool :=  
      contexts'.all (fun context' => 
        context'.env_simple.find? id == context.env_simple.find? id &&
        match context.env_keychain.find? id, context'.env_keychain.find? id with
        | some kc, some kc' => kc'.fold (fun result key => result && kc.contains key) true
        | none, none => true 
        | _, _ => false
      )


    partial def unify (i : Nat) (context : Context)
    : Ty -> Ty -> (Nat × List Context)

    -- existential quantifier elimination (closed variables) (proactive) 
    | .exis n ty_c1 ty_c2 ty1, ty2 => (
      let (i, ids_bound) := (i + n, (List.range n).map (fun j => i + j))

      let args := ids_bound.map (fun id => Ty.fvar id)
      let ty_c1 := instantiate 0 args ty_c1
      let ty_c2 := instantiate 0 args ty_c2
      let ty1 := instantiate 0 args ty1

      let env_simple_unchanged : List Ty.Context -> Option Ty.Context := (fun new_contexts => 
        match new_contexts with
        | [new_context] => 
          if new_context.env_simple.toList == context.env_simple.toList then
            some new_context
          else
            none
        | _ => none
      )


      -- TODO: substitute in order to prevent unsafe constraint refinements
      -- constraint is a requirement; not an observation
      let (i, contexts_constraint) := (unify i context ty_c1 ty_c2)

      match env_simple_unchanged contexts_constraint with 
      | some context_constraint => 
        let (i, contexts) := (unify i context_constraint ty1 ty2) 
        -- ensure that opaque variables are not bound from payload unification
        let result_safe := ids_bound.all (fun id => constraint_unchanged id context_constraint contexts)
        if result_safe then
          (i, contexts)
        else
          (i, [])
      | none => 
        let op := contexts_constraint.foldl (fun op_i_contexts context_constraint =>
          op_i_contexts.bind (fun (i, contexts) =>
            let (i, contexts') := (unify i context_constraint ty1 ty2)

            if !contexts'.isEmpty && (ids_bound.all (fun id => constraint_unchanged id context_constraint contexts')) then
              some (i, contexts ++ contexts')
            else
              none
          )
        ) (some (i, []))

        match op with
        | some (i, contexts) => (i, contexts)
        | none => (i, [])
    ) 


    -- universal quantifier introduction (closed variables) (proactive)
    | ty1, .univ op_ty_c ty2  => (
      let id_bound := i
      let i := i + 1

      let args := [Ty.fvar id_bound]
      let op_ty_c := Option.map (instantiate 0 args) op_ty_c
      let ty2 := instantiate 0 args ty2


      -- TODO: substitute in order to prevent unsafe constraint refinements
      -- constraint is a requirement; not an observation
      -- CAREFUL: substitution could cause the same unification problem to repeat infinitely
      let context := match op_ty_c with
      | none => context
      | some ty_c => {context with 
        env_simple := context.env_simple.insert id_bound ty_c
      }

      let (i, contexts) := (unify i context ty1 ty2)
      let result_safe := constraint_unchanged id_bound context contexts
      if result_safe then
        (i, contexts)
      else
        (i, [])
      -----------------------------
    )

    -- existential quantifier introduction (open variables) (reactive)
    | ty', .exis n ty_c1 ty_c2 ty =>
      let (i, args) := (
        i + n, 
        (List.range n).map (fun j => Ty.fvar (i + j))
      )

      let ty_c1 := instantiate 0 args ty_c1
      let ty_c2 := instantiate 0 args ty_c2
      let ty := instantiate 0 args ty

      -- NOTE: unify constraint last, as quantified variables should react to unification of payloads
      bind_nl (unify i context ty' ty) (fun i context => 
        -- NOTE: substitute in order to prevent unsafe constraint refinements
        -- constraint is a requirement; not an observation
        let ty_c1 := (simplify (subst context.env_simple ty_c1))
        let ty_c2 := (simplify (subst context.env_simple ty_c2))
        unify i context ty_c1 ty_c2
      )


    -- universal quantifier elimination (open variables) (reactive)
    | .univ op_ty_c ty1, ty2 =>
      let (i, id_bound) := (i + 1, i)
      let args := [Ty.fvar id_bound]

      let op_ty_c := Option.map (instantiate 0 args) op_ty_c
      let ty1 := instantiate 0 args ty1

      -- NOTE: unify constraint last, as quantified variables should react to unification of payloads
      bind_nl (unify i context ty1 ty2) (fun i context => 
        match op_ty_c with
        | none => (i, [context])
        | some ty_c => (
          -- TODO: substitute in order to prevent unsafe constraint refinements
          -- constraint is a requirement; not an observation
          -- CAREFUL: substitution could cause the same unification problem to repeat infinitely
          -- must check that id_bound does not map back to lhs (.univ op_ty_c ty1)
          -- NOTE: perhaps this could be solved using a simple equality check
            -- at the very beginning of unification
            -- this would prevent a variable on the mapping back to the lhs
          -----------------------------------
          -- subbing the id_bound causes strange non-termination
          -- let ty_b := (simplify (subst context.env_simple (Ty.fvar id_bound)))
          -- let ty_c := (simplify (subst context.env_simple ty_c))
          -- unify i context ty_b ty_c
          ----------------------------

          -------------------------------------
          let op_ty_b := context.env_simple.find? id_bound 
          match op_ty_b with
          | some ty_b => 
            (unify i context ty_b ty_c)
          | none => 
            (i, [{context with env_simple := context.env_simple.insert id_bound ty_c}])
        )
      )

    ---------------------------------------------------------------
    -- free variables
    ---------------------------------------------------------------

    | ty', .fvar id => 
      ----------------------
      -- NOTE: this executes before the left-variable on rule. in impli where ty' is also an unassgined variable, save as rhs maps to lhs. 
        -- Enables freed existential vars (rhs) to map to closed existential vars (lhs). 
      -- adjustment here records observed types; based on unioning fresh variable
      -- assymetrical mechanism, since free variables have the meaning of Top, and environment tracks upper bounds
      -- when the environment is packed as a constraint; it becomes id <: ty', so we need union to make id <: ty' | Top
      -- NAT <: X with X * _ <: NAT_LIST fails because NAT * _ <: NAT_LIST fails 
      -- ?zero unit <: X with X * _ <: NAT_LIST succeeds because ?zero unit * _ <: NAT_LIST succeeds 
      --------------------

      match context.env_simple.find? id with 
      | some ty => 
        let (i, contexts) := (unify i context ty' ty) 

        if !contexts.isEmpty then
          (i, contexts)
        else if !occurs context id ty' then
          let context := {context with env_simple := context.env_simple.insert id (Ty.unionize ty' ty)}
          (i, [context])
        else
          (i, [])
        ----------------------------------------------

      | none => 
        --- check env_relational
        match context.env_keychain.find? id with
        | some keychain =>
          keychain.fold (fun (i, contexts) key =>
            bind_nl (i, contexts) (fun i context => 
              match context.env_relational.find? key with
              | some relation => 
                let env_sub : PHashMap Nat Ty := empty.insert id ty'
                -- TODO: sub key and relation to prevent unsafe constraint refinements 
                -- occurs check
                -- let context := ... with context.env_simple.insert id ty'
                -- let ty_sub := subst context.env_simple key 
                let ty_sub := subst env_sub key  
                (unify i context ty_sub relation) 
              | none => 
                -- invariant: this never happens
                (i, [])
            )
          ) (i, [context])
        | none => (
          if (Ty.fvar id) == ty' then
            (i, [context])
          else if occurs context id ty' then
            (i, [])
          else
            (i, [{context with env_simple := context.env_simple.insert id ty' }])
        )
      ---------------------------------------

    | .fvar id, ty  => 
      ----------------------------
      -- adjustment updates the variable assignment to lower the upper bound 
      ---------------------------
      -- check env_simple first
      -- then check env_keychain
        -- check if the relational constraints can be solved 

      match context.env_simple.find? id with 
      | some ty' => 
        let (i, contexts) := (unify i context ty' ty)
        if !contexts.isEmpty then
          (i, contexts)
        else 
          let (i, contexts_reversed) := (unify i context ty ty')
          -- pick the simplest lower bound
          let ty_assign := (
            if !contexts_reversed.isEmpty then
              ty
            else
              (Ty.inter ty ty')
          )
          if (Ty.fvar id) == ty_assign then
            (i, [context])
          else if (occurs context id ty_assign) then
            (i, [])
          else
            let context := {context with env_simple := context.env_simple.insert id ty_assign}
            (i, [context])
      | none => 
        match context.env_keychain.find? id with
        | some keychain =>
          keychain.fold (fun (i, contexts) key =>
            bind_nl (i, contexts) (fun i context => 
            match context.env_relational.find? key with
            | some relation =>

                -- check that new constraint is weaker than relational constraint  
                -- weakening is only safe if the constraint is not over parameter type 
                -- assumption: relations do not constraintfunction parameter types

                let env_sub : PHashMap Nat Ty := empty.insert id ty
                let ty_sub := subst env_sub key  
                let ty_weak := (
                  let fids := toList (free_vars ty_sub)
                  [lesstype| {⟨fids.length⟩ // ⟨abstract fids 0 ty_sub⟩} ] 
                )
                -- unify relational lhs and constructed relational rhs 
                let (i, contexts_oracle) := (unify i context relation ty_weak)

                if !contexts_oracle.isEmpty then
                  (i, [context])
                else if (occurs context id ty) then
                    (i, [])
                else (
                  let context := {context with env_simple := context.env_simple.insert id ty}
                  (i, [context])
                )
              -- opaque_wrap context id (fun context =>
              -- )
            | none => 
              -- invariant: this should never happen
              (i, [])
            )
          ) (i, [context])
        | none =>
          if (Ty.fvar id) == ty then
            (i, [context])
          else if (occurs context id ty) then
            (i, [])
          else
            let context := {context with env_simple := context.env_simple.insert id ty}
            (i, [context])

    -------------------------------------

    | .impli (Ty.fvar id) ty_body, .impli ty_arg ty_res =>

      -- substitution to prevent weakening 
      let (i, contexts) := unify i context ty_arg (subst context.env_simple (Ty.fvar id)) 
      if contexts.isEmpty then
        (i, [])
      else
        let contexts := contexts.map (fun context => 
          if occurs context id ty_arg then
            context
          else
            {context with env_simple := context.env_simple.insert id ty_arg }
        )

        bind_nl (i, contexts) (fun i context =>
          -- substitution to prevent strengthening 
          -- but still allow weakening 
          (unify i context (subst context.env_simple ty_body) ty_res)
        ) 


    | .impli ty_param ty_body, .impli ty_arg ty_res =>

      -- substitution to prevent weakening 
      -- but still allow strengthening 
      bind_nl (unify i context ty_arg (subst context.env_simple ty_param)) (fun i context =>
          -- substitution to prevent strengthening 
          -- but still allow weakening 
        (unify i context (subst context.env_simple ty_body) ty_res)
      ) 

    /-
    Itersection elimination. 

    T ⊑ (P -> R)
    ---------------------------
    T ⊑ (P & Q -> R)

    P ⊑ T 
    ---------------------------
    P & Q ⊑ T 

    -/



    -- | ty1, .impli (.exis n ty_c1 ty_c2 ty_pl) ty3 =>
    --   -- TODO: reconsider if this rule is needed 
    --   -- TODO: safety check
    --   -- NOTE: special impli to ensure that variables are instantiated before decomposition of lhs
    --   let ty2 := (.exis n ty_c1 ty_c2 ty_pl)
    --   let (i, ty2') := (i + 1, Ty.fvar i)
    --   bind_nl (unify i context ty1 (.impli ty2' ty3)) (fun i context =>
    --     (unify i context ty2 ty2')
    --   )

    | .bvar id1, .bvar id2  =>
      if id1 = id2 then 
        (i, [context])
      else
        (i, [])

    | .bot, _ => (i, [context])
    | _, .top => (i, [context])
    | .unit, .unit => (i, [context])

    | .tag l' ty', .tag l ty =>
      if l' = l then
        unify i context ty' ty
      else
        (i, [])

    | .field l' ty', .field l ty =>
      if l' == l then
        unify i context ty' ty
      else
        (i, [])

    | .induc ty1, .induc ty2 =>
      if equiv context.env_simple ty1 ty2 then
        (i, [context])
      else
        -- using induction hypothesis, ty1 ≤ ty2; safely unroll
        let ty1' := instantiate 0 [.induc ty2] ty1
        let ty2' := instantiate 0 [.induc ty2] ty2
        unify i context ty1' ty2'

    | .induc ty1, ty2 =>
      let labels := extract_label_list ty2 
      let ty_factored := (factor_out_relation labels (.induc ty1))
      unify i context ty_factored ty2
    --------------------------------------------------
      -- if equiv context.env_simple (.induc ty1) ty2 then
      --   (i, [context])
      -- else
      --   -- using induction hypothesis, ty1 ≤ ty2; safely unroll
      --   let ty1' := instantiate 0 [ty2] ty1
      --   let (i, contexts) := unify i context ty1' ty2
      --   if contexts.isEmpty then
      --       -- factor_out to find some valid unification
      --       let labels := extract_label_list ty2 
      --       let ty_factored := (factor_out_relation labels (.induc ty1))
      --       unify i context ty_factored ty2
      --   else 
      --     (i, contexts)

    | ty', .induc ty =>
      -- let ty' := (simplify (subst context.env_simple ty'))
      if reducible context ty' (.induc ty) then
        unify i context ty' (instantiate 0 [Ty.induc ty] ty) 
      else
        match context.env_relational.find? ty' with
        | .some ty_cache => 
          unify i context ty_cache (Ty.induc ty)
        | .none => (
          let occurence := (toList (free_vars ty')).any (fun key => occurs context key (.induc ty)) 
          let rlabels := extract_record_labels ty' 
          let is_consistent_variable_record := !rlabels.isEmpty && List.all (toList (extract_record_labels (.induc ty))) (fun l =>
              rlabels.contains l 
            )
          if is_consistent_variable_record && !occurence && wellformed_key ty' then
            let context := {context with 
              env_keychain := index_free_vars context.env_keychain ty' 
              env_relational := context.env_relational.insert ty' (.induc ty),
            }
            (i, [context])
          else 
            (i, []) 
        )

    -- left-implication-union 
    | ty1, .impli (Ty.union ty_u1 ty_u2) ty2 =>
      bind_nl (unify i context ty1 (Ty.impli ty_u1 ty2)) (fun i context =>
        unify i context ty1 (Ty.impli ty_u2 ty2)
      )

    -- left-union
    | Ty.union ty1 ty2, ty => 
      bind_nl (unify i context ty1 ty) (fun i context =>
        (unify i context ty2 ty)
      )

    -- right-union
    | ty, .union ty1 ty2 => 
      let (i, contexts_ty1) := (unify i context ty ty1)
      let (i, contexts_ty2) := (unify i context ty ty2)
      (i, contexts_ty1 ++ contexts_ty2)

    -- right-implication-intersection
    | ty1, .impli ty2 (Ty.inter ty_u1 ty_u2) =>
       bind_nl (unify i context ty1 (Ty.impli ty2 ty_u1)) (fun i context =>
         unify i context ty1 (Ty.impli ty2 ty_u2)
       )

    -- right-intersection
    | ty, .inter ty1 ty2 => 
      bind_nl (unify i context ty ty1) (fun i context =>
        (unify i context ty ty2)
      )

    -- left-intersection
    | .inter ty1 ty2, ty => 
      let (i, contexts_ty1) := (unify i context ty1 ty)
      let (i, contexts_ty2) := (unify i context ty2 ty)
      (i, contexts_ty1 ++ contexts_ty2)

    | _, _ => (i, []) 

    partial def compress (boundary : Nat) (context : Context) (ty : Ty) :=
      -----------------------
      -- assumption: env_simple is cycle-free  
      -----------------------

      let ty := simplify (subst context.env_simple ty)

      let fids := (free_vars ty)
      if fids.isEmpty then
        ty
      else 

        let constraints : PHashMap Ty Ty := empty

        -- relational constraints
        let constraints : PHashMap Ty Ty := fids.fold (fun constraints fid => 
          if fid >= boundary then
            match context.env_keychain.find? fid with
            | some keychain =>
              keychain.fold (fun constraints key =>
                (match context.env_relational.find? key with
                | some relation => 
                  let key := subst context.env_simple key
                  if constraints.contains key then
                    constraints
                  else
                    constraints.insert key (compress boundary context relation) 
                | none => 
                  -- invariant: this impli should never happen
                  constraints 
                )
              ) constraints
            | none => constraints
          else
            constraints
        ) constraints 


        if constraints.isEmpty then
          ty
        else
          intersect_over (fun (ty_lhs, ty_rhs) => 
            let fvs_constraints := (free_vars ty_lhs)
            let fids_c := List.filter (fun id => id >= boundary) (toList fvs_constraints)
            [lesstype|
              {⟨fids_c.length⟩ // ⟨abstract fids_c 0 ty⟩ with ⟨abstract fids_c 0 ty_lhs⟩ <: ⟨abstract fids_c 0 ty_rhs⟩}
            ]
          ) constraints.toList

    def generalize (boundary : Nat) (context : Context) (ty : Ty) : Ty := (
      -- TODO: figure out way to solve relational constraints to simplify type 
      --------------------------------------
      -- boundary prevents overgeneralizing

      -- sub in simple types; 
      -- subbing prevents strengthening from the outside in 
      -- only the body type (conclusion) can safely strengthen the parameter type (the premise)  
      -- subbing does not prevent weakening, as weakining is handles adding unions of fresh variables  
      --------------------------------------

      -----------------------------
      -- TODO:
      -- rely on pack which does not sub in for parameters
      ---------------------------
        -- let ty_ex := pack boundary context empty ty
        -- [lesstype| ⟨ty_ex⟩ >> β[0]]
      -----------------------
      -----------------------
      let ty := simplify (subst context.env_simple ty)
      let fids_pl := List.filter (fun id => id >= boundary) (toList (free_vars ty))
      -- let constrained := fids_pl.any (fun fid => context.env_keychain.contains fid)  

      if fids_pl.isEmpty then
          ty
      -- else if no_function_types ty then
      --   let env_sub := PHashMap.from_list (
      --     fids.map (fun fid => (fid, Ty.bot))
      --   )
      --   simplify (subst env_sub ty)
      -- else if !constrained then
      --   -- NOTE: need to use universal in order to indicate weakening is allowed for unconstrained variables.
      --   (List.range fids_pl.length).foldl (fun ty_acc _ =>
      --     [lesstype| ? >> ⟨ty_acc⟩]
      --   ) (abstract fids_pl 0 ty)
      else (
        let ty_compressed := compress boundary context ty
        let ty_base := [lesstype| ⟨ty_compressed⟩ >> β[0]]
        (List.range fids_pl.length).foldl (fun ty_acc _ =>
          [lesstype| ? >> ⟨ty_acc⟩]
        ) (abstract fids_pl 0 ty_base) 
      )
      -----------------------
    )



    partial def union_all : (List Ty) -> Option Ty
      | [] => none
      | t::ts =>
        let ts := List.filter
          (fun t' => not (t == t'))
          ts
        match union_all ts with
          | .none => .some t
          | .some t' => Ty.union t t'

    partial def unify_reduce_env (i : Nat) (env_simple : PHashMap Nat Ty) (ty1) (ty2) (ty_result) :=
      let context : Context := Context.mk env_simple empty empty
      let boundary := 0 
      let (_, contexts) : Nat × List Context := (unify i context ty1 ty2)
      List.foldr (fun context ty_acc => 
        Ty.unionize (generalize boundary context ty_result) ty_acc
      ) Ty.bot contexts 

      
    partial def unify_reduce (i : Nat) (ty1) (ty2) (ty_result) :=
      let context : Context := ⟨empty, empty, empty⟩
      let boundary := 0 
      let (_, contexts) := (unify i context ty1 ty2)
      List.foldr (fun context ty_acc => 
        Ty.unionize (generalize boundary context ty_result) ty_acc
        -- Ty.unionize (pack boundary context ty_result) ty_acc
        -- Ty.unionize (ty_result) ty_acc
      ) Ty.bot contexts


    partial def unify_simple (i : Nat) (ty1) (ty2) :=
      let context : Context := ⟨empty, empty, empty⟩
      (unify i context ty1 ty2)

    partial def unify_decide (i : Nat) (ty1) (ty2) :=
      let context : Context := ⟨empty, empty, empty⟩
      let (_, result) := (unify i context ty1 ty2)
      !result.isEmpty

    def combine (icontexts : (Nat × List Context)) (ty : Ty) :=
      let (i, contexts) := icontexts
      (i, contexts.map fun context => (context, ty))

    def to_pair_type : Ty -> Ty 
    | .impli ty1 ty2 => 
      [lesstype| ⟨ty1⟩ * ⟨ty2⟩ ] 
    | [lesstype| ⊤ ] =>  [lesstype| ⊥ ]
    | _ =>  [lesstype| ⊤ ]

    def get_prem : Ty -> Ty 
    | .impli ty1 _ => ty1 
    | [lesstype| ⊤ ] =>  [lesstype| ⊥ ]
    | _ =>  [lesstype| ⊤ ]


  end Ty

  inductive Tm : Type
  | hole : Tm 
  | unit : Tm
  | bvar : Nat -> Tm 
  | fvar : Nat -> Tm 
  | tag : String -> Tm -> Tm
  | record : List (String × Tm) -> Tm
  | func : List (Tm × Tm) -> Tm
  | proj : Tm -> String -> Tm
  | app : Tm -> Tm -> Tm
  | letb : Option Ty -> Tm -> Tm -> Tm
  | fix : Tm -> Tm
  deriving Repr, Inhabited, BEq


  namespace Tm

    declare_syntax_cat lessterm 
    syntax:100 num : lessterm 
    syntax:100 ident : lessterm 
    syntax:30 "_" : lessterm
    syntax:30 "()" : lessterm
    syntax:30 "y[" lessterm:90 "]": lessterm
    syntax:30 "x[" lessterm:90 "]" : lessterm
    syntax:30 "#" lessterm:100 lessterm:30 : lessterm

    syntax:30 "@" lessterm:100 "=" lessterm:30 : lessterm
    syntax:30 "@" lessterm:100 "=" lessterm:30 lessterm: lessterm

    syntax "{" lessterm,+ "}" : lessterm 
    syntax:30 "(" lessterm "," lessterm ")" : lessterm

    syntax:20 "\\" lessterm:30 "=>" lessterm:20 : lessterm
    syntax:20 "\\" lessterm:30 "=>" lessterm:20 lessterm: lessterm

    syntax:30 lessterm:30 "." lessterm:100 : lessterm 
    syntax:30 "(" lessterm:30 lessterm:30 ")" : lessterm 
    syntax:30 "let y[0]" ":" lesstype:30 "=" lessterm:30 "in" lessterm:30 : lessterm 
    syntax:30 "let y[0]" "=" lessterm:30 "in" lessterm:30 : lessterm 
    syntax:30 "fix " lessterm:30 : lessterm 

    syntax "(" lessterm ")" : lessterm

    syntax "⟨" term "⟩" : lessterm 

    syntax "[lessterm| " lessterm "]" : term

    def record_fields : Tm -> List (String × Tm)
    | record fields => fields
    | _ =>  []

    def function_implis : Tm -> List (Tm × Tm)
    | func implis => implis 
    | _ =>  []

    macro_rules
    | `([lessterm| $n:num ]) => `($n)
    | `([lessterm| $a:ident]) => `($(Lean.quote (toString a.getId)))
    | `([lessterm| _ ]) => `(Tm.hole)
    | `([lessterm| () ]) => `(Tm.unit)
    | `([lessterm| y[$n] ]) => `(Tm.bvar [lessterm| $n ])
    | `([lessterm| x[$n] ]) => `(Tm.fvar [lessterm| $n ])
    | `([lessterm| # $a $b ]) => `(Tm.tag [lessterm| $a ] [lessterm| $b ])

    | `([lessterm| @ $a = $b ]) => `( Tm.record [ ([lessterm| $a ], [lessterm| $b ]) ]  )
    | `([lessterm| @ $a = $b $xs ]) => `( Tm.record (([lessterm| $a ], [lessterm| $b ]) :: (Tm.record_fields [lessterm| $xs ])))

    | `([lessterm| ( $a , $b ) ]) => `(Tm.record [("l", [lessterm| $a ]), ("r", [lessterm|$b ])])

    | `([lessterm| \ $b => $d ]) => `(Tm.func [([lessterm| $b ], [lessterm| $d ])])
    | `([lessterm| \ $b => $d $xs ]) => `( Tm.func (([lessterm| $b ], [lessterm| $d ]) :: (Tm.function_implis [lessterm| $xs ])))


    | `([lessterm| $a . $b ]) => `(Tm.proj [lessterm| $a ] [lessterm| $b ])
    | `([lessterm| ($a $b) ]) => `(Tm.app [lessterm| $a ] [lessterm| $b ])
    | `([lessterm| let y[0] : $a = $b in $c ]) => `(Tm.letb (Option.some [lesstype| $a ]) [lessterm| $b ] [lessterm| $c ])
    | `([lessterm| let y[0] = $b in $c ]) => `(Tm.letb Option.none [lessterm| $b ] [lessterm| $c ])
    | `([lessterm| fix $a ]) => `(Tm.fix [lessterm| $a ])

    -- generic
    | `([lessterm| ($a) ]) => `([lessterm| $a ])

    --escape 
    | `([lessterm| ⟨ $e ⟩ ]) => pure e


    #eval [lesstype| ? >> β[0] -> {β[0] with β[0] <: β[1] * β[2] }  ]

    #eval [lesstype| ? >> β[0] -> {β[0] | unit with β[1] <: β[0] } ]


    -- partial def repr (t : Tm) (n : Nat) : Format :=
    -- match t with
    -- | .hole => 
    --   "_"
    -- | .unit =>
    --   "()"
    -- | .bvar id =>
    --   "y[" ++ (Nat.repr id) ++ "]"
    -- | .fvar id => 
    --   "x[" ++ (Nat.repr id) ++ "]"
    -- | .tag l t1 =>
    --   "#" ++ l ++ " " ++ (repr t1 n)
    -- | record [("l", l), ("r", r)] =>
    --   let _ : ToFormat Tm := ⟨fun t1 => repr t1 n ⟩
    --   Format.bracket "(" (Format.joinSep [l, r] ("," ++ Format.line)) ")"
    -- | record fds =>
    --   let _ : ToFormat (String × Tm) := ⟨fun (l, t1) => "@" ++ l ++ " = " ++ repr t1 n⟩
    --   Format.bracket "(" (Format.joinSep fds (" " ++ Format.line)) ")"
    -- | func fs =>
    --   let _ : ToFormat (Tm × Tm) := ⟨fun (pat, tb) =>
    --     "| " ++ (repr pat n) ++ " => " ++ (repr tb (n))
    --   ⟩
    --   Format.bracket "(" (Format.joinSep fs (" " ++ Format.line)) ")"
    -- | .proj t1 l =>
    --   repr t1 n ++ "/" ++ l
    -- | .app t1 t2 =>
    --   Format.bracket "(" (repr t1 n) ") " ++ "(" ++ repr t2 n ++ ")"
    -- | .letb op_ty1 t1 t2 =>
    --   match op_ty1 with
    --   | some ty1 =>
    --     "let y[0] : " ++ (Ty.repr ty1 n) ++ " = " ++  (repr t1 n) ++ " in" ++
    --     Format.line  ++ (repr t2 n) 
    --   | none =>
    --     "let y[0] = " ++  (repr t1 n) ++ " in" ++
    --     Format.line  ++ (repr t2 n) 
    -- | .fix t1 =>
    --   Format.bracket "(" ("fix " ++ (repr t1 n)) ")"

    -- instance : Repr Tm where
    --   reprPrec := repr

    partial def pattern_wellformed (i : Nat) : Tm -> Option Nat
    | .hole => some i 
    | .unit => some i 
    | .bvar id => if i == id then some (i + 1) else none
    | .fvar _ => none
    | .tag _ t1 => pattern_wellformed i t1 
    | .record fds => 
      fds.foldl (fun 
        | .some i, (l, t1) => pattern_wellformed i t1 
        | .none, _ => none
      ) (some i)
    | .func _ => none
    | .proj _ _ => none
    | .app _ _ => none
    | .letb _ _ _ => none
    | .fix _ => none

    partial def abstract (fids : List Nat) (start : Nat) : Tm -> Tm
    | .hole => hole 
    | .unit => .unit 
    | .bvar id => bvar id 
    | .fvar id => 
      match (fids.enumFrom start).find? (fun (_, fid) => fid == id) with
      | .some (bid, _) => .bvar bid
      | .none => .fvar id 
    | .tag l t => .tag l (abstract fids start t) 
    | .record fds =>
      record (List.map (fun (l, t) =>
        (l, abstract fids start t)
      ) fds)
    | .func fs =>
      func (List.map (fun (tp, tb) =>
        let n := match pattern_wellformed 0 tp with
        | .some n => n 
        | .none => 0 
        let tp := abstract fids (start + n) tp 
        let tb := abstract fids (start + n) tb
        (tp, tb)
      ) fs)
    | .proj t l => 
      proj (abstract fids start t) l
    | .app t1 t2 =>
      app 
        (abstract fids start t1) 
        (abstract fids start t2)
    | .letb ty1 t1 t2 =>
      letb ty1 
        (abstract fids start t1)
        (abstract fids (start + 1) t2)
    | .fix t =>
      .fix (abstract fids start t)


    partial def instantiate (start : Nat) (args : List Tm) : Tm -> Tm
    | .hole => hole 
    | .bvar id => 
        if h : start ≤ id ∧ (id - start) < args.length then
          let i : Fin args.length := {
            val := (id - start),
            isLt := (match h with | And.intro _ h' => h') 
          } 
          args.get i 
        else
          .bvar id
    | .fvar id => .fvar id 
    | .unit => .unit 
    | .tag l t => tag l (instantiate start args t)
    | .record fds =>
      record (List.map (fun (l, t) =>
        (l, instantiate start args t)
      ) fds)
    | .func fs =>
      func (List.map (fun (tp, tb) =>
        let n := match pattern_wellformed 0 tp with
        | .some n => n 
        | .none => 0 
        let tp := instantiate (start + n) args tp 
        let tb := instantiate (start + n) args tb
        (tp, tb)
      ) fs)
    | .proj t l => 
      proj (instantiate start args t) l
    | .app t1 t2 =>
      app 
        (instantiate start args t1) 
        (instantiate start args t2)
    | .letb ty1 t1 t2 =>
      letb ty1 
        (instantiate start args t1)
        (instantiate (start + 1) args t2)
    | .fix t =>
      .fix (instantiate start args t)



    -- structure Guide where
    --   env_tm : PHashMap Nat Ty
    --   ty_expected : Ty
    -- deriving Repr

    -- structure Contract where
    --   i : Nat
    --   env_ty : PHashMap Ty Ty 
    --   guides : List (Nat × Guide) -- [..., (hole variable, guide), ...]
    --   t : Tm
    --   ty : Ty 
    -- deriving Repr



    partial def infer (i : Nat) (context : Ty.Context) (env_tm : PHashMap Nat Ty) (t : Tm) : 
    (Nat × List (Ty.Context × Ty)) :=
    match t with
    | hole => 
      (i, [(context, Ty.top)])
    | .unit => 
      (i, [(context, Ty.unit)])
    | bvar _ => (i, []) 
    | fvar id =>
      match (env_tm.find? id) with
      | some ty => 
        (i, [(context, ty)])
      | none => (i, [])

    | .tag l t1 =>   
      bind_nl (infer i context env_tm t1) (fun i (context, ty1) =>
        (i, [(context, Ty.tag l ty1)])
      )

    | .record fds =>

      let f_step := (fun (l, t1) acc =>
        bind_nl acc (fun i (context, ty_acc) =>
        bind_nl (infer i context env_tm t1) (fun i (context, ty1) =>
          (i, [(context, Ty.inter (Ty.field l ty1) ty_acc)])
        ))
      )

      List.foldr f_step (i, [(context, Ty.top)]) fds 

    | .func fs =>

      let f_step := (fun (p, b) acc =>
        bind_nl acc (fun i (context, ty_acc) =>
        match pattern_wellformed 0 p with
        | none => (i, [])
        | some n =>
          let env_pat : PHashMap Nat Ty := (List.range n).foldl (init := {}) (fun env_pat j => 
            let tm_key := (i + (2 * j))
            let ty_x := Ty.fvar (i + (2 * j) + 1) 
            (env_pat.insert tm_key ty_x)
          )
          let i := i + (2 * n)

          let list_tm_x := env_pat.toList.map (fun (k, _) => (fvar k))

          let p := instantiate 0 list_tm_x p 
          let b := instantiate 0 list_tm_x b  
          bind_nl (infer i context (env_tm ; env_pat) p) (fun i (context, ty_p) =>
          bind_nl (infer i context (env_tm ; env_pat) b) (fun i (context, ty_b) =>
              (i, [(context, Ty.simplify (Ty.inter (Ty.impli ty_p ty_b) ty_acc))])
          )))
        )

      List.foldr f_step (i, [(context, Ty.top)]) fs

    | .proj t1 l =>
      bind_nl (infer i context env_tm t1) (fun i (context, ty1) =>
      let (i, ty) := (i + 1, Ty.fvar i)
      bind_nl (Ty.unify i context ty1 (Ty.field l ty)) (fun i context =>
        (i, [(context, ty)])
      ))

    | .app t_f t_arg =>
      let (i, ty_res) := (i + 1, Ty.fvar i)
      let (i, context_tys_arg) := (infer i context env_tm t_arg)

------------------------------
      --------------
      -- this requires substitution of everything 
      --------------
      let op := context_tys_arg.foldl (fun op_i_context_tys (context, ty_arg) =>
        op_i_context_tys.bind (fun (i, context_tys) =>
          let (i, context_tys') := (
            bind_nl (infer i context env_tm t_f) (fun i (context, ty_f) =>
            bind_nl (Ty.unify i context 
              (Ty.subst context.env_simple ty_f) 
              (Ty.subst context.env_simple (Ty.impli ty_arg ty_res))
            ) (fun i context => 
              (i, [(context, ty_res)])
            ))
          )
          if context_tys'.isEmpty then
            none
          else
            some (i, context_tys ++ context_tys')
        )
      ) (some (i, []))

      match op with
      | some (i, context_tys) => (i, context_tys)
      | none => (i, [])

------------------------------

      -- let ty_strong := context_tys_arg.foldl (fun ty_strong (context_arg, ty_arg) =>
      --   Ty.unionize (Ty.subst context_arg.env_simple ty_arg) ty_strong
      -- ) Ty.bot

      -- let (i, new_context_tys_arg) :=  (
      --   bind_nl (i, context_tys_arg) (fun i (context, ty_arg) =>
      --   bind_nl (infer i context env_tm t_f) (fun i (context, ty_f) =>
      --   bind_nl (Ty.unify i context ty_f (Ty.impli ty_arg ty_res)) (fun i context => 
      --     (i, [(context, ty_arg)])
      --   )))
      -- )

      -- let ty_weak := new_context_tys_arg.foldl (fun ty_weak (context_arg, ty_arg) =>
      --   Ty.unionize (Ty.subst context_arg.env_simple ty_arg) ty_weak
      -- ) Ty.bot

      -- -- TODO: also neeed to ensure weaker side does not have additional/stronger relational constraints
      -- let (i, contexts_oracle) := Ty.unify i context ty_strong ty_weak

      -- if contexts_oracle.isEmpty then
      --   (i, [])
      -- else
      --   (i, new_context_tys_arg.map (fun (context, _) => (context, ty_res)))
      ----------------

    | .letb op_ty_expected t_arg t => 

      let (i, ty_expected) := match op_ty_expected with
      | some ty_expected => (i, ty_expected)
      | none => (i + 1, Ty.fvar i)

      if t_arg == Tm.hole then
        let (i, id_expected) := (i + 1, i)
        let context := {context with env_simple := context.env_simple.insert id_expected ty_expected}
        let (i, x, env_tmx) := (i + 1, fvar i, PHashMap.from_list [(i, Ty.fvar id_expected)]) 
        let t := instantiate 0 [x] t 
        (infer i context (env_tm ; env_tmx) t) 
      else
        let free_var_boundary := i

        let (i, context_tys_arg) := (infer i context env_tm t_arg)


        -----------------------------------------------
        let is_safe := context_tys_arg.all (fun (context, ty_arg) =>
          let ty_arg := (Ty.subst context.env_simple ty_arg)
          let ty_expected := (Ty.subst context.env_simple ty_expected)
          let (i, contexts') := ( 
            (Ty.unify i context ty_arg ty_expected)
          )
          !contexts'.isEmpty
        )

        if is_safe then
          bind_nl (i, context_tys_arg) (fun i (context, ty_arg) =>
          bind_nl (Ty.unify i context ty_arg ty_expected) (fun i context =>
            let ty_schema := Ty.generalize free_var_boundary context ty_arg
            let (i, x, env_tmx) := (i + 1, fvar i, PHashMap.from_list [(i, ty_schema)]) 
            let t := instantiate 0 [x] t 
            (infer i context (env_tm ; env_tmx) t) 
          ))
        else
          (i, [])
        ------------------------------------------------------

        -- let ty_strong := context_tys_arg.foldl (fun ty_strong (context_arg, ty_arg) =>
        --   Ty.unionize (Ty.subst context_arg.env_simple ty_arg) ty_strong
        -- ) Ty.bot

        -- let (i, contexts_oracle) := Ty.unify i context ty_strong ty_expected
        -- if contexts_oracle.isEmpty then
        --   (i, [])
        -- else
        --   bind_nl (infer i context env_tm t_arg) (fun i (context, ty_arg) =>
        --   bind_nl (Ty.unify i context ty_arg ty_expected) (fun i context =>
        --     let ty_schema := Ty.generalize free_var_boundary context ty_arg
        --     let (i, x, env_tmx) := (i + 1, fvar i, PHashMap.from_list [(i, ty_schema)]) 
        --     let t := instantiate 0 [x] t 
        --     (infer i context (env_tm ; env_tmx) t) 
        --   ))

      -------------------------------
      -- let (i, ty_ret) := (i + 1, Ty.fvar i)
      -- let (i, context_tys_arg) := (infer i context env_tm t_arg)
      -- let ty_strong := context_tys_arg.foldl (fun ty_strong (context_arg, ty_arg) =>
      --   Ty.unionize (Ty.subst context_arg.env_simple ty_arg) ty_strong
      -- ) Ty.bot

      -- let (i, new_context_tys_arg) :=  (
      --   bind_nl (i, context_tys_arg) (fun i (context, ty_arg) =>
      --   bind_nl (infer i context env_tm t_f) (fun i (context, ty_f) =>
      --   bind_nl (Ty.unify i context ty_f (Ty.impli ty_arg ty_ret)) (fun i context => 
      --     (i, [(context, ty_arg)])
      --   )))
      -- )

      -- let ty_weak := new_context_tys_arg.foldl (fun ty_weak (context_arg, ty_arg) =>
      --   Ty.unionize (Ty.subst context_arg.env_simple ty_arg) ty_weak
      -- ) Ty.bot

      -- let (i, contexts_oracle) := Ty.unify i context ty_strong ty_weak

      -- -- let m : PHashMap Nat Ty := (empty.insert 333 ty_weak).insert 111 ty_strong
      -- -- let cd : Ty.Context := ⟨m, empty, empty⟩ 

      -- if contexts_oracle.isEmpty then
      --   (i, [])
      -- else
      --   (i, new_context_tys_arg.map (fun (context, _) => (context, ty_ret)))


    | .fix t1 =>
      let boundary := i
      let (i, ty_IH) := (i + 1, Ty.fvar i) 
      let (i, ty_IC) := (i + 1, Ty.fvar i) 
      bind_nl (infer i context env_tm t1) (fun i (context, ty1) =>
      bind_nl (Ty.unify i context ty1 (Ty.impli ty_IH ty_IC)) (fun i context =>
        let ty_IH := (Ty.subst context.env_simple ty_IH)
        let ty_IC := (Ty.subst context.env_simple ty_IC)
        ------------------------------------------------------
        -- TODO: factor out this rewriting with higher order function 
        -------------------------------------------------------
        let ty_param_content := List.foldr (fun ty_impli ty_acc =>
          let fvs := (toList (Ty.free_vars ty_impli)).filter (fun fid => fid >= boundary)
          let fvs_prem :=  (Ty.free_vars ty_IH)
          let ty_choice := (
            if List.any fvs (fun id => fvs_prem.find? id != none) then
              let fixed_point := fvs.length
              [lesstype|
                {⟨fvs.length⟩ // ⟨Ty.abstract fvs 0 (Ty.get_prem ty_impli)⟩ with 
                  ⟨Ty.abstract fvs 0 (Ty.get_prem ty_IH)⟩ <: β[⟨fixed_point⟩] 
                } 
              ]
            else if fvs.length > 0 then
              [lesstype| {⟨fvs.length⟩ // ⟨Ty.abstract fvs 0 (Ty.get_prem ty_impli)⟩} ]
            else
              (Ty.get_prem ty_impli)
          )

          (Ty.union ty_choice ty_acc) 
        ) [lesstype| ⊥ ] (Ty.split_intersections ty_IC)

        let ty_param := [lesstype| induct ⟨ty_param_content⟩ ]
        ------------------------------------------------------
        -- let (i, ty_param) := (i + 1, Ty.fvar i)
        ------------------------------------------------------

        let ty_content := List.foldr (fun ty_impli ty_acc =>
          let fvs := (toList (Ty.free_vars ty_impli)).filter (fun fid => fid >= boundary)
          let fvs_prem := (Ty.free_vars ty_IH)
          let ty_choice := (
            if List.any fvs (fun id => fvs_prem.find? id != none) then
              let fixed_point := fvs.length
              [lesstype|
                {⟨fvs.length⟩ // ⟨Ty.abstract fvs 0 (Ty.to_pair_type ty_impli)⟩ with 
                  ⟨Ty.abstract fvs 0 (Ty.to_pair_type ty_IH)⟩ <: β[⟨fixed_point⟩] 
                } 
              ]
            else if fvs.length > 0 then
              [lesstype| {⟨fvs.length⟩ // ⟨Ty.abstract fvs 0 (Ty.to_pair_type ty_impli)⟩} ]
            else
              (Ty.to_pair_type ty_impli)
          )

          (Ty.union ty_choice ty_acc) 
        ) [lesstype| ⊥ ] (Ty.split_intersections ty_IC)

        -- NOTE: constraint that ty' <= ty_IH is built into inductive type
        let relational_type := [lesstype| induct ⟨ty_content⟩ ]
        let ty' := [lesstype| ⟨ty_param⟩ >> β[0] -> {1 // β[0] with β[1] * β[0] <: ⟨relational_type⟩} ] 
        (i, [(context, ty')])
      ))


    partial def infer_simple i (t : Tm) :=
      let context : Ty.Context := ⟨empty, empty, empty⟩
      (infer (i + 1) context {} t)
      
    partial def infer_union_context (i : Nat) (context : Ty.Context) (t : Tm) : Ty :=
      let boundary := 0
      let (_, contexts) := (infer i context {} t)
      List.foldr (fun (context, ty') ty_acc => 
        (Ty.union ty' ty_acc)
      ) Ty.bot contexts

    partial def infer_union (i : Nat) (t : Tm) : Ty := 
      let context : Ty.Context := ⟨empty, empty, empty⟩
      infer_union_context (i + 1)  context t

    partial def infer_reduce_context (i : Nat) (context : Ty.Context) (t : Tm) : Ty :=
      let boundary := 0
      let (_, context_tys) := (infer i context {} t) 
      List.foldr (fun (context, ty') ty_acc => 
        Ty.unionize (Ty.generalize boundary context ty') ty_acc
        -- Ty.unionize (Ty.pack boundary context ty') ty_acc
        -- Ty.unionize ty' ty_acc
      ) Ty.bot context_tys


    partial def infer_reduce (i : Nat) (t : Tm) : Ty := 
      let context : Ty.Context := ⟨empty, empty, empty⟩
      infer_reduce_context (i + 1)  context t

    -- structure Work where
    --   cost : Nat
    --   i : Nat
    --   guides : PHashMap Nat Guide
    --   patches : PHashMap Nat Tm 
    --   t : Tm
    -- deriving Repr



    -- def Work.le (x y: Work): Bool := x.cost <= y.cost

    -- def Work.Queue := BinomialHeap Work Work.le

    -- partial def cost : Tm -> Nat
    -- | hole => 1 
    -- | .unit => 1 
    -- | bvar id => 1 
    -- | fvar id => 1
    -- | tag l t => 1 + (cost t)
    -- | record entries => 
    --   List.foldl (fun cost' (l, t) => cost' + (cost t)) 1 entries
    -- | func implis =>
    --   List.foldl (fun cost' (p, t_b) => cost' + (cost t_b)) 1 implis
    -- | proj t l => 1 + (cost t)
    -- | app t1 t2 => 1 + (cost t1) + (cost t2)
    -- | letb ty t1 t2 => 1 + (cost t1) + (cost t2)
    -- | .fix t => 1 + (cost t)

    -- partial def subst (m : PHashMap Nat Tm) : Tm -> Tm 
    -- | hole => hole 
    -- | .unit => .unit 
    -- | bvar id => bvar id 
    -- | fvar id => (match m.find? id with
    --   | some t => subst m t 
    --   | none => .fvar id
    -- )
    -- | tag l t => tag l (subst m t)
    -- | record entries => 
    --   let entries' := List.map (fun (l, t) => (l, subst m t)) entries 
    --   record entries'
    -- | func implis =>
    --   let implis' := List.map (fun (p, t_b) => 
    --     (p, subst m t_b)
    --   ) implis 
    --   func implis'
    -- | proj t l => proj (subst m t) l
    -- | app t1 t2 => app (subst m t1) (subst m t2)
    -- | letb ty t1 t2 => letb ty (subst m t1) (subst m t2)
    -- | .fix t => .fix (subst m t)

    -- (tag labels, field labels)
    partial def extract_labels : Ty -> (List String × List String)
    | .bvar id => ([], []) 
    | .fvar id => ([], [])
    | .unit => ([], []) 
    | .top => ([], [])
    | .bot => ([], [])
    | .tag l ty => 
      let (ls_t, ls_f) := extract_labels ty
      (l :: ls_t, ls_f) 
    | .field l ty => 
      let (ls_t, ls_f) := extract_labels ty
      (ls_t, l :: ls_f) 
    | .union ty1 ty2 => 
      let (ls_t1, ls_f1) := extract_labels ty1
      let (ls_t2, ls_f2) := extract_labels ty2
      (ls_t1 ++ ls_t2, ls_f1 ++ ls_f2) 
    | .inter ty1 ty2 => 
      let (ls_t1, ls_f1) := extract_labels ty1
      let (ls_t2, ls_f2) := extract_labels ty2
      (ls_t1 ++ ls_t2, ls_f1 ++ ls_f2) 
    | .impli ty1 ty2 => 
      let (ls_t1, ls_f1) := extract_labels ty1
      let (ls_t2, ls_f2) := extract_labels ty2
      (ls_t1 ++ ls_t2, ls_f1 ++ ls_f2) 
    | .exis n ty_c1 ty_c2 ty =>
      let (ls_tc1, ls_fc1) := extract_labels ty_c1
      let (ls_tc2, ls_fc2) := extract_labels ty_c2
      let (ls_t, ls_f) := extract_labels ty
      (ls_tc1 ++ ls_tc2 ++ ls_t, ls_fc1 ++ ls_fc2 ++ ls_f) 
    | .univ op_ty_c ty =>
      let (ls_tc, ls_fc) := (match op_ty_c with
      | none => ([], [])
      | some ty_c => extract_labels ty_c
      )
      let (ls_t, ls_f) := extract_labels ty
      (ls_tc ++ ls_t, ls_fc ++ ls_f) 
    | .induc ty =>
      extract_labels ty


    partial def enumerate_fields : List String -> List (List (String × Tm))
    | [] => []
    | l :: ls =>
      (enumerate_fields ls).map (fun fields => (l, hole) :: fields)

    partial def enumerate_implis : List String -> List (List (Tm × Tm))
    | [] => []
    | l :: ls =>
      (enumerate_implis ls).map (fun implis => ([lessterm| #⟨l⟩ y[0] ], [lessterm| _ ]) :: implis)

    partial def join_functions (t1 : Tm) (t2 : Tm) : List Tm := match t1, t2 with
    | func implis1, func implis2 => [func (implis1 ++ implis2)]
    | _, _ => []

    partial def enumerate (i : Nat) (env_tm : PHashMap Nat Ty) (ty : Ty) : List Tm :=
      let (ls_t, ls_f) := (extract_labels ty)
      let tags := ls_t.map (fun l => tag l hole)

      let fields := enumerate_fields ls_f
      let records := fields.map (fun fds => record fds)

      let implis := enumerate_implis ls_t
      let functions := (
        [lessterm| \ y[0] => _ ] :: 
        (implis.map (fun implis => func implis))
      )

      [lessterm| () ] ::
      tags ++
      records ++
      functions ++
      [ [lessterm| let y[0] = _ in _ ] ] ++
      [ [lessterm| fix _ ] ] ++
      List.bind env_tm.toList (fun (x, ty) =>
        let (_, ls) := extract_labels ty
        let var := (fvar x)
        let application := [lessterm| let y[0] = (⟨fvar x⟩ _) in _ ] 
        let projections := ls.map (fun l =>
          [lessterm| let y[0] = (⟨fvar x⟩.⟨l⟩) in _ ] 
        )
        var :: application :: projections
      )

  end Tm



--------------------------------------------------
  open Ty Tm

  --- unification --
  def nat_ := [lesstype|
    induct 
      ?zero unit |
      ?succ β[0]
  ]

  
    
  #eval unify_simple 30
  [lesstype| (?zero unit) ] 
  [lesstype| ?zero unit | ?succ unit ]


  #eval unify_reduce 30
  [lesstype| (?succ ?succ ?succ α[0]) ] 
  [lesstype| ?zero unit | ?succ ⟨nat_⟩ ] 
  [lesstype| α[0] ]

  #eval unify_simple 30
  [lesstype| (?succ ?succ ?succ ?zero unit) ] 
  [lesstype| ?zero unit | ?succ ⟨nat_⟩ ]

  #eval unify_reduce 30
  [lesstype| (?succ α[0]) ] 
  nat_
  [lesstype| α[0] ]

  def nat_list := [lesstype| 
    induct 
      (?zero unit * ?nil unit) | 
      {?succ β[0] * ?cons β[1] with (β[0] * β[1]) <: β[2]}
  ]

  #eval unify_reduce 30
  [lesstype| (?succ ?zero unit) * ?cons α[0] ] 
  nat_list
  [lesstype| α[0] ]

  #eval unify_reduce 30
  [lesstype| ?succ ?zero unit * α[0] ]
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| α[0] ]

  -- subtyping via local constraints
  -- expected: ?nil unit
  #eval unify_reduce 30
  [lesstype| {β[0] with ?succ ?zero unit * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ?cons α[0] ] 
  [lesstype| α[0] ]


  -- expected: ?cons ?nil unit
  #eval unify_reduce 30
  [lesstype| ⊤ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?succ ?zero unit -> ?cons α[0] ] 
  [lesstype| α[0] ]


  -- requires weakening to be turned off
  -- expected: ⊥
  #eval unify_reduce 30
  [lesstype| ⊤ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ?foo ?succ ?zero unit -> α[0] ] 
  [lesstype| ?boo α[0] ]

  -----------------------------------------------

  def even_list := [lesstype| 
    induct 
      (?zero unit * ?nil unit) | 
      {?succ ?succ β[0] * ?cons ?cons β[1] with (β[0] * β[1]) <: β[2]}
  ]


  -- affected by direction of variable assigment
  -- expected: true
  #eval unify_decide 0 even_list nat_list 

  -- expected: false 
  #eval unify_decide 0 nat_list even_list

  def even := [lesstype| 
    induct ?zero unit | ?succ ?succ β[0]
  ]

  ---------------------------------
  #eval unify_decide 0 even nat_ 
  #eval unify_decide 0 nat_ even
  ------------------------

  -- expected: true
  #eval unify_decide 0
  [lesstype| ? >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ? >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]


  -- expected: ?cons ?nil unit
  #eval unify_reduce 10
  [lesstype| {2 // β[0] -> β[1] with β[0] * β[1] <: ⟨nat_list⟩} >> β[0]]
  [lesstype| ?succ ?zero unit -> α[2]]
  [lesstype| α[2]]


  -- expected: ?cons ?nil unit
  #eval unify_reduce 10
  [lesstype| ?succ ?zero unit -> α[2]]
  [lesstype| {2 // β[0] -> β[1] with β[0] * β[1] <: ⟨nat_list⟩}]
  [lesstype| α[2]]

  ----------------

  -- expected: ⊥
  #eval unify_reduce 10
  [lesstype| {2 // β[0] -> β[1] with β[0] * β[1] <: ⟨nat_list⟩}]
  [lesstype| ?succ ?zero unit -> α[2]]
  [lesstype| α[2]]

  -- expected: ?cons ?nil unit 
  #eval unify_reduce 10
  [lesstype| ?succ ?zero unit -> α[2]]
  [lesstype| {2 // β[0] -> β[1] with β[0] * β[1] <: ⟨nat_list⟩}]
  [lesstype| α[2]]


  -- potential CYCLE!!!!
  -- substitution could cause the same unification problem to repeat infinitely
  -- expected: true
  #eval unify_decide 10 
  [lesstype| α[0] >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| α[0] >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]

  -- expected: true
  #eval unify_decide 10 
  [lesstype| α[1] -> {β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| α[2] -> {β[0] with α[2] * β[0] <: ⟨nat_list⟩} ]

  #eval unify_simple 10 
  [lesstype| α[1] -> α[3] ]
  [lesstype| α[2] -> α[4] ]

  -- expected: true 
  #eval unify_decide 10 
  [lesstype| {β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| {β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]

  -- expected: false 
  #eval unify_decide 10 
  [lesstype| {β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| {β[0] with α[2] * β[0] <: ⟨nat_list⟩} ]

  -- expected: true
  #eval unify_decide 10 
  [lesstype| {α[1] * β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| {α[2] * β[0] with α[2] * β[0] <: ⟨nat_list⟩} ]

  -- expected: true
  #eval unify_decide 10 
  [lesstype| {β[0] * β[1] with β[0] * β[1] <: ⟨nat_list⟩} ]
  [lesstype| {β[0] * β[1] with β[0] * β[1] <: ⟨nat_list⟩} ]

  -- expected: true
  #eval unify_decide 10 
  [lesstype| {β[0] with β[0] <: ⟨nat_list⟩} ]
  [lesstype| {β[0] with β[0] <: ⟨nat_list⟩} ]

  -- expected: true
  #eval unify_decide 10 
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| ⟨nat_list⟩ ]
---------------

  def plus := [lesstype| 
    induct 
      {x : ?zero unit & y : β[0] & z : β[0]} | 
      {x : ?succ β[0] & y : β[1] & z : ?succ β[2] with (x : β[0] & y : β[1] & z : β[2]) <: β[3] }
  ]

  #eval plus

  #eval unify_reduce 30 [lesstype|
    (
      x : (α[10]) &
      y : (?succ ?zero unit) & 
      z : (?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| α[10] ]

  #eval unify_reduce 30 
    [lesstype|
      (
        x : (?zero unit) &
        y : (?zero unit) & 
        z : (?zero unit)
      )
    ] 
    plus
    [lesstype| unit ]

  #eval unify_reduce 30 
    [lesstype|
      (
        x : (?succ ?zero unit) &
        y : (?succ ?succ ?zero unit) & 
        z : (?succ ?succ ?succ ?zero unit)
      )
    ] 
    plus
    [lesstype| unit ]


  #eval unify_reduce 30 [lesstype|
    (
      x : (?succ ?zero unit) & 
      y : (α[10]) &
      z : (?succ ?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| α[10] ]


  #eval unify_reduce 30 [lesstype|
    (
      x : ?succ α[1] &
      y : α[2] &
      z : (?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| α[1] * α[2] ]



  #eval unify_reduce 30 
  [lesstype| (α[0] * ?zero unit) | (?zero unit * α[0]) ] 
  [lesstype| (⟨nat_⟩ * ?zero unit) ] 
  [lesstype| α[0] ]



  #eval unify_reduce 30 [lesstype|
    (
      x : ?succ α[0] &
      y : α[2] &
      z : (?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| ?succ α[0] * α[2] ]

  #eval unify_reduce 30 [lesstype|
    (
      x : α[0] &
      y : α[2] &
      z : (?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| α[0] * α[2] ]

  #eval unify_reduce 1 [lesstype|
    (
      x : (?succ ?succ ?zero unit) & 
      y : (?succ ?zero unit) &
      z : (α[0])
    )
  ] plus
  [lesstype| α[0] ]
  -- == [lesstype| ?succ ?succ ?succ ?zero unit ]

  #eval unify_reduce 30 [lesstype|
    (
      x : (?succ ?zero unit) & 
      y : (α[10]) &
      z : (?succ ?succ ?zero unit)
    )
  ] plus
  [lesstype| α[10] ]


  #eval unify_reduce 10 [lesstype|
  (
    x : α[5] &
    y : ?succ ?zero unit &
    z : ?succ ?succ ?zero unit
  )
  ] plus
  [lesstype| α[5] ]

  #eval unify_simple 10 
    [lesstype| ⊥ ] 
    plus 

  #eval unify_simple 10 
    plus 
    [lesstype| ⊥ ] 

  ------ type inference --------
  #eval infer_reduce 0 [lessterm|
    #succ #zero ()
  ]


  -- path discrimination

  -- expected: ?cons ?nil unit
  #eval infer_reduce 0 [lessterm|
    let y[0] : (?zero unit -> ?nil unit) & (?succ ?zero unit -> ?cons ?nil unit) = _ in 
    (y[0] (#succ #zero ()))
  ]

  #eval infer_reduce 10 
  [lessterm|
  let y[0] : (
    (? >> (?hello β[0] -> ?world unit)) & 
    (? >> ?one β[0] -> ?two unit)
  ) = _ in 
  (y[0] #one ())
  ]

  #eval infer_reduce 10 
  [lessterm|
  let y[0] : (
    (? >> 
      (?hello β[0] -> ?world unit) & 
      (?one β[0] -> ?two unit)
    )
  ) = _ in 
  (y[0] #one ())
  ]

  -- expected: ?cons ?nil unit
  #eval infer_reduce 0 [lessterm|
    let y[0] : ⟨nat_⟩ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} = _ in 
    (y[0] (#succ #zero ()))
  ]

  -- NOTE: weakening causes a fairly impprecise type  
  -- expected:  {2 // β[1] with β[0] * β[1] <: ⟨nat_list⟩}  
  #eval infer_reduce 10 [lessterm|
    let y[0] : ? >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} = _ in 
    (y[0] (#succ #zero ()))
  ]

---------------------------------------------------------------
  ----------------------------------
  -- broken: nat should not be subbed into relational key
  -- double
  #eval infer_reduce 10 [lessterm|
    let y[0] : ⟨nat_⟩ = _ in
    let y[0] = fix(\ y[0] => (
      \ #zero () => #zero ()
      \ #succ y[0] => #succ #succ ((y[1] y[0]))
    )) in
    (y[0] y[1])
  ]
  ----------------------------------

  --------- relational typing -----------

  #eval infer_reduce 0 [lessterm|
    fix(\ y[0] => (
    \ #zero () => #nil ()
    \ #succ y[0] => #cons (y[1] y[0])
    ))
  ]

  #eval infer_reduce 0 [lessterm|
    let y[0] = fix(\ y[0] => 
      \ #zero () => #nil ()
      \ #succ y[0] => #cons (y[1] y[0])
    ) in 
    y[0]
  ]

  --------- relational selection -----------

  #eval unify_reduce 10 
  [lesstype| (?succ ?zero unit * α[0]) ]
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| α[0] ]

  #eval unify_reduce 10 
  [lesstype| (?succ ?succ ?zero unit * α[0]) ]
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| α[0] ]


  -- expected: ?cons (?thing unit * ?cons (?thing unit * ?nil unit))
  #eval unify_reduce 10 
  [lesstype|
      {1 // β[0] with (?succ ?succ ?zero unit * β[0]) <: (induct ((?zero unit * ?nil unit) |
          {2 // (?succ β[1] * ?cons (?thing unit * β[0])) with (β[1] * β[0]) <: β[2]}))}
  ]
  [lesstype| α[7] ]
  [lesstype| α[7] ]

  -- expected: ?cons (?thing unit * ?cons (?thing unit * ?nil unit))
  #eval unify_reduce 10 
  [lesstype|
    (α[0] >> (β[0] ->
      {1 // β[0] with (β[1] * β[0]) <: (induct ((?zero unit * ?nil unit) |
          {2 // (?succ β[1] * ?cons (?thing unit * β[0])) with (β[1] * β[0]) <: β[2]}))}))
  ]
  [lesstype| ?succ ?succ ?zero unit -> α[7] ]
  [lesstype| α[7] ]

  -- expected: ?cons (?thing unit * ?cons (?thing unit * ?nil unit))
  #eval unify_reduce 20 
  [lesstype|
    (⟨nat_⟩ >> (β[0] ->
      {1 // β[0] with (β[1] * β[0]) <: (induct ((?zero unit * ?nil unit) |
          {2 // (?succ β[1] * ?cons (?thing unit * β[0])) with (β[1] * β[0]) <: β[2]}))}))
  ]
  [lesstype| ?succ ?succ ?zero unit -> α[7] ]
  [lesstype| α[7] ]

  -- broken
  -- breaks when using parameter type
  -- expected: ?cons (?thing unit * ?cons (?thing unit * ?nil unit))
  #eval infer_reduce 10 [lessterm|
    let y[0] = (\ y[0] => fix(\ y[0] => 
      \ #zero () => #nil ()
      \ #succ y[0] => #cons (y[2], (y[1] y[0]))
    )) in 
    ((y[0] #thing()) #succ #succ #zero ())
    -- (y[0] #thing())
    -- y[0]
  ]

  -- expected: ?cons ?nil unit
  #eval infer_reduce 10 [lessterm|
    (fix(\ y[0] => ( 
      \ #zero () => #nil ()
      \ #succ y[0] => #cons (y[1] y[0])
    )) 
    (#succ #zero ())
    )
  ]

  -- expected: ?cons ?nil unit
  #eval infer_reduce 10 [lessterm|
    let y[0] = fix(\ y[0] => ( 
      \ #zero () => #nil ()
      \ #succ y[0] => #cons (y[1] y[0])
    )) in 
    (y[0] (#succ #zero ()))
  ]


  #eval unify_reduce 10 
  [lesstype|
  (α[3] >> (β[0] -> {1 // β[0] with (β[1] * β[0]) <: 
    (induct (
        (?zero unit * ?nil unit) | 
        {2 // (?succ β[1] * ?cons β[0]) with (β[1] * β[0]) <: β[2]}))
  }))
  ]
  [lesstype| ?succ ?zero unit -> α[0] ]
  [lesstype| α[0] ]

  -------------------------------

  #eval infer_reduce 0 [lessterm| 
      (fix (\ y[0] => (
        \ (#zero(), y[0]) => #true()  
        \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
        \ (#succ y[0], #zero()) => #false() 
      )))
  ] 

  -- expected: ⊥  
  #eval infer_reduce 0 [lessterm| 
    let y[0] : ?succ ?zero unit = 
    (
      (\ (y[0], y[1]) => (
        (
          (\ #true() => y[1] \ #false() => y[0]))
          ((
            \ (#zero(), y[0]) => #true()  
            \ (#succ y[0], #succ y[1]) => #false()
            \ (#succ y[0], #zero()) => #false() 
          )
          (y[0], y[1])) 
        )
      )
      ((#succ #succ #zero()), #succ #zero())
    ) 
    in
    y[0] 
  ] 


  ---------- generics ----------------

  #eval infer_reduce 10 [lessterm|
    ((\ #cons (y[0], y[1]) => y[0]) (#cons (#ooga (), #booga ())))
  ]

  #eval infer_reduce 10 [lessterm|
    let y[0] = (\ #cons (y[0], y[1]) => y[0]) in
    (y[0] (#cons (#ooga (), #booga ())))  
  ]

  #eval infer_reduce 10 [lessterm|
    let y[0] = (\ #cons (y[0], y[1]) => y[0]) in 
    y[0]  
  ]

  #eval infer_reduce 10 [lessterm|
    let y[0] : ? >> ? >> ?cons (β[0] * β[1]) -> β[0] = _ in
    (y[0] (#cons (#ooga (), #booga ())))  
  ]

  ---------- expanding return type ----------------
  -- weakening mechanism may be superfluous; subsumed by behavior of inductive and existential types.
  ----------------------------------------------
  -- object-oriented example without type annotation ----------------
  -- a typical object-oriented pattern:
  -- where the method constructs new data and calls constructor with new data 

  -- expected:
  /-
  constructor : (Data <: ?) >> Data -> {Object with Data * Object <: DO}
        where μ DO . {D, α, O // D * (data : D & update : α -> O) with (?cons (α * D) * O) <: DO
  -/
  -- broken: bound variable β[1] not introduced
  #eval infer_reduce 0 [lessterm|
    -- fix \ self \ data => 
    fix (\ y[0] => \ y[0] => 
      (
        @data = y[0]
        @update = (\ y[0] => (y[2] #cons (y[0], y[1])))
      )
    ) 
  ]

-- NOTE: 
-- The weakening flag may not actually be needed, as distinct types can be handled via existential inside of inductive type,
-- which results in fresh variables at the time of unification.
  /-
(? >> 

(β[1] >> -- this is correct; short hand for (β[0] <: β[1] >>) 

(β[0] ->
   {1 // β[0] with (β[1] * β[0]) <: (induct 
      {3 // (β[2] * (
        (data : β[2]) & (update : (β[1] -> β[0]))
        )) with (?cons (β[1] * β[2]) * β[0]) <: β[3]}
   )}
 )
 )
 )
  -/


  #eval infer_reduce 0 [lessterm|
    -- fix \ self \ data => 
    let y[0] = fix (\ y[0] => \ y[0] => 
      (@update = (\ y[0] => (y[2] #cons (y[0], y[1]))))
    ) in 
    -- y[0]
    -- let y[0] = (y[1] #nil())
    (y[0] #nil())
    -- (((y[0] #nil()).update #hello()).update #world())
  ]
  ------------------

  ----------------------------------------
  -- weakening mechanism is deprecated
  ----------------------------------------
  -- #eval infer_reduce 0 [lessterm|
  --   let y[0] : ? >> β[0] -> (β[0] -> (β[0] * β[0])) = _ in 
  --   ((y[0] #hello ()) #world ())
  -- ]

  -- #eval infer_reduce 0 [lessterm|
  --   let y[0] = (\ y[0] => \ y[0] => (y[1], y[0])) in 
  --   ((y[0] #hello ()) #world ())
  -- ]

  -- #eval infer_reduce 0 [lessterm|
  --   (((\ y[0] => \ y[0] => (y[1], y[0])) #hello ()) #world ())
  -- ]

  -- -- NOTE: this requires subbing in unions to maintain weakening after let-poly generalization
  -- #eval infer_reduce 0 [lessterm|
  --   let y[0] : ? >> β[0] -> (β[0] -> (β[0] * β[0])) = _ in 
  --   let y[0] = (y[0] #hello ()) in
  --   (y[0] #world())
  -- ]
  ----------------------------------------

  ---------- strengthening ----------------
  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  let y[0] : ?dos unit -> unit = _ in 
  (\ y[0] =>
    (y[2] y[0]))
  ]

  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  let y[0] : ?dos unit -> unit = _ in 
  ((\ y[0] => (y[2] y[0])) #uno())
  ]

  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  (y[0] #uno())
  ]

  -- broken
  -- expected: (uno : unit) & (dos : unit) -> unit * unit
  #eval infer_reduce 0 [lessterm|
  let y[0] : (uno : unit) -> unit = _ in 
  let y[0] : (dos : unit) -> unit = _ in 
  (\ y[0] =>
    ((y[2] y[0]), (y[1] y[0])))
  ]

  -- expected: ⊥ -> unit * unit
  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  let y[0] : ?dos unit -> unit = _ in 
  (\ y[0] =>
    ((y[2] y[0]), (y[1] y[0])))
  ]

  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  let y[0] = _ in 
  let y[0] = (y[1] y[0]) in 
  y[0]
  ]

  #eval infer_reduce 0 [lessterm|
  let y[0] : ?uno unit -> unit = _ in 
  let y[0] : ?dos unit -> unit = _ in 
  (\ y[0] =>
    let y[0] = (y[2] y[0]) in 
    let y[0] = (y[2] y[1]) in 
    (y[0], y[1]))
  ]

  ----------------------------------
  #eval [lessterm| @x = #hello () @y = #world ()]
  --------------------------------------

  #eval unify_decide 0 
    [lesstype| ?hello unit ] 
    [lesstype| α[0] ] 

  -- not well foundend: induction untagged 
  -- expected: false
  #eval unify_decide 0 
    [lesstype| ?hello unit ] 
    [lesstype| induct ?wrong unit | β[0] ] 

  -- potentially diverges - inductive type not well founded
  -- expected: false
  #eval unify_decide 0 
    [lesstype| ?hello unit ] 
    [lesstype| induct β[0] ] 

  def bad_nat_list := [lesstype| 
    induct 
      (?zero unit * ?nil unit) | 
      {(β[0] * β[1]) with β[0] * β[1] <: β[2]}
  ]

  -- expected: false
  #eval unify_decide 0 
    [lesstype| ?zero unit * ?nil unit ] 
    bad_nat_list

  def other_nat_list := [lesstype| 
    induct {(?succ β[0] * ?cons β[1]) with β[0] * β[1] <: β[2]}
  ]

  -- expected: false; base case is missing
  #eval unify_decide 0 
    [lesstype| ?succ ?zero unit * ?cons ?nil unit ] 
    other_nat_list

  #eval [lessterm|
  (\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  ))
  ]

  #eval infer_reduce 10 [lessterm|
  fix(\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  ))
  ]

  -- broken
  -- expected: ?succ ?zero unit
  #eval infer_reduce 10 [lessterm|
  (fix(\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  )) (#succ #succ #zero (), #succ #succ #succ #zero ()))
  ]

  ----------------------------------

  def gt := [lesstype| 
    induct  
      {?succ β[0] * ?zero unit} | 
      {?succ β[0] * ?succ β[1] with (β[0] * β[1]) <: β[2]}
  ]

  -------------------------------------------------

  def spec := [lesstype| 
  (α[0] * α[1]) -> (
    { β[0] with (x:β[0] & y:α[1] & z:α[0]) <: ⟨plus⟩} |
    { β[0] with (x:β[0] & y:α[0] & z:α[1]) <: ⟨plus⟩}
  )  
  ]

  -- Note: is this in effect, the same thing as PDR/IC3?
  -- That is, whatever is learned to strengthen the conclusion 
  -- is automatically applied to preceding iterations 
  -- due to the wrapping type in inductive binding 
  -- NOTE: this may have some non-termination depending on how occurs is used 
  #eval infer_simple 10 
  [lessterm|
  let y[0] : ⟨spec⟩ = fix(\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  )) in 
  y[0]
  ]

  -------------------------------------------------

  #eval infer_reduce 10 
  [lessterm|
  let y[0] = fix(\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  )) in 
  y[0]
  ]

  -- expected: ?succ ?zero unit 
  #eval infer_reduce 10 
  [lessterm|
  let y[0] = fix(\ y[0] => ( 
    \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1]))
    \ (#zero (), y[0]) => y[0]
    \ (y[0], #zero ()) => y[0] 
  )) in 
  (y[0] (#succ #succ #zero (), #succ #zero ()))
  ]

  def diff_rel :=
  [lesstype|
    induct 
      {?zero unit * β[0] * β[0]} | 
      {β[0] * ?zero unit * β[0]} |
      {(?succ β[1] * ?succ β[2] * β[0]) with (β[1] * β[2] * β[0]) <: β[3]}
  ]

  #eval unify_reduce 10
  [lesstype| ?succ ?succ ?zero unit * ?succ ?zero unit * α[0] ]
  diff_rel
  [lesstype| α[0] ]



  def plus_choice := [lesstype| 
  α[0] * α[1] * (
    { β[0] with (x:β[0] & y:α[1] & z:α[0]) <: ⟨plus⟩} |
    { β[0] with (x:β[0] & y:α[0] & z:α[1]) <: ⟨plus⟩}
  )  
  ]

  #eval unify_reduce 10
  plus_choice
  diff_rel
  [lesstype| α[0] ]


  -- #eval unify_reduce 10
  -- [lesstype|
  --   ? >> β[0] -> {β[0] with (β[1] * β[0]) <: ⟨diff_rel⟩}
  -- ]
  -- spec
  -- [lesstype| α[0] * α[1] ]

  ------------ transposition checking ----------------

  def list_ := [lesstype|
    induct 
      ?nil unit |
      ?cons β[0]
  ]

  -- #eval [lessterm| 
  --   let y[0] : ⟨nat_⟩ -> ⟨list_⟩ = fix(\ y[0] =>
  --     \ #zero() => #nil()  
  --     \ #succ y[0] => #cons (y[1] y[0]) 
  --   )
  --   in
  --   y[0]
  -- ] 

  -- #eval infer_reduce 0 [lessterm| 
  --   fix(\ y[0] =>
  --     \ #zero() => #nil()  
  --     \ #succ y[0] => #cons (y[1] y[0]) 
  --   )
  -- ]



  -- expected: true 
  #eval unify_decide 0
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| ⟨nat_⟩ * ⟨list_⟩ ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| ⟨nat_⟩ * ⟨nat_⟩ ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| ⟨nat_⟩ * ?nil unit ]

  -- expected: false
  #eval unify_decide 0
  [lesstype| ⟨nat_⟩ * ⟨list_⟩ ]
  [lesstype| ⟨nat_list⟩ ]


  ----- transposition construction ----
  
  -- expected: ⟨nat_⟩ * ⟨list_⟩
  #eval unify_reduce 10
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| α[1] * α[2] ]
  [lesstype| α[1] * α[2] ]

  -- expected: ⟨list_⟩
  #eval unify_reduce 10
  [lesstype| ⟨nat_list⟩ ]
  [lesstype| ⟨nat_⟩ * α[0] ]
  [lesstype|  α[0] ]

  #eval unify_decide 10
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ⊤ ]


  ----- transposition projection ----

  -- expected: false 
  #eval unify_decide 10
  [lesstype| {β[0] -> unit with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?zero unit -> unit ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| {β[0] -> unit with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ⟨nat_⟩ -> unit ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?zero unit ]

  -- expected: true 
  #eval unify_decide 10
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ⟨nat_⟩ ]

  -- expected: true 
  #eval unify_decide 10
  [lesstype| {2 // β[0] with β[0] * β[1] <: ⟨nat_list⟩} ]
  [lesstype| ⟨nat_⟩ ]

  -- expected: false
  #eval unify_decide 10
  [lesstype| {2 // β[0] with β[0] * β[1] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?zero unit ]

  ----------------------------

  -- expected: true 
  #eval unify_decide 10
  [lesstype| {β[0] with α[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ⟨list_⟩ ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?succ ?zero unit ]

  -- broken
  -- expected: true 
  #eval unify_decide 10
  [lesstype| ⟨nat_⟩ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ⟨nat_⟩ -> ⟨list_⟩ ]

  -- expected: true 
  #eval unify_decide 10
  [lesstype| ⟨nat_⟩ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]
  [lesstype| ?succ ?zero unit -> α[0] ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| ⟨nat_⟩ -> ⟨list_⟩ ]
  [lesstype| ⟨nat_⟩ >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| ⟨nat_⟩ -> ⟨list_⟩ ]
  [lesstype| α[0] -> {β[0] with α[0] * β[0] <: ⟨nat_list⟩} ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| ⟨list_⟩ ]
  [lesstype| {β[0] with α[0] * β[0] <: ⟨nat_list⟩} ]

  -- expected: false
  #eval unify_decide 10
  [lesstype| α[0] * ⟨list_⟩ ]
  [lesstype| ⟨nat_list⟩ ]

  -- expected: true 
  #eval unify_decide 10
  [lesstype| {β[0] with β[0] <: ⟨list_⟩} ]
  [lesstype| ⟨list_⟩ ]


  ------------------------------


  -- expected: true 
  #eval unify_decide 0
  [lesstype| ⟨nat_⟩ ]
  [lesstype|
    induct
      ?zero unit |
      {2 // ?succ β[0] with β[0] <: β[2]}
  ]

---------------- debugging

  #eval infer_reduce 0 [lessterm| 
    let y[0] : ⟨nat_⟩ -> ⟨list_⟩ = fix(\ y[0] =>
      \ #zero() => #nil()  
      \ #succ y[0] => #cons (y[1] y[0]) 
    )
    in
    y[0]
  ] 
  --------------------------------

  ------- proactive safely assgined ---------

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {β[0]} ]
  [lesstype|  ?ooga unit ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] <: ?ooga unit} ]
  [lesstype|  ?booga unit]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {3 // β[2] with β[0] * β[1] <: ⟨nat_list⟩} ]
  [lesstype| ⟨nat_⟩]

  -- expected: true 
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] <: ?ooga unit} ]
  [lesstype|  ?ooga unit | ?booga unit]

  -- expected: false
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] <: (?three unit)} ]
  [lesstype| ?one unit ]

  -- expected: false
  #eval unify_decide 0
  [lesstype| (?one unit | ?three unit) ]
  [lesstype| ?one unit ]

  -- expected: false
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] <: (?one unit | ?three unit)} ]
  [lesstype| ?one unit ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| (?one unit * ?two unit) | (?three unit * ?four unit) ]
  [lesstype| (?three unit * ?four unit)  ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit * ?two unit ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {2 // β[0]  with β[0] * β[1] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit ]

  -- expected: false 
  #eval unify_decide 10
  [lesstype| {β[0] with β[0] * α[0] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit  ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| {2 // β[0] with β[0] * β[1] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit ]

  -- expected: true 
  #eval unify_decide 0
  [lesstype| {2 // β[0] with β[0] * β[1] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit | ?three unit ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| (?one unit * ?two unit) | (?three unit * ?four unit) ]
  [lesstype| ?one unit  ]

  -- expected: true 
  #eval unify_decide 10 
  [lesstype| {β[0] with β[0] * α[0] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit | ?three unit  ]

  -- expected: false 
  #eval unify_decide 10 
  [lesstype| {β[0] with β[0] * α[0] <: (?one unit * ?two unit) | (?three unit * ?four unit)} ]
  [lesstype| ?one unit  ]



--------------------- universal introduction subtyping ----------------

  -- broken
  -- expected: false 
  #eval unify_decide 0
  [lesstype| ?one unit  ]
  [lesstype| {(β[0] | α[0]) -> β[0] with (β[0] | α[0]) <: (?one unit | ?two unit) & (?three unit | ?four unit) } >> β[0] ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| ?one unit  ]
  [lesstype| (?one unit | ?two unit) & (?three unit | ?four unit) ]

  -- broken
  -- expected: false 
  #eval unify_decide 0
  [lesstype| ?one unit  ]
  [lesstype|  {(β[0] | α[0]) -> β[0] with (β[0] | α[0]) <: (?one unit | ?two unit) * (?three unit | ?four unit)} >> β[0] ]

  -- expected: false 
  #eval unify_decide 0
  [lesstype| ?one unit  ]
  [lesstype| (?one unit | ?two unit) * (?three unit | ?four unit) ]


---------------------------------
  #eval infer_reduce 1 [lessterm| 
    let y[0] : α[0] = _ in
    y[0] 
  ] 

  def ooga := [lesstype| 
    induct
      {?zero unit * β[0]} |
      {?succ β[0] * ?succ β[1] with β[0] * β[1] <: β[2]}
  ]

  #eval unify_reduce 10
  [lesstype| α[2] * α[3] -> {β[0] with (α[2] * β[0]) * (α[3] * β[0]) <: ⟨ooga⟩ * ⟨ooga⟩} ]
  [lesstype| α[0] * α[1] -> α[1] ]
  [lesstype| ?hmm unit ]


--------------------------------------------------------

  -- expected: ⊥
  #eval infer_reduce 0 [lessterm| 
    let y[0] : (? >> ? >> β[0] * β[1] -> {1 // β[0] with (β[0] * β[1]) <: ⟨nat_⟩ * ⟨nat_⟩}) = 
    (\ (y[0], y[1]) => y[0]) in
    y[0]
  ] 

------- argument type inference ------

  -- expected: the argument type should be refined by the function application 
  -- should be similar to the function type, but just an exisitential without the return type
  -- the return type is inferred, but the argument type is not inferred 
  -- e.g.
  /-
    ({2 // β[0] with (β[0] * β[1]) <: (induct (
          (?zero unit * ?nil unit) |
          {2 // (?succ β[1] * ?cons β[0]) with (β[1] * β[0]) <: β[2]}
    ))})
  -/
  #eval unify_reduce 50
  [lesstype| 
  (α[10] >> (β[0] ->
  {1 // β[0] with (β[1] * β[0]) <: (induct ((?zero unit * ?nil unit) |
     {2 // (?succ β[1] * ?cons β[0]) with (β[1] * β[0]) <: β[2]}))}))
  ]
  [lesstype| α[20] -> α[12]]
  [lesstype| α[20]]


  -- expected: the argument type should be refined by the function application 
  -- e.g.
  /-
    ({2 // β[0] with (β[0] * β[1]) <: (induct (
          (?zero unit * ?nil unit) |
          {2 // (?succ β[1] * ?cons β[0]) with (β[1] * β[0]) <: β[2]}
    ))})
  -/
  #eval infer_reduce 0 [lessterm| 
    let y[0] = fix (\ y[0] =>
      \ (#zero()) => #nil()  
      \ (#succ y[0]) => #cons (y[1] y[0]) 
    ) in
    let y[0] = _ in
    let y[0] = (y[1] (y[0])) in
    y[1]
  ] 

--------------------------------------

  -- better: notions of ?zero and ?true appear in inferred type? 
  -- this requires including relational constraints in generalization
  -- this works! 
  #eval infer_reduce 0 [lessterm| 
    (\ (y[0]) => ((fix (\ y[0] =>
      \ (#zero(), #zero()) => #true()  
    )) (y[0])))
  ] 

  -- broken
  -- expected: ?true unit
  #eval infer_reduce 0 [lessterm| 
    let y[0] = (\ (y[0]) => ((fix (\ y[0] =>
      \ (#zero(), #zero()) => #true()  
    )) (y[0])))
    in
    (y[0] (#zero(), #zero()))
  ] 

  def nat_pair := [lesstype|
    induct
      {(?zero unit * ⟨nat_⟩)} 
      | 
      {(?succ β[0] * ?succ β[1]) with (β[0] * β[1]) <: β[2] } 
      | 
      {(?succ ⟨nat_⟩ * ?zero unit)}
  ]

  -- expected: relational function type
  #eval infer_reduce 0 [lessterm| 
    fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    )
  ] 
    
  -- expected: ?false unit
  #eval infer_reduce 0 [lessterm| 
    -- less than or equal:
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    (
      (\ y[0] => y[0])
      (y[0] (#succ #succ #zero(), #succ #zero()))
    )
  ] 

  -- expected: the argument type should be refined by the function application 
  #eval infer_reduce 0 [lessterm| 
    -- less than or equal:
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    (\ (y[0], y[1]) => 
      (
        let y[0] = (y[2] (y[0], y[1])) in
        y[1]
      )
    )
  ] 

  -- expected: type maintains relational information 
  #eval infer_reduce 0 [lessterm| 
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    let y[0] = (\ (y[0], y[1]) => 
        (y[2] (y[0], y[1]))
    ) in
    y[0]
  ] 


  -- NOTE: not reducible 
  -- expected: ⊥
  #eval unify_reduce 10
  [lesstype| (α[1] * α[2]) * ?true unit ]
  [lesstype|
  induct (
      {1 // ((?zero unit * β[0]) * ?true unit)} |
      {3 // ((?succ β[0] * ?succ β[1]) * β[2]) with ((β[0] * β[1]) * β[2]) <: β[3]} |
      {1 // ((?succ β[0] * ?zero unit) * ?false unit)}
  )
  ]
  [lesstype| (α[1] * α[2]) * ?true unit ]

  -- expected: ?? 
  #eval unify_decide 0
  [lesstype|
    ({1 // β[0] with ((α[20] * α[18]) * β[0]) <: 
      (induct ({1 // ((?zero unit * β[0]) * ?true unit)} |
      ({3 // ((?succ β[1] * ?succ β[2]) * β[0]) with ((β[1] * β[2]) * β[0]) <: β[3]} |
      {1 // ((?succ β[0] * ?zero unit) * ?false unit)})))}
  )
  ]
  [lesstype| ?true unit ]


  -- expected: type is maintained after identity function application
  #eval infer_reduce 0 [lessterm| 
    -- less than or equal:
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    (\ (y[0], y[1]) => 
      (
        (\ y[0] => y[0])
        (y[2] (y[0], y[1]))
      )
    )
  ]

  -- expected: type that describes max invariant
  -- e.g. X -> Y -> {Z with (X * Z) <: LE, (Y * Z) <: LE}
  #eval infer_reduce 0 [lessterm| 
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    let y[0] = _ in
    let y[0] = _ in
    (
      (
      \ #true() => y[1]
      \ #false() => y[0]
      )
      (y[2] (y[0], y[1]))
    )
  ] 



  -- expected: 
  /-
  (? >> (? >> ({2 // (β[1] * β[0]) with (β[1] * β[0]) <: (induct ({1 // (?zero unit * β[0])} |
        ({3 // (?succ β[1] * ?succ β[2]) with (β[1] * β[2]) <: β[3]} | {1 // (?succ β[0] * ?zero unit)})))} >> β[0])))
  -/
  #eval unify_reduce 10 
  [lesstype| 
  α[0] * α[1]
  ]
  [lesstype| 
  (induct (
    {1 // (?zero unit * β[0])} | 
    {3 // (?succ β[1] * ?succ β[2]) with (β[1] * β[2]) <: β[3]} |
    {1 // (?succ β[0] * ?zero unit)}
  )) 
  ]
  [lesstype| 
  α[0] * α[1]
  ]

  -- expected: 
  /-
  (? >> (? >> ({2 // (β[1] * β[0]) with (β[1] * β[0]) <: (induct ({1 // (?zero unit * β[0])} |
        ({3 // (?succ β[1] * ?succ β[2]) with (β[1] * β[2]) <: β[3]} | {1 // (?succ β[0] * ?zero unit)})))} >> β[0])))
  -/
  #eval unify_reduce 10 
  [lesstype| 
  (induct (
    {1 // (?zero unit * β[0])} | 
    {3 // (?succ β[1] * ?succ β[2]) with (β[1] * β[2]) <: β[3]} |
    {1 // (?succ β[0] * ?zero unit)}
  )) >> (β[0] ->
    {1 // β[0] with (β[1] * β[0]) <: (induct 
      {1 // ((?zero unit * β[0]) * ?true unit)} |
      {3 // ((?succ β[1] * ?succ β[2]) * β[0]) with ((β[1] * β[2]) * β[0]) <: β[3]} |
      {1 // ((?succ β[0] * ?zero unit) * ?false unit)}
    )}
  )
    ]
  [lesstype| 
  α[0] * α[1] -> α[2]
  ]
  [lesstype| 
  α[0] * α[1]
  ]


  -- broken: type is big and ugly and causes non-termination when there's a safety check in left-existential
  -- expected: type that describes max invariant
  -- e.g. X -> Y -> {Z with (X * Z) <: LE, (Y * Z) <: LE}
  #eval infer_reduce 0 [lessterm| 
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    (\ (y[0], y[1]) => 
      (
        (
        \ #true() => y[1]
        \ #false() => y[0]
        )
        (y[2] (y[0], y[1]))
      )
    ) 
  ] 


  -- NOTE: max of the two inputs  
  -- broken; this fails if there is parameter type added to fix type
  -- expected: ?succ ?succ ?succ ?zero unit   
  #eval infer_reduce 0 [lessterm| 
    let y[0] = fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ) in
    let y[0] = (\ (y[0], y[1]) => 
      (
        (
        \ #true() => y[1]
        \ #false() => y[0]
        )
        (y[2] (y[0], y[1]))
      )
    ) in
    (y[0] (#succ #zero(), #succ #succ #succ #zero()))
  ] 


  --------------- debugging ---------------

  -- broken
  -- expected: ?false unit 
  #eval infer_reduce 0 [lessterm| 
    (
      (fix (\ y[0] =>
        \ (#zero(), y[0]) => #true()  
        \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
        \ (#succ y[0], #zero()) => #false() 
      ))
      (#succ #succ #zero(), #succ #zero())
    )
  ] 

  #eval infer_reduce 0 [lessterm| 
    let y[0] = (fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    )) in
    (y[0] (#succ #succ #zero(), #succ #zero()))
  ] 

  #eval infer_reduce 0 [lessterm| 
    (fix (\ y[0] =>
      \ (#zero(), y[0]) => #true()  
      \ (#succ y[0], #succ y[1]) => (y[2] (y[0], y[1])) 
      \ (#succ y[0], #zero()) => #false() 
    ))
  ] 



  #eval unify_decide 10 
  [lesstype| ?succ ?zero unit * ?zero unit]
  nat_pair


  def le_ := [lesstype|
    induct
      {(?zero unit * β[0]) * ?true unit} 
      | 
      {(?succ β[0] * ?succ β[1]) * β[2] with (β[0] * β[1]) * β[2] <: β[3] } 
      | 
      {(?succ β[0] * ?zero unit) * ?false unit}
  ]

  -- expected: ⊥ 
  #eval unify_reduce 10 
  [lesstype|
    (?ooga unit >>
       (β[0] -> {1 // β[0] with (β[1] * β[0]) <: ⟨le_⟩}))
  ]
  [lesstype| ?succ ?succ ?zero unit * ?succ ?zero unit -> α[0]]
  [lesstype| α[0] ]

  -- expected: ?false unit 
  #eval unify_reduce 10 
  [lesstype| (⟨nat_pair⟩ >> (β[0] -> {1 // β[0] with (β[1] * β[0]) <: ⟨le_⟩})) ]
  [lesstype| ?succ ?succ ?zero unit * ?succ ?zero unit -> α[0]]
  [lesstype| α[0] ]

  ----------------------------
  -- incomplete without model-based subtyping
  ----------------------------
  -- URL: https://pnwamk.github.io/sst-tutorial/#%28part._sec~3asemantic-subtyping%29
  #eval unify_decide 0
  [lesstype| (?x unit | ?y unit) * ?y unit ] 
  [lesstype| (?x unit * ?y unit) | (?y unit * ?y unit) ] 

  -------------------------

  -- expected: (?spanish unit | ?english unit)
  #eval infer_reduce 10 [lessterm|
    let y[0] : α[0] >> β[0] -> {β[0] with β[1] * β[0] <: (?uno unit * ?dos unit) | (?one unit * ?two unit)} = _ in
    let y[0] : α[1] = _ in
    (
      (\ #dos() => #spanish() \ #two() => #english())
      (y[1] y[0])
    ) 
  ]

  -----------  argument type strengthening ----------

  -- expected: ?uno unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : ?uno unit -> ?dos unit = _ in
    let y[0] = _ in
    let y[0] = (y[1] y[0]) in
    y[1]
  ]

  -- expected: ?uno unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : ? >> β[0] -> {β[0] with β[1] * β[0] <: (?uno unit * ?dos unit)} = _ in
    let y[0] = _ in
    (
      (\ #dos() => y[0])
      (y[1] y[0])
    ) 
  ]

  -- expected: ?uno unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : ?uno unit -> ?dos unit = _ in
    let y[0] = _ in
    (
      (\ #dos() => y[0])
      (y[1] y[0])
    ) 
  ]

  -- requires local strengthening in left-existential
  -- expected: ?uno unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : α[2] >> β[0] -> {β[0] with β[1] * β[0] <: (?uno unit * ?dos unit)} = _ in
    let y[0] = _ in
    (
      (\ #dos() => y[0])
      (y[1] y[0])
    ) 
  ]

  -- expected: ?uno unit | ?other unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : ? >> β[0] -> {β[0] with β[1] * β[0] <: (?uno unit * ?dos unit) | (?one unit * ?two unit)} = _ in
    let y[0] = _ in
    (
      (\ #dos() => y[0] \ #two() => #other())
      (y[1] y[0])
    ) 
  ]

  -- expected: ?uno unit 
  #eval infer_reduce 10 [lessterm|
    let y[0] : ? >> β[0] -> {β[0] with β[1] * β[0] <: (?uno unit * ?dos unit) | (?one unit * ?two unit)} = _ in
    let y[0] = _ in
    (
      (\ #dos() => y[0] \ #two() => #uno())
      (y[1] y[0])
    ) 
  ]


  -----------  local strengthening ----------

  -- expected: (?one unit | ?three unit) 
  #eval infer_reduce 0 [lessterm|
    let y[0] = _ in
    let y[0] = (
      (\ #one() => #two() \ #three() => #four())
      y[0]
    ) in
    y[1]
  ]

  -- expected: ?one unit
  #eval infer_reduce 0 [lessterm|
    let y[0] = _ in
    (
      (\ #one() => y[0] \ #three() => #one ())
      y[0]
    )
  ]

  -- expected: ⊥ 
  #eval infer_reduce 0 [lessterm|
    let y[0] : ?one unit | ?two unit = _ in
    (
      (\ #one() => y[0] \ #three() => #one ())
      y[0]
    )
  ]

  -----------  implication existential ----------

  -- broken
  -- expected: unit 
  #eval unify_reduce 10 
  [lesstype| (?one unit -> unit) & (?three unit -> unit) ]
  [lesstype| {β[0] with β[0] <: (?one unit | ?three unit)} -> α[7] ]
  [lesstype| α[7] ]

  -- expected: ⊥ 
  #eval unify_reduce 10 
  [lesstype| {β[0] with β[0] <: (?one unit | ?three unit)} ]
  [lesstype| ?one unit ]
  [lesstype| ?unexpected unit ]


  -- expected: ?one unit 
  #eval infer_reduce 0 [lessterm|
    let y[0] : {β[0] with β[0] <: ?one unit | ?three unit} = _ in
    (
      (\ #one() => y[0] \ #three() => #one ())
      y[0]
    )
  ]

  -- broken
  -- expected: ?one unit | ?three unit 
  #eval infer_reduce 0 [lessterm|
    let y[0] : {β[0] with β[0] <: ?one unit | ?three unit} = _ in
    (
      (\ #one() => y[0] \ #three() => y[0])
      y[0]
    )
  ]


  ---------- implication union ---------
  -- (S1 -> T) & (S2 -> T) <: (S1 | S2 -> T) 


  -- expected: unit
  #eval unify_reduce 10 
  [lesstype| (?one unit -> unit) & (?three unit -> unit) ]
  [lesstype| (?one unit | ?three unit) -> α[7] ]
  [lesstype| α[7] ]


  -- expected: ?four unit
  #eval infer_reduce 0 [lessterm|
    let y[0] : ?one unit | ?three unit = _ in
    (
      (\ #one() => #four() \ #three() => #four ())
      y[0]
    )
  ]

  -- expected: ?two unit * ?four unit
  #eval unify_reduce 10 
  [lesstype| (?one unit -> ?two unit) & (?three unit -> ?four unit) ]
  [lesstype| (?one unit -> α[7]) & (?three unit -> α[8])]
  [lesstype| α[7] * α[8] ]


  -- expected: ?two unit | ?four unit
  #eval unify_reduce 10 
  [lesstype| (?one unit -> ?two unit) & (?three unit -> ?four unit) ]
  [lesstype| (?one unit -> α[7]) & (?three unit -> α[7])]
  [lesstype| α[7] ]

  -- NOTE: requires expandable variables
  -- expected: ?two unit | ?four unit
  #eval unify_reduce 10
  [lesstype| (?one unit -> ?two unit) & (?three unit -> ?four unit) ]
  [lesstype| (?one unit | ?three unit) -> α[7] ]
  [lesstype| α[7] ]

  ----------------------
  /-
                                                      Y <: ?'
                                                  --------------
                                                    Y <: B | ?'
                                                  --------------------
    B <: ?                                            Y <: ?
------------------------                     ------------------------
  (A -> B) <: (A -> ?)                         (X -> Y) <: (X -> ?) 
---------------------------------          -----------------------------------
  (A -> B & X -> Y) <: (A -> ?),            (A -> B & X -> Y) <: (X -> ?)
--------------------------------------------------------------------------------
  (A -> B & X -> Y) <: (A | X) -> ?


  -- NOTE: requires expanding ? into B | Y
  -- since it starts as a variable; union a variable to indicate it can expand 
  -/

-----------------

  -- broken
  -- NOTE: variable α[7] should not be refined
  -- it should be marked as expandable
  -- expected: ?two | ?four
  #eval unify_reduce 10
  [lesstype| (?one unit -> ?two unit) & (?three unit -> ?four unit) ]
  [lesstype| (?one unit | ?three unit) -> {β[0] with β[0] <: α[7]} ]
  [lesstype| α[7] ]


-----------------

  #eval unify_simple 10
  [lesstype| (?one unit -> ?two unit)  ]
  [lesstype| (?one unit | ?three unit) -> {β[0]} ]

  #eval unify_simple 10
  [lesstype| (?three unit -> ?four unit) ]
  [lesstype| (?one unit | ?three unit) -> {β[0]} ]


---------------------------------------------------


  -- expected: ?one unit | ?three unit
  #eval unify_reduce 10
  [lesstype| (?one unit -> ?two unit) & (?three unit -> ?four unit) ]
  [lesstype| α[7] -> (?two unit | ?four unit) ]
  [lesstype| α[7] ]


  -------------------------------------------
  -- requires weakening of return type in app
  -- expected: ?two unit | ?four unit
  -- may be affected initial expected type in infer_reduce 
  #eval infer_reduce 0 [lessterm|
    let y[0] : ?one unit | ?three unit = _ in
    (
      (\ #one() => #two() \ #three() => #four ())
      y[0]
    )
  ]

  -- broken
  -- expected: ?one unit
  #eval infer_reduce 0 [lessterm|
    let y[0] : ?one unit | ?three unit = _ in
    (
      (\ #one() => y[0] \ #three() => #one ())
      y[0]
    )
  ]

  ---------- implication intersection ---------
  -- (S -> T1) & (S -> T2) <: (S -> T1 & T2)

  -- expected: true
  #eval unify_decide 10 
  [lesstype| (?one unit -> ?two unit) & (?one unit -> ?three unit) ]
  [lesstype| ?one unit -> (?two unit & ?three unit)]

  ----------------------------------

  -- NOTE: in right-existential: if key is not matchable; save the relation
  -- expected: true 
  #eval unify_decide 10 
  [lesstype| ?succ α[1] * α[0] ]
  [lesstype| {2 // (?succ β[0] * ?cons β[1]) with (β[0] * β[1]) <: ⟨nat_list⟩} ]

  ---------- relational propagation ---------
  -- broken
  -- NOTE: variables are no longer expanded; 
  -- need a generalized disjunction elimination rule 
  -- or some general elimination rule for intersection of implication; e.g a factoring rule.
  -- expected ?thing unit | ?other unit
  #eval unify_reduce 10 
  [lesstype| (?zero unit -> ?thing unit) & (?succ α[1] -> ?other unit)]
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} -> α[2]]
  [lesstype| α[2] ]

  -- broken
  -- expected: ?other unit | ?thing unit 
  #eval unify_reduce 10 
  [lesstype| (?succ ⟨nat_⟩ -> ?other unit) & (?zero unit -> ?thing unit)]
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} -> α[2]]
  [lesstype| α[2] ]

  -- broken
  -- expected: ?nil unit | ?other unit
  #eval unify_reduce 10 
  [lesstype| (?zero unit -> α[0]) & (?succ α[1] -> ?other unit)]
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} -> α[2]]
  [lesstype| α[2] ]

  -- broken
  -- expected: ?nil unit | ?other unit
  #eval unify_reduce 10 
  [lesstype| (?zero unit -> α[0]) & (?succ ⟨list_⟩ -> ?other unit)]
  [lesstype| {β[0] with β[0] * α[0] <: ⟨nat_list⟩} -> α[2]]
  [lesstype| α[2] ]

  -- broken
  -- expected: ?nil unit | ?other unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : α[0] = _ in
    let y[0] : {β[0] with β[0] * α[0] <: ⟨nat_list⟩} = _ in
    (
      (\ #zero() => y[1] \ #succ y[0] => #other())
      y[0]
    )
  ]

  ----- using function application --------

  -- NOTE: requires application packing an existential for return type
  -- return type should not be refined further after return
  -- wrapping in existential is needed to prevent further strengthening of return type
  -- additionally, existential contains mechanism for safe strengthening 
  -- expected: ?zero unit | ?other unit
  #eval infer_reduce 10 [lessterm|
    let y[0] : α[0] >> β[0] -> {β[0] with β[1] * β[0] <: ⟨nat_list⟩} = _ in
    let y[0] = _ in
    (
      (\ #nil() => y[0] \ #cons y[0] => #other())
      (y[1] y[0])
    )
  ]


  -- broken
  -- argument type is weaker than parameter type
  -- expected: ⊥
  #eval infer_reduce 10 [lessterm|
    let y[0] : α[0] = _ in
    let y[0] : {β[0] with β[0] * α[0] <: ⟨nat_list⟩} = _ in
    (
      (\ #zero() => y[1])
      y[0]
    )
  ]


  -------- collapsing ------------

  -- broken
  -- NOTE: requires collapsing to ensure what must type check, rather than what may type check 
  -- NOTE: collapsing should happen at argument site, rather than return site
    -- to ensure that contextual information is not lost
    -- e.g. learning the type of the function that is applied, whose variables may not appear in return type. 
  -- NOTE: packing serves a similar purpose, albeit for leveraging left-existential safe strengthening 
    -- therefore, it makes sense to perform packing at argument site too
  -- expected: ⊥
  #eval infer_reduce 0 [lessterm| 
    let y[0] = _ in 
    let y[0] = (( \ #one() => #two() \ #three() => #four()) y[0]) in
    ((\ #two() => #thing()) y[0])
  ]


  --------------------------------------


  -- expected: ((?one unit -> ?two unit) & (?three unit -> ?four unit))
  #eval infer_reduce 0 [lessterm| 
    ( \ #one() => #two() \ #three() => #four())
  ]

  -- broken: inferring union instead of intersection
  -- expected: ((?one unit -> ?two unit) & (?three unit -> ?four unit))
  #eval infer_reduce 0 [lessterm| 
    (\y[0] => (( \ #one() => #two() \ #three() => #four()) y[0]))
  ]

  ------- path selection --------------
  -- expected: ?two unit 
  #eval infer_reduce 0 [lessterm| 
    (( \ #one() => #two() \ #three() => #four()) #one()) 
  ]

------------------------------

  -- broken
  -- expected: false
  #eval unify_decide 0
  [lesstype| {β[0] with β[0] * ?cons ?cons ?nil unit <: ⟨nat_list⟩}]
  [lesstype| ?succ ?foo ?zero unit ]

  #eval unify_reduce 10
  [lesstype| {β[0] with β[0] * ?cons ?cons ?nil unit <: ⟨nat_list⟩}]
  [lesstype| α[0]]
  [lesstype| α[0]]

  #eval unify_reduce 10
  [lesstype| α[0] * ?cons ?cons ?nil unit]
  nat_list
  [lesstype| α[0] ]

  #eval unify_decide 10
  [lesstype| ?succ ?foo ?zero unit ]
  [lesstype| ?succ ?succ ?zero unit ]

  --------- sound application --------

  -- expected: false
  #eval unify_decide 10
  [lesstype|
    {β[0] * β[1] with (x : β[0] & y : β[1] & z : ?succ ?zero unit ) <: ⟨plus⟩}
  ]
  [lesstype| (?zero unit * ?succ ?zero unit) ]

  -- expected: ((?zero unit * ?succ ?zero unit) | (?succ ?zero unit * ?zero unit))
  #eval unify_reduce 10
  [lesstype|
    {β[0] * β[1] with (x : β[0] & y : β[1] & z : ?succ ?zero unit ) <: ⟨plus⟩}
  ]
  [lesstype| α[7] ]
  [lesstype| α[7] ]

  #eval unify_reduce 10
  [lesstype|
    ? >> β[0] -> {β[0] * β[1] with (x : β[0] & y : β[1] & z : β[2]) <: ⟨plus⟩}
  ]
  [lesstype| ?succ ?zero unit -> α[7] ]
  [lesstype| α[7] ]

  -- expected: ((?zero unit * ?succ ?zero unit) | (?succ ?zero unit * ?zero unit))
  #eval infer_reduce 10
  [lessterm|
    let y[0] : ? >> β[0] -> {β[0] * β[1] with (x : β[0] & y : β[1] & z : β[2]) <: ⟨plus⟩} =  _ in
    (y[0] #succ #zero ())
  ]
  -----------------------------------

  -- expected: ⊥
  #eval unify_reduce 10
  [lesstype|
    (?zero unit * ?succ ?zero unit) -> unit
  ]
  [lesstype| ((?zero unit * ?succ ?zero unit) | (?succ ?zero unit * ?zero unit)) -> α[7] ]
  [lesstype| α[7] ]

  -- broken
  -- NOTE: in app rule: collapse arg's union type before applying 
  -- expected: ⊥
  #eval infer_reduce 10
  [lessterm|
    let y[0] : ? >> β[0] -> {β[0] * β[1] with (x : β[0] & y : β[1] & z : β[2]) <: ⟨plus⟩} =  _ in
    let y[0] : (?zero unit * ?succ ?zero unit) -> unit = _ in 
    (y[0] (y[1] #succ #zero ()))

  ]

  -------------------------------------------
  ---------- let binding soundness -----------

  -- expected: ⊥
  #eval infer_reduce 10
  [lessterm|
    let y[0] : ? >> β[0] -> {β[0] * β[1] with (x : β[0] & y : β[1] & z : β[2]) <: ⟨plus⟩} =  _ in
    let y[0] : (?zero unit * ?succ ?zero unit) = (y[0] #succ #zero ()) in
    y[0]

  ]


end Nameless 