{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{- | Value-related functionality. In order to keep the interface efficient and
 safe at the same time, there is a type-level distinction between 'PValue's
 that are guaranteed to be properly normalized and those that provide no
 such guarantee.

 Also for efficiency reasons, the Ada-specific functions assume that there
 can be only one token name for the Ada currency symbol, and they don't check
 whether it matches 'Plutus.adaToken'.
-}
module Plutarch.Api.V1.Value (
  PValue (PValue),
  PCurrencySymbol (PCurrencySymbol),
  PTokenName (PTokenName),
  KeyGuarantees (Unsorted, Sorted),
  AmountGuarantees (NoGuarantees, NonZero, Positive),

  -- * Conversions and assertions
  passertSorted,
  passertPositive,
  pforgetPositive,
  pforgetSorted,
  pnormalize,

  -- * Creation
  psingleton,
  psingletonData,
  pconstantSingleton,
  pconstantPositiveSingleton,

  -- * Combining values
  punionWith,
  punionWithData,

  -- * Partial ordering operations
  pcheckBinRel,

  -- * Lookups
  pvalueOf,
  plovelaceValueOf,

  -- * Ada-specific
  padaSymbol,
  padaSymbolData,
  padaToken,
  padaTokenData,
  pisAdaOnlyValue,
  padaOnlyValue,
  pnoAdaValue,
) where

import qualified PlutusLedgerApi.V1 as Plutus

import Plutarch.Api.V1.AssocMap (KeyGuarantees (Sorted, Unsorted), PMap)
import qualified Plutarch.Api.V1.AssocMap as AssocMap
import Plutarch.Bool (pand', pif')
import Plutarch.Lift (
  DerivePConstantViaBuiltin (DerivePConstantViaBuiltin),
  DerivePConstantViaNewtype (DerivePConstantViaNewtype),
  PConstantDecl,
  PLifted,
  PUnsafeLiftDecl,
 )
import qualified Plutarch.List as List
import Plutarch.Unsafe (punsafeCoerce, punsafeDowncast)
import qualified PlutusTx.Monoid as PlutusTx
import qualified PlutusTx.Semigroup as PlutusTx

import Plutarch.Prelude hiding (psingleton)

newtype PTokenName (s :: S) = PTokenName (Term s PByteString)
  deriving stock (Generic)
  deriving anyclass (PlutusType, PIsData, PEq, POrd)
instance DerivePlutusType PTokenName where type DPTStrat _ = PlutusTypeNewtype

instance PUnsafeLiftDecl PTokenName where type PLifted PTokenName = Plutus.TokenName
deriving via
  (DerivePConstantViaBuiltin Plutus.TokenName PTokenName PByteString)
  instance
    PConstantDecl Plutus.TokenName

newtype PCurrencySymbol (s :: S) = PCurrencySymbol (Term s PByteString)
  deriving stock (Generic)
  deriving anyclass (PlutusType, PIsData, PEq, POrd)
instance DerivePlutusType PCurrencySymbol where type DPTStrat _ = PlutusTypeNewtype

instance PUnsafeLiftDecl PCurrencySymbol where type PLifted PCurrencySymbol = Plutus.CurrencySymbol
deriving via
  (DerivePConstantViaBuiltin Plutus.CurrencySymbol PCurrencySymbol PByteString)
  instance
    PConstantDecl Plutus.CurrencySymbol

data AmountGuarantees = NoGuarantees | NonZero | Positive

type role PValue nominal nominal nominal
newtype PValue (keys :: KeyGuarantees) (amounts :: AmountGuarantees) (s :: S)
  = PValue (Term s (PMap keys PCurrencySymbol (PMap keys PTokenName PInteger)))
  deriving stock (Generic)
  deriving anyclass (PlutusType, PIsData)
instance DerivePlutusType (PValue keys amounts) where type DPTStrat _ = PlutusTypeNewtype

instance PUnsafeLiftDecl (PValue 'Unsorted 'NonZero) where
  type PLifted (PValue 'Unsorted 'NonZero) = Plutus.Value
deriving via
  ( DerivePConstantViaNewtype
      Plutus.Value
      (PValue 'Unsorted 'NonZero)
      (PMap 'Unsorted PCurrencySymbol (PMap 'Unsorted PTokenName PInteger))
  )
  instance
    PConstantDecl Plutus.Value

instance PEq (PValue 'Sorted 'Positive) where
  a #== b = pto a #== pto b

instance PEq (PValue 'Sorted 'NonZero) where
  a #== b = pto a #== pto b

{- | Partial ordering implementation for sorted 'PValue' with 'Positive' amounts.

Use 'pcheckBinRel' if 'AmountGuarantees' is 'NoGuarantees'.
-}
instance POrd (PValue 'Sorted 'Positive) where
  a #< b = pforgetPositive @_ @'Sorted @'NonZero a #< pforgetPositive b
  a #<= b = pforgetPositive @_ @'Sorted @'NonZero a #<= pforgetPositive b

{- | Partial ordering implementation for sorted 'PValue' with 'NonZero' amounts.

Use 'pcheckBinRel' if 'AmountGuarantees' is 'NoGuarantees'.
-}
instance POrd (PValue 'Sorted 'NonZero) where
  a #< b = f # a # b
    where
      f = phoistAcyclic $ pcheckBinRel #$ phoistAcyclic $ plam (\x y -> pfromData x #< pfromData y)
  a #<= b = f # a # b
    where
      f = phoistAcyclic $ pcheckBinRel #$ phoistAcyclic $ plam (\x y -> pfromData x #<= pfromData y)

instance PEq (PValue 'Sorted 'NoGuarantees) where
  a #== b = AssocMap.pall # (AssocMap.pall # plam (#== 0)) # pto (punionWith # plam (-) # a # b)

instance Semigroup (Term s (PValue 'Sorted 'Positive)) where
  a <> b = punsafeDowncast (pto $ punionWith # plam (+) # a # b)

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'Positive)) where
  a <> b = punsafeDowncast (pto $ punionWith # plam (+) # a # b)

instance Semigroup (Term s (PValue 'Sorted 'NonZero)) where
  a <> b = pnormalize #$ punionWith # plam (+) # a # b

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'NonZero)) where
  a <> b = pnormalize #$ punionWith # plam (+) # a # b

instance Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) where
  a <> b = punionWith # plam (+) # a # b

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) where
  a <> b = punionWith # plam (+) # a # b

instance
  Semigroup (Term s (PValue 'Sorted normalization)) =>
  Monoid (Term s (PValue 'Sorted normalization))
  where
  mempty = pcon (PValue AssocMap.pempty)

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted normalization)) =>
  PlutusTx.Monoid (Term s (PValue 'Sorted normalization))
  where
  mempty = pcon (PValue AssocMap.pempty)

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) =>
  PlutusTx.Group (Term s (PValue 'Sorted 'NoGuarantees))
  where
  inv a = pmapAmounts # plam negate # a

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted 'NonZero)) =>
  PlutusTx.Group (Term s (PValue 'Sorted 'NonZero))
  where
  inv a = punsafeCoerce $ PlutusTx.inv (punsafeCoerce a :: Term s (PValue 'Sorted 'NoGuarantees))

-- | Check whether a binary relation holds over 2 sorted 'PValue's.
pcheckBinRel ::
  Term
    s
    ( (PAsData PInteger :--> PAsData PInteger :--> PBool)
        :--> PValue 'Sorted any0
        :--> PValue 'Sorted any1
        :--> PBool
    )
pcheckBinRel = phoistAcyclic $
  plam $ \f m1 m2 ->
    let inner = pfix #$ plam $ \self l1 l2 ->
          pelimList
            ( \x xs ->
                pelimList
                  ( \y ys -> unTermCont $ do
                      v1dat <- tcont . plet $ psndBuiltin # x
                      v2dat <- tcont . plet $ psndBuiltin # y
                      k1 <- tcont . plet $ pfromData $ pfstBuiltin # x
                      k2 <- tcont . plet $ pfromData $ pfstBuiltin # y
                      pure $
                        pif
                          (k1 #< k2)
                          (pinnerCheckBinRel # f # pfromData v1dat # AssocMap.pempty #&& self # xs # l2)
                          $ pif
                            (k1 #== k2)
                            ( pinnerCheckBinRel # f # pfromData v1dat # pfromData v2dat #&& self
                                # xs
                                # ys
                            )
                            $ pinnerCheckBinRel # f # AssocMap.pempty # pfromData v2dat #&& self
                              # l1
                              # ys
                  )
                  ( pinnerCheckBinRel # f # pfromData (psndBuiltin # x) # AssocMap.pempty
                      #&& pall
                        # plam
                          ( \p ->
                              let v1dat = psndBuiltin # p
                               in pinnerCheckBinRel # f # pfromData v1dat # AssocMap.pempty
                          )
                        # xs
                  )
                  l2
            )
            ( pall
                # plam
                  ( \p ->
                      let v1dat = psndBuiltin # p
                       in pinnerCheckBinRel # f # AssocMap.pempty # pfromData v1dat
                  )
                # l2
            )
            l1
     in inner # pto (pto $ pto m1) # pto (pto $ pto m2)
  where
    dat0 :: ClosedTerm (PAsData PInteger)
    dat0 = pconstantData 0
    pinnerCheckBinRel ::
      ClosedTerm
        ( (PAsData PInteger :--> PAsData PInteger :--> PBool)
            :--> ( PMap 'Sorted PTokenName PInteger
                    :--> (PMap 'Sorted PTokenName PInteger :--> PBool)
                 )
        )
    pinnerCheckBinRel = phoistAcyclic $
      plam $ \f m1 m2 ->
        let inner = pfix #$ plam $ \self l1 l2 ->
              pelimList
                ( \x xs ->
                    let k1dat = pfstBuiltin # x
                        v1dat = psndBuiltin # x
                     in pelimList
                          ( \y ys ->
                              let k2dat = pfstBuiltin # y
                                  v2dat = psndBuiltin # y
                               in unTermCont $ do
                                    k1 <- tcont . plet $ pfromData k1dat
                                    k2 <- tcont . plet $ pfromData k2dat
                                    pure $
                                      pif
                                        (k1 #< k2)
                                        (f # v1dat # dat0 #&& self # xs # l2)
                                        $ pif
                                          (k1 #== k2)
                                          (f # v1dat # v2dat #&& self # xs # ys)
                                          $ f # dat0 # v2dat #&& self # l1 # ys
                          )
                          ( f # v1dat # dat0
                              #&& pall
                                # plam (\p -> f # (psndBuiltin # p) # dat0)
                                # xs
                          )
                          l2
                )
                (pall # plam (\p -> f # dat0 #$ psndBuiltin # p) # l2)
                l1
         in inner # pto m1 # pto m2

-- | Construct a constant singleton 'PValue' containing only the given quantity of the given currency.
pconstantSingleton ::
  ClosedTerm PCurrencySymbol ->
  ClosedTerm PTokenName ->
  ClosedTerm PInteger ->
  ClosedTerm (PValue 'Sorted 'NonZero)
pconstantSingleton symbol token amount
  | plift amount == 0 = mempty
  | otherwise = punsafeDowncast (AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

-- | Construct a constant singleton 'PValue' containing only the given positive quantity of the given currency.
pconstantPositiveSingleton ::
  ClosedTerm PCurrencySymbol ->
  ClosedTerm PTokenName ->
  ClosedTerm PInteger ->
  ClosedTerm (PValue 'Sorted 'Positive)
pconstantPositiveSingleton symbol token amount
  | plift amount == 0 = mempty
  | plift amount < 0 = error "Negative amount"
  | otherwise = punsafeDowncast (AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

-- | Construct a singleton 'PValue' containing only the given quantity of the given currency.
psingleton ::
  Term
    s
    (PCurrencySymbol :--> PTokenName :--> PInteger :--> PValue 'Sorted 'NonZero)
psingleton = phoistAcyclic $
  plam $ \symbol token amount ->
    pif
      (amount #== 0)
      mempty
      (punsafeDowncast $ AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

{- | Construct a singleton 'PValue' containing only the given quantity of the
 given currency, taking data-encoded parameters.
-}
psingletonData ::
  Term
    s
    ( PAsData PCurrencySymbol :--> PAsData PTokenName :--> PAsData PInteger
        :--> PValue 'Sorted 'NonZero
    )
psingletonData = phoistAcyclic $
  plam $ \symbol token amount ->
    pif
      (amount #== zeroData)
      mempty
      ( punsafeDowncast
          ( AssocMap.psingletonData # symbol
              #$ pdata
              $ AssocMap.psingletonData # token # amount
          )
      )

-- | Get the quantity of the given currency in the 'PValue'.
pvalueOf :: Term s (PValue anyKey anyAmount :--> PCurrencySymbol :--> PTokenName :--> PInteger)
pvalueOf = phoistAcyclic $
  plam $ \value symbol token ->
    AssocMap.pfoldAt
      # symbol
      # 0
      # plam (\map -> AssocMap.pfoldAt # token # 0 # plam pfromData # pfromData map)
      # pto value

-- | The 'PCurrencySymbol' of the Ada currency.
padaSymbol :: Term s PCurrencySymbol
padaSymbol = pconstant Plutus.adaSymbol

-- | Data-encoded 'PCurrencySymbol' of the Ada currency.
padaSymbolData :: Term s (PAsData PCurrencySymbol)
padaSymbolData = pdata padaSymbol

-- | The 'PTokenName' of the Ada currency.
padaToken :: Term s PTokenName
padaToken = pconstant Plutus.adaToken

-- | Data-encoded 'PTokenName' of the Ada currency.
padaTokenData :: Term s (PAsData PTokenName)
padaTokenData = pdata padaToken

-- | Test if the value contains nothing but Ada
pisAdaOnlyValue :: Term s (PValue 'Sorted 'Positive :--> PBool)
pisAdaOnlyValue = phoistAcyclic $
  plam $ \value ->
    pmatch (pto $ pto value) $ \case
      PNil -> pcon PTrue
      PCons x xs -> pand' # (pnull # xs) # (pfstBuiltin # x #== padaSymbolData)

-- | Value without any non-Ada
padaOnlyValue :: Term s (PValue 'Sorted v :--> PValue 'Sorted v)
padaOnlyValue = phoistAcyclic $
  plam $ \value ->
    pmatch (pto $ pto value) $ \case
      PNil -> value
      PCons x _ ->
        pif' # (pfstBuiltin # x #== padaSymbolData)
          # pcon (PValue $ pcon $ AssocMap.PMap $ List.psingleton # x)
          # pcon (PValue AssocMap.pempty)

-- | Value without any Ada
pnoAdaValue :: Term s (PValue 'Sorted v :--> PValue 'Sorted v)
pnoAdaValue = phoistAcyclic $
  plam $ \value ->
    pmatch (pto $ pto value) $ \case
      PNil -> value
      PCons x xs -> pif' # (pfstBuiltin # x #== padaSymbolData) # pcon (PValue $ pcon $ AssocMap.PMap xs) # value

-- | The amount of Lovelace in value
plovelaceValueOf :: Term s (PValue 'Sorted v :--> PInteger)
plovelaceValueOf = phoistAcyclic $
  plam $ \value ->
    pmatch (pto $ pto value) $ \case
      PNil -> 0
      PCons x _ ->
        pif' # (pfstBuiltin # x #== padaSymbolData)
          # pfromData (psndBuiltin #$ phead #$ pto $ pfromData $ psndBuiltin # x)
          # 0

{- | Combine two 'PValue's applying the given function to any pair of
 quantities with the same asset class. Note that the result is _not_
 'normalize'd and may contain zero quantities.
-}
punionWith ::
  Term
    s
    ( (PInteger :--> PInteger :--> PInteger) :--> PValue 'Sorted any0 :--> PValue 'Sorted any1
        :--> PValue 'Sorted 'NoGuarantees
    )
punionWith = phoistAcyclic $
  plam $ \combine x y ->
    pcon . PValue $
      AssocMap.punionWith
        # plam (\x y -> AssocMap.punionWith # combine # x # y)
        # pto x
        # pto y

{- | Combine two 'PValue's applying the given function to any pair of
 data-encoded quantities with the same asset class. Note that the result is
 _not_ 'normalize'd and may contain zero quantities.
-}
punionWithData ::
  Term
    s
    ( (PAsData PInteger :--> PAsData PInteger :--> PAsData PInteger)
        :--> PValue 'Sorted any0
        :--> PValue 'Sorted any1
        :--> PValue 'Sorted 'NoGuarantees
    )
punionWithData = phoistAcyclic $
  plam $ \combine x y ->
    pcon . PValue $
      AssocMap.punionWith
        # plam (\x y -> AssocMap.punionWithData # combine # x # y)
        # pto x
        # pto y

-- | Normalize the argument to contain no zero quantity nor empty token map.
pnormalize :: Term s (PValue 'Sorted any :--> PValue 'Sorted 'NonZero)
pnormalize = phoistAcyclic $
  plam $ \value ->
    pcon . PValue $
      AssocMap.pmapMaybe # plam normalizeTokenMap # pto value
  where
    normalizeTokenMap tokenMap =
      plet (AssocMap.pmapMaybeData # plam nonZero # tokenMap) $ \normalMap ->
        pif
          (AssocMap.pnull # normalMap)
          (pcon PNothing)
          (pcon $ PJust normalMap)
    nonZero intData =
      pif (intData #== zeroData) (pcon PNothing) (pcon $ PJust intData)

-- | Assert the value is properly sorted and normalized.
passertSorted :: forall anyKey anyAmount s. Term s (PValue anyKey anyAmount :--> PValue 'Sorted 'NonZero)
passertSorted = phoistAcyclic $
  plam $ \value ->
    pif
      ( AssocMap.pany
          # plam (
                \submap ->
                  AssocMap.pnull # (AssocMap.passertSorted # submap)
                    #|| AssocMap.pany # plam (#== 0) # submap
            )
          # pto value
      )
      (ptraceError "Abnormal Value")
      (let valueMap :: Term _ (PMap anyKey PCurrencySymbol (PMap 'Sorted PTokenName PInteger))
            = punsafeCoerce $ pto value
      in pcon $ PValue $ AssocMap.passertSorted # valueMap)

-- | Assert all amounts in the value are positive.
passertPositive :: Term s (PValue 'Sorted 'NonZero :--> PValue 'Sorted 'Positive)
passertPositive = phoistAcyclic $
  plam $ \value ->
    pif
      ( AssocMap.pall
          # plam (\submap -> AssocMap.pall # plam (0 #<) # submap)
          # pto value
      )
      (punsafeDowncast $ pto value)
      (ptraceError "Negative amount in Value")

-- | Forget the knowledge of value's positivity.
pforgetPositive :: Term s (PValue 'Sorted 'Positive) -> Term s (PValue k a)
pforgetPositive = punsafeCoerce

-- | Forget the knowledge of all value's guarantees.
pforgetSorted :: Term s (PValue 'Sorted a) -> Term s (PValue k b)
pforgetSorted = punsafeCoerce

zeroData :: ClosedTerm (PAsData PInteger)
zeroData = pdata 0

-- | Applies a function to every amount in the map.
pmapAmounts :: Term s ((PInteger :--> PInteger) :--> PValue k a :--> PValue k 'NoGuarantees)
pmapAmounts = phoistAcyclic $
  plam $ \f v -> pcon $ PValue $ AssocMap.pmap # plam (AssocMap.pmap # f #) # pto v
