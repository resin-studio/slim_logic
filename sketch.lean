-- slim logic sketch --

-- label --
/-
l ∈ String 
-/

-- identifier --
/-
x ∈ String 
-/

-- type --
inductive Ty where              -- τ ::=
| Id : String -> Ty             --   x              variable type : *
| Dyn : Ty                      --   ?              dynamic type : *
| Tag : String -> Ty            --   $l             tag type : *
| Variant : String -> Ty        --   #l : τ         variant type : *
| Field : String -> Ty -> Ty    --   .l : τ         field type : *
| Inter : Ty -> Ty -> Ty        --   τ & τ          intersection type : *
| Union : Ty -> Ty -> Ty        --   τ | τ          union type : *
| Arrow : Ty -> Ty -> Ty        --   τ -> τ         implication type where τ : * or higher kind where τ : **
| Mu : Ty -> Ty -> Ty           --   μ x . τ        inductive type : * where x : κ
| Uni : String -> Ty -> Ty      --   ∀ x . τ        universal type : ** where x : κ (predicative) or x : ** (impredicative)
| Exi : String -> Ty -> Ty      --   ∃ x . τ        existential type : ** where x : κ (predicative) or x : ** (impredicative)
| Rel : Tm -> Tm -> Ty -> Ty    --   { t | t : τ }  relational type : * where τ : * 
| Star : Ty                     --   *              unit ground kind : **
| Anno : Ty -> Ty               --   [τ]            payload ground kind where τ : [τ] <: * : **


-- type notes --
/-
- A type is a syntactic notion
- A kind is a semantic notion that categorizes both term and type syntax
  - τ : κ : **, i.e. a type belongs to a kind, which belongs to ** 
  - τ => τ : κ -> κ : **, i.e. a type constructor belongs to a kind, which belongs to ** 
  - related: **Fω** - https://xavierleroy.org/CdF/2018-2019/2.pdf
- predicativity is recognized by treating quantifiers as large types belonging to **
  - unlinke kinds which also belong to **, only terms, not types belong to 
  - related work: **1ml** by Andreas Rossberg - https://people.mpi-sws.org/~rossberg/1ml/1ml.pdf
- universal and existential types quantify over types of kind *, resulting in types of kind **
- these type quantifiers are primitive in this weak logic
- in a stronger dependently typed / higher kinded logic, these types would be subsumed by implication 
- composite types defined in terms of subtyping combinators --
  - A ∧ B = (.left : A) & (.right : B)           -- product
  - A ∨ B = (#left : A) | (#right : B)           -- sum
- relational types 
  - refine a type in terms of typings **refinement types in ML**
  - relate content of a type to other values **liquid types**
    - liquid types refine using predicate expressions, rather than typings
    - liquid types rely on SMT solvers check refinements
  - relate content of a type AND refine types in terms of typings **novel** 
    - obviate the need for outsourcing to SMT solver, 
    - allow reusing definitions for both checking and refinement
-/

-- term --

inductive Cases where
| Base : Tm -> Tm -> Cases
| Step : Tm -> Tm -> Cases -> Cases

inductive Fields where
| Base : String -> Tm -> Fields 
| Step : String -> Tm -> Fields -> Fields 

inductive Tm where                  -- t ::=
| Irrel : Tm                        --   _                               -- irrelevant pattern / inferred expression
| Memb : Tm -> Ty -> Tm             --   t : τ                           -- typed pattern where τ : κ : **
| Id : String -> Tm                 --   x                               -- variable expression / pattern
| Tag : String -> Tm                --   #l                              -- tag expression / pattern
| Variant : String -> tm -> Tm      --   #l t                            -- variant expression / pattern
| Match : Tm -> Cases -> Tm         --   match t (case t => t ...)       -- pattern matching 
| Record : Fields -> Tm             --   .l t, ...                       -- record expression / pattern
| Proj : Fields -> Tm               --   t.l                             -- record projection
| Fun : Tm -> Tm -> Tm              --   t => t                          -- function abstraction
| App : Tm -> Tm -> Tm              --   t t                             -- function application
| Let : Tm -> Tm -> Tm -> Tm        --   let t = t in t                  -- binding
| Fix : Tm -> Tm                    --   fix t                           -- recursion
| Ty : Ty -> Tm                     --   τ                               -- type as term : *





-- term notes --
/-
- term sugar
  - ⟦(t1 , t2)⟧  ~> (.left ⟦t1⟧, .right ⟦t2⟧)
- we collapse the notion of type with term
  - consistent with Python's unstratified syntax
-/


-- context --
/-
Γ ::= 
  .        -- empty context
  Γ, x : τ -- context extended with indentifier and its type 
-/

-- examples --
/-
let list = α : * => μ list α . $nil | #cons:(α ∧ list α)

let nat = μ nat . ?zero | #succ:nat

let list_len = α : * => μ list_len . ($nil ∧ $zero) | {(#cons (_ : α, xs), #succ n) | (xs, n) : list_len α}

let 4 = #succ (#succ (#succ (#succ $zero)))

let list_4 = {xs | (xs, 4) : list_len nat}

%check 1 :: 2 :: 3 :: 4 :: $nil : list_4
-/