{-# OPTIONS --without-K --sized-types --no-guardedness  #-}

module DeBruijn where

-- This module defines a data type for lambda calculus expressions
-- represented by de Bruijn indices and a substitution operations. 
-- It refers to N.G. de Bruijn's article:
--    "Lambda Calculus notation with nameless dummies,
--     A tool for automatic formula manipulation with application 
--     to the Church-Rosser Theorem"
-- The goal of this module is to interpolate de Bruijn's original definitions
-- to those shown in PFLA.

open import Data.Product using (_,_)
open import Data.Nat using (ℕ; zero; suc; _+_; _≤_ ;  z≤n ; s≤s ; ≤-pred )
open import Codata.Stream 
  using (Stream; _∷_; lookup; map; zipWith; tail; nats; unfold)
open import Codata.Thunk using (force)
open import Size
import Relation.Binary.PropositionalEquality as Eq
open Eq using (_≡_; refl; cong)


-- Syntax: Here is the definition of "namefree" expressions
-- that we work with in this file.

infix  8  #_
infix  6  ƛ_
infixl 7  _·_

-- NF stands for "namefree"
data NF : Set where
  #_  : ℕ -> NF          -- variable (index)
  ƛ_  : NF -> NF         -- abstraction
  _·_ : NF -> NF -> NF   -- application

{- 

Take a moment to compare this definition with the one shown in
Section 5 of de Bruijn's article.

We make a few changes from de Bruijn's definition:

    1. We start counting indices from 0 instead of 1
    2. We drop constants and primitive function symbols
    3. We use single application (M · N) instead of 
       multi-application with a special "A" symbol
       i.e. A( M1 , M2 , ... )

    4. Instead of capital Greek letters for lambda expressions
       (Σ, Ω), we use M, N, P as meta variables.
-}


-- Here are some Church numerals expressed in this notation
-- (Note: due to Agda's flexible treatment of symbols in identifiers, 
-- almost all tokens must be separated by spaces.)


-- λ s. λ z. s (s z) 
twoᶜ : NF
twoᶜ = ƛ ƛ (# 1 · (# 1 · # 0))

-- λ s. λ z. s (s (s (s z))) 
fourᶜ : NF
fourᶜ = ƛ ƛ (# 1 · (# 1 · (# 1 · (# 1 · # 0))))

-- λ m. λ n. λ s. λ z. m s (n s z)
plusᶜ : NF
plusᶜ = ƛ ƛ ƛ ƛ (# 3 · # 1 · (# 2 · # 1 · # 0))

-- NOTE: 2+2ᶜ is a variable name in Agda
2+2ᶜ : NF
2+2ᶜ = plusᶜ · twoᶜ · twoᶜ

-- The "scope" of a name-free expression is a bound on the 
-- largest index that appears in the expression. This bound 
-- does not need to be tight, and an expression could have 
-- multiple scopes. However, there is a unique minimum scope.
-- If this were a typed language, you could think of the scope 
-- as the length of the typing context needed to type check the 
-- expression.

data scope :  ℕ -> NF -> Set where
  d-# : ∀ { x n } 
       -> x ≤ n 
    -------------------------
       -> scope n (# x)

  d-ƛ : ∀ { n M }
      -> scope (suc n) M
    ---------------------
      -> scope n (ƛ M) 

  d-· : ∀ { n L M }
      -> scope n L 
      -> scope n M 
    ----------------------
     -> scope n (L · M) 


------------------------------
-- Substitution (Section 6)

module DeBruijn where

   {- 

   N. G. de Bruijn represents substitutions using an infinite
   list of lambda terms, ordered right-to-left. This
   corresponds to replacing variable at index i with the term
   at position i in the list. (Also, recall that indexing
   starts at 1 for de Bruijn).
   
   We can model a similar definition in Agda using a
   *coinductive stream* of namefree terms. Agda's streams are
   written left-to-right and indexing starts at 0. (See
   Codata.Stream from the standard library for more details.)
   -}

   -- A substitution is an infinite stream of namefree terms
   Substitution = Stream NF ∞

   -- For example, the identity substitution replaces the index
   -- at position i with a variable with the same index. If we
   -- apply this substitution to a namefree term, it shouldn't
   -- change anything.

   σ-id : Substitution
   σ-id = map #_ nats     -- nats is the stream  0 ∷ 1 ∷ 2 ∷ ...

   -- And here is an incrementing substitution that adds one to
   -- each index. We'll use this substitution for weakening.
   σ-incr = map (λ i -> # (suc i)) nats

   -- The substitution function in de Bruijn's paper is notated by 
   --
   --     S( ... <Σ₃>, <Σ₂>, <Σ₁>; Ω ) 
   --
   -- where ... <Σ₃>, <Σ₂>, <Σ₁> is the substitution and Ω is
   -- the term.
   --
   -- In Agda, we'll write it as 
   -- 
   --     subst σ M

   mutual 
     {-# TERMINATING #-}
     subst : Substitution -> NF -> NF
     -- (iii)
     subst σ (L · M) = subst σ L · subst σ M
     -- (iv)
     subst σ (# x)   = lookup x σ 
     -- (v)
     subst σ (ƛ N)   = ƛ subst (exts σ) N

     exts : Substitution -> Substitution
     exts σ = (# 0) ∷ λ where .force -> map (subst σ-incr) σ

     {- In the last case, if Σ is (... <Σ₃>, <Σ₂>, <Σ₁>) then de
     Bruijn says the result is

         S ( ... <Λ₃>, <Λ₂>, <Λ₁>, 1 ; N )

     where each <Λᵢ> is "obtained by adding 1 to every integer
     in <Σᵢ> that refers to a free variable". In
     this case, we are applying the substitution underneath a 
     lambda expression, so there is one more bound variable
     in scope. That new bound variable should be left alone, 
     and all of the existing substitutions must be shifted
     over and the free variables in their terms must be 
     incremented.

     With our version (calculated by `exts`), we start the new
     substitution with 0 (identity sub for the bound variable)
     and then weaken all of the terms that appear in the
     original substitution.  To do so we use the stream's `map`
     operation with our weakening substitution above.
     -}


   -- Test for substitution: weaken the free variables in 
   -- this term.
   test = subst σ-incr (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
     -- C-c C-n can normalize this to
     -- ƛ # 3 · # 2 · # 0 · (ƛ # 3 · # 1)

   {-

     However, this definition of substs and exts is not
     obviously terminating. To disable Agda's termination
     checker for this definition we label it as TERMINATING.

     But, we can revise the definition to satisfy Agda's
     termination checker. The solution is to build up this
     definition in two parts: first *renaming* and then
     substitution.

   -}


module Streams where

   -- A *renaming* is a limited form of substitution that
   -- replaces indices by other indices, not terms. We can
   -- represent it as a stream of natural numbers.
   Renaming = Stream ℕ ∞

   ρ-id : Renaming
   ρ-id = nats

   ρ-incr : Renaming
   ρ-incr = map suc nats

   -- Key point for termination: we can compute the extended
   -- renaming in the lambda-case without a recursive call to
   -- rename.  To add 1 to each index in the renaming, we just
   -- use 'suc'.

   ext : Renaming -> Renaming
   ext ρ = 0 ∷ λ where .force -> map suc ρ

   -- The rename function is a simple structural recursion
   rename : Renaming -> NF -> NF
   rename ρ (# x)    = # (lookup x ρ)
   rename ρ (ƛ M)    = ƛ rename (ext ρ) M
   rename ρ (L · M) = rename ρ L · rename ρ M

   -- Some examples (use C-c C-n to normalize them)
   t1 = rename ρ-id (ƛ ( # 1 · # 0))
   t2 = rename ρ-incr (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
      -- ƛ # 3 · # 2 · # 0 · (ƛ # 3 · # 1)

   Substitution = Stream NF ∞

   -- Now to define the extended substitution, we use rename to increment 
   -- all indices in the terms in the substitution.
   exts : Substitution -> Substitution
   exts σ = (# 0) ∷ λ where .force -> map (rename ρ-incr) σ

   -- Substitution is also a simple structural recursion
   subst : Substitution -> NF -> NF
   subst σ (# x) = lookup x σ 
   subst σ (ƛ N) = ƛ subst (exts σ) N
   subst σ (L · M) = subst σ L · subst σ M

   -- We can convert a renaming to a substitution
   r-to-s : Renaming -> Substitution
   r-to-s ρ = map #_ ρ

   t3 = subst (r-to-s ρ-incr) (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
    -- ƛ # 3 · # 2 · # 0 · (ƛ # 3 · # 1)

   -- Single substitution AKA "open": replace index 0 with M, decrement
   -- all other free variables. (Leave bound vars alone.)
   subst-zero : NF -> Substitution
   subst-zero M = M ∷ λ where .force -> (map #_ ρ-id)

   -- MORE test cases
   t4 = subst (subst-zero (ƛ # 0)) (# 0 · # 1)
    -- (ƛ # 0) · # 0
   t5 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1))
    -- ƛ # 0 · (ƛ # 0)
   t6 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1 · # 2))
    -- ƛ # 0 · (ƛ # 0) · # 1
   t7 = subst (subst-zero (ƛ # 0)) (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
    -- ƛ # 1 · (ƛ # 0) · # 0 · (ƛ (ƛ # 0) · # 1)

   -- Example proofs about stream representation of renamings and substitutions
   -- Even though we are representing streams coinductively, these are 
   -- inductive proofs over the index passed to lookup

   lookup-suc : ∀ {k ρ} -> lookup k (map suc ρ) ≡ suc (lookup k ρ)
   lookup-suc {zero}  {a ∷ b} = refl
   lookup-suc {suc k} {a ∷ b} = lookup-suc {k}{b .force}

   -- And the generalized version of the above lemma
   lookup-map-comm : ∀ {A : Set} → {s : Stream A ∞}
                   → (k : ℕ) → (f : A → A)
                   → lookup k (map f s) ≡ f (lookup k s)
   lookup-map-comm {s = hd ∷ _}  zero     _ = refl
   lookup-map-comm {s = _ ∷ tl} (suc k)   f = lookup-map-comm k f

   -- Defined for readability in `lookup-count-≤-suc`, corresponds to
   -- counts generated from repeated mappings of `suc` over `nats`
   count : ℕ → Stream ℕ ∞
   count k = unfold (λ x → suc x , x) k

   -- If all values in a count starting at k are less than i,
   -- then all values in a count starting at suc k are less than
   -- suc i.
   lookup-count-≤-suc : ∀ {i k : ℕ}
                      → (n : ℕ)
                      → lookup n (count k) ≤ i
                        --------------------------------
                      → lookup n (count (suc k)) ≤ suc i
   lookup-count-≤-suc zero    pf = s≤s pf
   lookup-count-≤-suc (suc n) pf = lookup-count-≤-suc n pf

   lookup-≤-suc : ∀ {j : ℕ} {ρ : Stream ℕ ∞}
                → (k : ℕ)
                → lookup k ρ ≤ j
                  ------------------------
                → lookup k (map suc ρ) ≤ suc j
   lookup-≤-suc {ρ = ρ} zero i≤j   with ρ
   ...                                | i ∷ _ = s≤s i≤j
   lookup-≤-suc {ρ = ρ} (suc k) pf with ρ
   ...                                | _ ∷ tl = lookup-≤-suc k pf

   -------------------------------------------------------------------------
   -- We can extend the concept of scope to renamings and substitutions
   -- 
   -- EXERCISE: finish these proofs.
   -------------------------------------------------------------------------

   -- A renaming is scoped by i and j when all indices less than or equal to i
   -- are renamed to values less than or equal to j. 
   ρ-scope : ℕ -> ℕ -> Renaming -> Set
   ρ-scope i j ρ = ∀ {k : ℕ} -> k ≤ i -> (lookup k ρ ≤ j)

   -- Like namefree expressions, renamings can be scoped by multiple pairs of
   -- indices.
   ρ-id-scope : ∀ {i} -> ρ-scope i i ρ-id
   ρ-id-scope {i} z≤n =  z≤n
   ρ-id-scope {suc i} (s≤s {m} pf) with m     | ρ-id-scope {i} pf
   ...                                | zero  | pf′ = s≤s pf′
   ...                                | suc n | pf′ = lookup-count-≤-suc n pf′

   ρ-incr-scope : ∀ {j : ℕ} → ρ-scope j (suc j) ρ-incr
   ρ-incr-scope {zero} {zero} _ = s≤s z≤n
   ρ-incr-scope {suc j} {k} le
     rewrite lookup-map-comm {s = nats} k suc
     with le
   ...  | z≤n         = s≤s z≤n
   ...  | s≤s {k} k≤j
     with ρ-incr-scope {j} k≤j
   ...  | ih rewrite lookup-map-comm {s = nats} k suc
     with ih
   ...  | s≤s ih = s≤s (lookup-count-≤-suc k ih)

   -- A substitution is scoped by i and j when all indices less than or equal to i
   -- map to namefree expressions scoped by j. Like renamings,
   -- substitutions can be scoped by multiple pairs of indices.
   σ-scope : ℕ -> ℕ -> Substitution -> Set
   σ-scope i j σ = ∀ {k : ℕ} -> k ≤ i -> scope j (lookup k σ)

   -- Now we show that all of our operations on renamings and substitutions
   -- preserve scoping
   ext-scope : ∀ {i j : ℕ} {ρ : Renaming} -> (ρ-scope i j ρ) 
     -> (ρ-scope (suc i) (suc j) (ext ρ)) 
   ext-scope pf        {zero} =  λ _ -> z≤n
   ext-scope {i}{j} pf {suc k} (s≤s k≤i) with pf k≤i
   ...                                      | pf′ = lookup-≤-suc k pf′

   rename-scope : ∀ {i j : ℕ}{ρ : Renaming}{M : NF} -> (ρ-scope i j ρ) 
     -> scope i M -> scope j (rename ρ M)
   rename-scope pf (d-# x) = d-# (pf x)
   rename-scope pf (d-· dm dm₁) = d-· (rename-scope pf dm) (rename-scope pf dm₁)
   rename-scope {ρ} pf (d-ƛ dm) = d-ƛ (rename-scope (ext-scope pf) dm)

   exts-scope : ∀ {i j : ℕ} {σ : Substitution} -> (σ-scope i j σ) ->
      (σ-scope (suc i) (suc j) (exts σ))
   exts-scope pf z≤n = d-# z≤n
   exts-scope {σ = σ} pf {suc k} (s≤s k≤i)
     with lookup-map-comm {s = σ} k (rename ρ-incr) | pf k≤i
   ...  | lookup-map-comm-≡                         | pf′
     rewrite lookup-map-comm-≡ = rename-scope ρ-incr-scope pf′

   subst-scope : ∀ {i j : ℕ}{σ : Substitution}{M : NF} -> (σ-scope i j σ)
     -> scope i M -> scope j (subst σ M)
   subst-scope pf (d-# x) = pf x
   subst-scope pf (d-ƛ f) =  d-ƛ (subst-scope (exts-scope pf) f)
   subst-scope pf (d-· f f₁) =  d-· (subst-scope pf f) (subst-scope pf f₁)


   
------------------------------------------------------------------------
-- Substitution represented as functions
----------------------------------------------------------------------------

{- Instead of using infinite streams of numbers/terms we can also 
   represent multi-renamings/substitutions using functions. 

   EXERCISE: try to complete ext and exts with this version.

-}

module Functions where

  Renaming     = ℕ -> ℕ    -- lookup the renaming at an index
  Substitution = ℕ -> NF   -- lookup a substitution at an index

  ρ-id : Renaming 
  ρ-id n = n

  ρ-incr : Renaming 
  ρ-incr = suc

  -- ext : Renaming -> Renaming
  -- ext ρ = 0 ∷ λ where .force -> map suc ρ

  ext : Renaming -> Renaming
  ext ρ zero =  zero             
  ext ρ (suc x) = suc (ρ x)

  -- The rename function is the same structural recursion
  rename : Renaming -> NF -> NF
  rename ρ (# x)    = # (ρ x)
  rename ρ (ƛ N)    = ƛ rename (ext ρ) N
  rename ρ (L · M) = rename ρ L · rename ρ M

  -- Some examples (use C-c C-n to normalize them)
  t1 = rename ρ-id (ƛ ( # 1 · # 0))
       -- 
  t2 = rename ρ-incr (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
       -- ƛ # 3 · # 2 · # 0 · (ƛ # 3 · # 1)
  
  --  exts : Substitution -> Substitution
  --  exts σ = (# 0) ∷ λ where .force -> map (rename ρ-incr) σ
  exts : Substitution -> Substitution
  exts σ zero = # 0     -- at index 0 return # 0
  exts σ (suc n) = rename ρ-incr (σ n)  -- everywhere else, increment 
  
   -- Substitution is also a simple structural recursion
  subst : Substitution -> NF -> NF
  subst σ (# x) = σ x 
  subst σ (ƛ N) = ƛ subst (exts σ) N
  subst σ (L · M) = (subst σ L) · (subst σ M)

  -- ( M :: 0 :: 1 :: 2 ...)
  subst-zero : NF -> Substitution
  subst-zero M zero = M
  subst-zero M (suc n) = # n

  t4 = subst (subst-zero (ƛ # 0)) (# 0 · # 1)
   -- (ƛ # 0) · # 0
  t5 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1))
   -- ƛ # 0 · (ƛ # 0)
  t6 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1 · # 2))
   -- ƛ # 0 · (ƛ # 0) · # 1
  t7 = subst (subst-zero (ƛ # 0)) (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
   -- ƛ # 1 · (ƛ # 0) · # 0 · (ƛ (ƛ # 0) · # 1)


  ------------------------------------------------------------
  -- EXERCISE: finish this proof. You'll need to use some properties
  -- of the natural number ≤ relation from the Agda standard library. 
  -- Check out the two constructors, z≤n and s≤s, (defined in 
  -- https://agda.github.io/agda-stdlib/Data.Nat.Base.html#1535) and 
  -- the property ≤-pred (defined in 
  -- https://agda.github.io/agda-stdlib/Data.Nat.Properties.html#7536)
  ------------------------------------------------------------


  -- A renaming is scoped by i and j when all indices less than or equal to i
  -- are renamed to values less than or equal to j. 
  ρ-scope : ℕ -> ℕ -> Renaming -> Set
  ρ-scope i j ρ = ∀ {k : ℕ} -> k ≤ i -> (ρ k ≤ j)

  -- Like namefree expressions, renamings can be scoped by multiple pairs of
  -- indices.
  ρ-id-scope : ∀ {i} -> ρ-scope i i ρ-id
  ρ-id-scope {i} = λ p -> p 

  -- A substitution is scoped by i and j when all indices less than or equal to i
  -- map to namefree expressions scoped by j. Like renamings,
  -- substitutions can be scoped by multiple pairs of indices.
  σ-scope : ℕ -> ℕ -> Substitution -> Set
  σ-scope i j σ = ∀ {k : ℕ} -> k ≤ i -> scope j (σ k)

  -- Now we show that all of our operations on renamings and substitutions
  -- preserve scoping
  ext-scope : ∀ {i j : ℕ} {ρ : Renaming} -> (ρ-scope i j ρ) 
    -> (ρ-scope (suc i) (suc j) (ext ρ)) 
  ext-scope pf z≤n =  z≤n
  ext-scope pf (s≤s x) = s≤s (pf x)

  rename-scope : ∀ {i j : ℕ}{ρ : Renaming}{M : NF} -> (ρ-scope i j ρ) 
    -> scope i M -> scope j (rename ρ M)
  rename-scope pf (d-# x) = d-# (pf x)
  rename-scope pf (d-· dm dm₁) = d-· (rename-scope pf dm) (rename-scope pf dm₁)
  rename-scope {ρ} pf (d-ƛ dm) = d-ƛ (rename-scope (ext-scope pf) dm)

  exts-scope : ∀ {i j : ℕ} {σ : Substitution} -> (σ-scope i j σ) ->
     (σ-scope (suc i) (suc j) (exts σ)) 
  exts-scope pf z≤n = d-# z≤n
  exts-scope pf (s≤s x) = rename-scope s≤s ((pf x))

  subst-scope : ∀ {i j : ℕ}{σ : Substitution}{M : NF} -> (σ-scope i j σ) 
    -> scope i M -> scope j (subst σ M)
  subst-scope pf (d-# x) = pf x
  subst-scope pf (d-ƛ f) =  d-ƛ (subst-scope (exts-scope pf) f)
  subst-scope pf (d-· f f₁) =  d-· (subst-scope pf f) (subst-scope pf f₁)

  subst-zero-scope : ∀ {i : ℕ}{M : NF} -> scope i M -> σ-scope (suc i) i (subst-zero M)
  subst-zero-scope d {zero} pf =  d
  subst-zero-scope d {suc k} pf = d-# (≤-pred pf)

-- A third implementation of substitution is by "defunctionalizing" the functions
-- shown above. The actual data structures that we use can vary, but the result is 
-- an implementation similar to that of calculi of explicit substitutions

module Explicit where

  data Renaming : Set where
    ρ-incr : Renaming 
    ρ-ext  : Renaming -> Renaming 

  data Substitution : Set where
    σ-incr : Substitution
    σ-exts : Substitution -> Substitution
    subst-zero : NF -> Substitution

  ρ-apply : Renaming -> ℕ -> ℕ
  ρ-apply ρ-incr x = (suc x)
  ρ-apply (ρ-ext ρ) zero = zero
  ρ-apply (ρ-ext ρ) (suc x) = suc (ρ-apply ρ x)

  -- The rename function is the same structural recursion
  rename : Renaming -> NF -> NF
  rename ρ (# x)    = # (ρ-apply ρ x)
  rename ρ (ƛ N)    = ƛ rename (ρ-ext ρ) N
  rename ρ (L · M) = rename ρ L · rename ρ M

  -- Some examples (use C-c C-n to normalize them)
  t2 = rename ρ-incr (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
       -- ƛ # 3 · # 2 · # 0 · (ƛ # 3 · # 1)
  
  σ-apply : Substitution -> ℕ -> NF
  σ-apply σ-incr x = # (suc x)
  σ-apply (σ-exts σ) zero = # 0
  σ-apply (σ-exts σ) (suc x) = rename ρ-incr (σ-apply σ x) 
  σ-apply (subst-zero M) zero = M
  σ-apply (subst-zero x₁) (suc x) = # x
  
   -- Substitution is also a simple structural recursion
  subst : Substitution -> NF -> NF
  subst σ (# x) = σ-apply σ x 
  subst σ (ƛ N) = ƛ subst (σ-exts σ) N
  subst σ (L · M) = (subst σ L) · (subst σ M)

  t4 = subst (subst-zero (ƛ # 0)) (# 0 · # 1)
   -- (ƛ # 0) · # 0
  t5 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1))
   -- ƛ # 0 · (ƛ # 0)
  t6 = subst (subst-zero (ƛ # 0)) (ƛ (# 0 · # 1 · # 2))
   -- ƛ # 0 · (ƛ # 0) · # 1
  t7 = subst (subst-zero (ƛ # 0)) (ƛ ( # 2 · # 1 · # 0 · (ƛ # 2 · # 1)))
   -- ƛ # 1 · (ƛ # 0) · # 0 · (ƛ (ƛ # 0) · # 1)


  -- A renaming is scoped by i and j when all indices less than or equal to i
  -- are renamed to values less than or equal to j. 
  data ρ-scope : ℕ -> ℕ -> Renaming -> Set where
    ρ-incr-scope : ∀ {i} -> ρ-scope i (suc i) ρ-incr
    ext-scope  : ∀ {i j ρ} -> ρ-scope i j ρ -> ρ-scope (suc i) (suc j) (ρ-ext ρ)

  -- now we prove that our proof witnesses imply the ρ-scope property above
  ρ-apply-scope : ∀ {i j ρ} -> ρ-scope i j ρ 
      -> ∀ {k : ℕ} -> k ≤ i -> (ρ-apply ρ k ≤ j)
  ρ-apply-scope ρ-incr-scope  x =  s≤s x
  ρ-apply-scope (ext-scope s) z≤n =  z≤n
  ρ-apply-scope (ext-scope pf) (s≤s x) = s≤s (ρ-apply-scope pf x)

  rename-scope : ∀ {i j : ℕ}{ρ : Renaming}{M : NF} -> (ρ-scope i j ρ) 
    -> scope i M -> scope j (rename ρ M)
  rename-scope pf (d-# x)      = d-# (ρ-apply-scope pf x)
  rename-scope pf (d-· dm dm₁) = d-· (rename-scope pf dm) (rename-scope pf dm₁)
  rename-scope {ρ} pf (d-ƛ dm) = d-ƛ (rename-scope (ext-scope pf) dm)

  -- A substitution is scoped by i and j when all indices less than or equal to i
  -- map to namefree expressions scoped by j. Like renamings,
  -- substitutions can be scoped by multiple pairs of indices.

  data σ-scope : ℕ -> ℕ -> Substitution -> Set where
    σ-incr-scope : ∀ {i}     -> σ-scope i (suc i) σ-incr
    exts-scope   : ∀ {i j σ} -> σ-scope i j σ -> σ-scope (suc i) (suc j) (σ-exts σ)
    subst-zero-scope : ∀ {i M}   -> scope i M -> σ-scope (suc i) i (subst-zero M)

  σ-apply-scope : ∀ {i j σ} -> σ-scope i j σ 
      -> ∀ {k : ℕ} -> k ≤ i -> scope j (σ-apply σ k)
  σ-apply-scope σ-incr-scope x = d-# (s≤s x)
  σ-apply-scope (exts-scope s) z≤n = d-# z≤n
  σ-apply-scope (exts-scope s) (s≤s lt) = rename-scope ρ-incr-scope ( (σ-apply-scope s lt))
  σ-apply-scope (subst-zero-scope x) z≤n = x
  σ-apply-scope (subst-zero-scope x) (s≤s lt) = d-# lt

  subst-scope : ∀ {i j : ℕ}{σ : Substitution}{M : NF} -> (σ-scope i j σ) 
    -> scope i M -> scope j (subst σ M)
  subst-scope pf (d-# x) = σ-apply-scope pf x
  subst-scope pf (d-ƛ f) =  d-ƛ (subst-scope (exts-scope pf) f)
  subst-scope pf (d-· f f₁) =  d-· (subst-scope pf f) (subst-scope pf f₁)


open Explicit

------------------------------------------------------------------------
-- Beta-reduction
------------------------------------------------------------------------

-- Now use the above to define full β-reduction

-- An operation like "open"
_[_] : NF -> NF -> NF
_[_] N M = subst (subst-zero M) N


-- Inductive definition of one-step β-reduction
-- Uses the notation for the β-reduction rule. Other 
-- rules are the compatible closure.
infix 2 _—→_

data _—→_ : NF -> NF → Set where

  β : ∀ {N} {M}
      ---------------------------------
    → (ƛ N) · M —→ N [ M ]

  ζ : ∀ {N N′}
    → N —→ N′
      -----------
    → ƛ N —→ ƛ N′


  ξ₁ : ∀ {L L′ M}
    → L —→ L′
      ----------------
    → L · M —→ L′ · M

  ξ₂ : ∀ {L M M′}
    → M —→ M′
      ----------------
    → L · M —→ L · M′

------------------------------------------------------------
-- Now, let's prove that β-reduction is scope-preserving

open-scope : {i : ℕ}{M N : NF} -> scope (suc i) M -> scope i N -> scope i (M [ N ])
open-scope dm dn = subst-scope (subst-zero-scope dn) dm

-- Finally, we have the main proof that β-reduction is scope preserving

scope-preservation : {i : ℕ}{M N : NF} -> M —→ N -> scope i M -> scope i N
scope-preservation β scope = {!!}
scope-preservation (ζ red) scope = {!!}
scope-preservation (ξ₁ red) scope = {!!}
scope-preservation (ξ₂ red) scope = {!!}

-- NOTE: This is a lot of work to prove scope verification even though the argument 
-- is rather straightforward and determined by the structure of namefree terms. 
-- For that reason it is more common in Agda to represent namefree terms with 
-- intrinsic scopes, and define operations like subst simultaneously with its
-- proof of scope preservation.
