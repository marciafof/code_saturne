!-------------------------------------------------------------------------------

!     This file is part of the Code_Saturne Kernel, element of the
!     Code_Saturne CFD tool.

!     Copyright (C) 1998-2009 EDF S.A., France

!     contact: saturne-support@edf.fr

!     The Code_Saturne Kernel is free software; you can redistribute it
!     and/or modify it under the terms of the GNU General Public License
!     as published by the Free Software Foundation; either version 2 of
!     the License, or (at your option) any later version.

!     The Code_Saturne Kernel is distributed in the hope that it will be
!     useful, but WITHOUT ANY WARRANTY; without even the implied warranty
!     of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!     GNU General Public License for more details.

!     You should have received a copy of the GNU General Public License
!     along with the Code_Saturne Kernel; if not, write to the
!     Free Software Foundation, Inc.,
!     51 Franklin St, Fifth Floor,
!     Boston, MA  02110-1301  USA

!-------------------------------------------------------------------------------

subroutine condli &
!================

 ( idbia0 , idbra0 ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   isvhb  , isvtb  ,                                              &
   icodcl , isostd ,                                              &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb , rcodcl , &
   coefa  , coefb  , uetbor , visvdr , hbord  , thbord , frcxt  , &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   coefu  , rijipb ,                                              &
   ra     )

!===============================================================================
! FONCTION :
! --------

! TRADUCTION DES CONDITIONS AUX LIMITES FOURNIES PAR USCLIM.F
! SOUS UNE FORME "SIMPLEMENT" ADMISSIBLE PAR LE SOLVEUR

! CETTE TRADUCTION SE PRESENTE SOUS LA FORME D'UNE VALEUR PFAC DE
! LA VARIABLE P CONSIDEREE A LA FACETTE :
!        PFAC = COEFA +COEFB.P(I)
! P(I) : VALEUR DE LA VARIABLE DANS LA CELLULE FLUIDE ADJACENTE

! ATTENTION : SI ON CONSIDERE L'INCREMENT DE LA VARIABLE, LA C.L SE
! REDUIT A : d(PFAC) = COEFB.d(P(I))

! CAS PARTICULIER DES VITESSES :
! --> C.L PEUVENT COUPLER LES 3 COMPOSANTES DE VITESSES
!         (POUR L'INSTANT CE N'EST PAS LE CAS)

!  UXFAC = COEFAX +COEFBX  *UX(I) +COEFU(1)*UY(I) +COEFU(2)*UZ(I)
!  UYFAC = COEFAY +COEFU(1)*UX(I) +COEFBY  *UY(I) +COEFU(3)*UZ(I)
!  UZFAC = COEFAZ +COEFU(2)*UX(I) +COEFU(3)*UY(I) +COEFBZ  *UZ(I)

! On dispose du tableau de tri des faces de bord du
!   pas de temps precedent (sauf au premier pas de temps, ou
!   ITRIFB n'a pas ete renseigne)

!-------------------------------------------------------------------------------
! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! idbia0           ! i  ! <-- ! number of first free position in ia            !
! idbra0           ! i  ! <-- ! number of first free position in ra            !
! nvar             ! i  ! <-- ! total number of variables                      !
! nscal            ! i  ! <-- ! total number of scalars                        !
! nphas            ! i  ! <-- ! number of phases                               !
! isvhb            ! e  ! <-- ! indicateur de sauvegarde des                   !
!                  !    !     !  coefficients d'echange aux bords              !
! isvtb            ! e  ! <-- ! indicateur de sauvegarde des                   !
!                  !    !     !  temperatures aux bords                        !
! icodcl           ! te ! --> ! code de condition limites aux faces            !
!  (nfabor,nvar    !    !     !  de bord                                       !
!                  !    !     ! = 1   -> dirichlet                             !
!                  !    !     ! = 3   -> densite de flux                       !
!                  !    !     ! = 4   -> glissemt et u.n=0 (vitesse)           !
!                  !    !     ! = 5   -> frottemt et u.n=0 (vitesse)           !
!                  !    !     ! = 6   -> rugosite et u.n=0 (vitesse)           !
!                  !    !     ! = 9   -> entree/sortie libre (vitesse          !
!                  !    !     !  entrante eventuelle     bloquee               !
! isostd           ! te ! --> ! indicateur de sortie standard                  !
!    (nfabor+1)    !    !     !  +numero de la face de reference               !
! ia(*)            ! ia ! --- ! main integer work array                        !
! dt(ncelet)       ! ra ! <-- ! time step (per cell)                           !
! rtp, rtpa        ! ra ! <-- ! calculated variables at cell centers           !
!  (ncelet, *)     !    !     !  (at current and previous time steps)          !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! propfa(nfac, *)  ! ra ! <-- ! physical properties at interior face centers   !
! propfb(nfabor, *)! ra ! <-- ! physical properties at boundary face centers   !
! rcodcl           ! tr ! --> ! valeur des conditions aux limites              !
!  (nfabor,nvar    !    !     !  aux faces de bord                             !
!                  !    !     ! rcodcl(1) = valeur du dirichlet                !
!                  !    !     ! rcodcl(2) = valeur du coef. d'echange          !
!                  !    !     !  ext. (infinie si pas d'echange)               !
!                  !    !     ! rcodcl(3) = valeur de la densite de            !
!                  !    !     !  flux (negatif si gain) w/m2 ou                !
!                  !    !     !  hauteur de rugosite (m) si icodcl=6           !
!                  !    !     ! pour les vitesses (vistl+visct)*gradu          !
!                  !    !     ! pour la pression             dt*gradp          !
!                  !    !     ! pour les scalaires                             !
!                  !    !     !        cp*(viscls+visct/sigmas)*gradt          !
! coefa, coefb     ! ra ! <-- ! boundary conditions                            !
!  (nfabor, *)     !    !     !                                                !
! uetbor           ! tr ! --> ! vitesse de frottement au bord                  !
! (nfabor,nphas    !    !     !  pour van driest en les                        !
! visvdr(nphas)    ! tr ! --> ! viscosite dynamique ds les cellules            !
! (ncelet,nphas    !    !     !  de bord apres amortisst de v driest           !
! hbord            ! tr ! --> ! coefficients d'echange aux bords               !
! (nfabor)         !    !     !                                                !
! thbord           ! tr ! --> ! temperature aux bords en i'                    !
! (nfabor)         !    !     !    (plus exactmt : var. energetique)           !
! frcxt(ncelet,    ! tr ! <-- ! force exterieure generant la pression          !
!   3,nphas)       !    !     !  hydrostatique                                 !
! w1,2,3,4,5,6     ! ra ! --- ! work arrays                                    !
!  (ncelet)        !    !     !  (computation of pressure gradient)            !
! coefu            ! tr ! --- ! tab de trav pour valeurs en iprime             !
! (nfabor,3   )    !    !     !  des comp de la vitesse au bord                !
! rijipb           ! tr ! --- ! tab de trav pour valeurs en iprime             !
! (nfabor,6   )    !    !     !  des rij au bord                               !
! ra(*)            ! ra ! --- ! main real work array                           !
!__________________!____!_____!________________________________________________!

!     TYPE : E (ENTIER), R (REEL), A (ALPHANUMERIQUE), T (TABLEAU)
!            L (LOGIQUE)   .. ET TYPES COMPOSES (EX : TR TABLEAU REEL)
!     MODE : <-- donnee, --> resultat, <-> Donnee modifiee
!            --- tableau de travail
!===============================================================================

!===============================================================================
! Module files
!===============================================================================

use paramx
use dimens, only: ndimfb
use numvar
use optcal
use cstphy
use cstnum
use pointe
use entsor
use albase
use parall
use ppppar
use ppthch
use ppincl
use radiat
use cplsat
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0
integer          nvar   , nscal  , nphas
integer          isvhb  , isvtb

integer          icodcl(nfabor,nvar)
integer          isostd(nfabor+1)
integer          ia(*)

double precision dt(ncelet), rtp(ncelet,*), rtpa(ncelet,*)
double precision propce(ncelet,*)
double precision propfa(nfac,*), propfb(ndimfb,*)
double precision rcodcl(nfabor,nvar,3)
double precision frcxt(ncelet,3)
double precision coefa(ndimfb,*), coefb(ndimfb,*)
double precision uetbor(nfabor), visvdr(ncelet)
double precision hbord(nfabor),thbord(nfabor)
double precision w1(ncelet),w2(ncelet),w3(ncelet)
double precision w4(ncelet),w5(ncelet),w6(ncelet)
double precision coefu(nfabor,ndim), rijipb(nfabor,6)
double precision ra(*)

! Local variables

integer          idebia, idebra
integer          ifac  , iel   , ivar  , iphas
integer          isou  , ii    , iii   , iiph
integer          ihcp  , iscal , iscat
integer          inc   , iccocg, iphydp
integer          iok   , iok1
integer          icodcu
integer          isoent, isorti, ncpt,   isocpt(2)
integer          iclsym, ipatur, ipatrg, isvhbl
integer          iuiph , iviph , iwiph , ipriph
integer          ikiph , iepiph, iphiph, ifbiph, iomgip
integer          inuiph
integer          ir11ip, ir22ip, ir33ip, ir12ip, ir13ip, ir23ip
integer          ipcvis, ipcvst, ipccp , ipcvsl, ipccv
integer          iclpr , iclu  , iclv  , iclw  , iclk  , iclep
integer          iclnu
integer          icl11 , icl22 , icl33 , icl12 , icl13 , icl23
integer          icluf , iclvf , iclwf , iclphi, iclfb , iclomg
integer          iclvar, iclvaf, icluma, iclvma, iclwma
integer          iismph, iyplbp
integer          nswrgp, imligp, iwarnp, icliva
integer          iph
double precision sigma , cpp   , rkl
double precision hint  , hext  , pimp  , xdis
double precision flumbf, visclc, visctc, distbf, srfbn2
double precision epsrgp, climgp, extrap
double precision ro0iph, p0iph , pr0iph, xxp0, xyp0, xzp0
double precision srfbnf, rnx   , rny   , rnz
double precision upx   , upy   , upz   , vistot

!===============================================================================

!===============================================================================
! 1.  INITIALISATIONS
!===============================================================================

!  On a besoin des COEFA et COEFB pour le calcul des gradients
!     pour les cond lim turb en paroi
!   Leur valeur en entree n'est donc pas ecrasee (au premier pas de
!     temps ils sont initialises dans INIVAR a flux nul)

!  COEFU sert a stocker la vitesse en I'
!    On l'utilise aussi pour stocker la pression en I' (dans TYPECL), etc

! Initialize variables to avoid compiler warnings

iepiph = 0
ifbiph = 0
ikiph = 0
iomgip = 0
iphiph = 0
inuiph = 0
ir11ip = 0
ir22ip = 0
ir33ip = 0
ir12ip = 0
ir13ip = 0
ir23ip = 0
iclep = 0
iclk = 0
iclomg = 0
iclfb = 0
iclphi = 0
iclnu = 0
icl11 = 0
icl22 = 0
icl33 = 0
icl12 = 0
icl13 = 0
icl23 = 0
iclvar = 0
iclvaf = 0
icluf = 0
iclvf = 0
iclwf = 0
ipccv = 0
! Memoire

idebia = idbia0
idebra = idbra0

!  Initialisation du tableau pour stockage de yplus
!     On le remplit dans clptur

if(mod(ipstdv,ipstyp).eq.0) then
  iyplbp = iyplbr
  do ifac = 1, nfabor
    ra(iyplbp+ifac-1) = 0.d0
  enddo
endif


!===============================================================================
! 2.  TRAITEMENT DES CONDITIONS DONNES PAR ITYPFB
!===============================================================================


if(ippmod(iphpar).ge.1) then
  call pptycl                                                     &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   icodcl , ia(iitrif) , ia(iitypf)  , ia(iizfpp) ,               &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   coefa  , coefb  , rcodcl ,                                     &
   w1     , w2     , w3     , w4     , w5     , w6     , coefu  , &
   ra     )
endif

if (iale.eq.1) then
  call altycl                                                     &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   ia(iitypf)      , ia(iialty)      , icodcl , ia(iimpal)      , &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   rcodcl , ra(ixyzn0)      , ra(idepal)      ,                   &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   ra     )
endif

if (imobil.eq.1) then

  call mmtycl &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   ia(iitypf)      , icodcl ,                                     &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   rcodcl ,                                                       &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   ra     )

endif

call typecl                                                       &
!==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   ia(iitypf)      , ia(iitrif)      , icodcl , isostd ,          &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   coefa  , coefb  , rcodcl , frcxt  ,                            &
   w1     , w2     , w3     , w4     , w5     , w6     , coefu  , &
   ra     )

!===============================================================================
! 2.  VERIFICATION DE LA CONSISTANCE DES CL
!===============================================================================

call vericl                                                       &
!==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   icodcl ,                                                       &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   coefa  , coefb  , rcodcl ,                                     &
   ra     )

!===============================================================================
! 4. DISTANCE A LA PAROI ANCIEN MODELE
!===============================================================================
! attention, si on s'en sert pour autre chose, disons le module X
!   bien faire attention dans verini avec quelles options le module
!   X doit alors etre incompatible (perio, parall).

iok1 = 0

if(ineedy.eq.1.and.abs(icdpar).eq.2) then

  if(ia(iifapa).le.0) then

    ! ON FERA ATTENTION EN PARALLELISME OU PERIODICITE
    !    (UNE PAROI PEUT ETRE PLUS PROCHE EN TRAVERSANT UN BORD ...)

    do iel = 1, ncel
      w1(iel) = grand
    enddo

    iuiph = iu

    do ifac = 1, nfabor
      icodcu = icodcl(ifac,iuiph)
      if( icodcu.eq.5 .or. icodcu.eq.6 ) then
        do iel = 1, ncel
          xdis =                                                &
               (cdgfbo(1,ifac)-xyzcen(1,iel))**2                   &
               +(cdgfbo(2,ifac)-xyzcen(2,iel))**2                   &
               +(cdgfbo(3,ifac)-xyzcen(3,iel))**2
          if(w1(iel).gt.xdis) then
            w1(iel) = xdis
            ia(iifapa-1+iel) = ifac
          endif
        enddo
      endif
    enddo

  endif

  iok = 0
  do iel = 1, ncel
    if(ia(iifapa-1+iel).le.0)then
      iok = iok + 1
    endif
  enddo
  if(iok.gt.0) then
    write(nfecra,1000) irijec, idries
    iok1 = 1
  endif

endif

!     Normalement, on ne passe pas en parallele ici,
!       mais au cas ou ...
if(irangp.ge.0) then
  call parcpt(iok1)
endif

if(iok1.ne.0) then
  call csexit (1)
  !==========
endif


!===============================================================================
! 6.  DEBUT DE LA BOUCLE SUR LES PHASES
!        ET REPERAGE DES VARIABLES
!===============================================================================

! --- Variables
ro0iph = ro0
p0iph  = p0
pr0iph = pred0
xxp0   = xyzp0(1)
xyp0   = xyzp0(2)
xzp0   = xyzp0(3)
ipriph = ipr
iuiph  = iu
iviph  = iv
iwiph  = iw
if(itytur.eq.2) then
  ikiph  = ik
  iepiph = iep
elseif(itytur.eq.3) then
  ir11ip = ir11
  ir22ip = ir22
  ir33ip = ir33
  ir12ip = ir12
  ir13ip = ir13
  ir23ip = ir23
  iepiph = iep
elseif(iturb.eq.50) then
  ikiph  = ik
  iepiph = iep
  iphiph = iphi
  ifbiph = ifb
elseif(iturb.eq.60) then
  ikiph  = ik
  iomgip = iomg
elseif(iturb.eq.70) then
  inuiph = inusa
endif

! --- Conditions aux limites
iclpr  = iclrtp(ipriph,icoef)
iclu   = iclrtp(iuiph ,icoef)
iclv   = iclrtp(iviph ,icoef)
iclw   = iclrtp(iwiph ,icoef)
if(itytur.eq.2) then
  iclk   = iclrtp(ikiph ,icoef)
  iclep  = iclrtp(iepiph,icoef)
elseif(itytur.eq.3) then
  icl11  = iclrtp(ir11ip,icoef)
  icl22  = iclrtp(ir22ip,icoef)
  icl33  = iclrtp(ir33ip,icoef)
  icl12  = iclrtp(ir12ip,icoef)
  icl13  = iclrtp(ir13ip,icoef)
  icl23  = iclrtp(ir23ip,icoef)
  iclep  = iclrtp(iepiph,icoef)
elseif(iturb.eq.50) then
  iclk   = iclrtp(ikiph ,icoef)
  iclep  = iclrtp(iepiph,icoef)
  iclphi = iclrtp(iphiph,icoef)
  iclfb  = iclrtp(ifbiph,icoef)
elseif(iturb.eq.60) then
  iclk   = iclrtp(ikiph ,icoef)
  iclomg = iclrtp(iomgip,icoef)
elseif(iturb.eq.70) then
  iclnu  = iclrtp(inuiph,icoef)
endif

icluf  = iclrtp(iuiph ,icoeff)
iclvf  = iclrtp(iviph ,icoeff)
iclwf  = iclrtp(iwiph ,icoeff)

! --- Grandeurs physiques
ipcvis = ipproc(iviscl)
ipcvst = ipproc(ivisct)
if(icp.gt.0) then
  ipccp  = ipproc(icp   )
else
  ipccp = 0
endif
! --- Compressible
if ( ippmod(icompf).ge.0 ) then
  if(icv.gt.0) then
    ipccv  = ipproc(icv   )
  else
    ipccv = 0
  endif
endif



!===============================================================================
! 6.  CONSTRUCTION DE LA TEMPERATURE OU ENTHALPIE
!        AU CENTRE DES FACES DE BORD (OBTENUS PAR Fi + II'.GRAD(Fi))

!          POUR LE COUPLAGE SYRTHES
!            THBORD EST UTILISE PAR COUPBO EN SORTIE DE CONDLI
!          POUR LE COUPLAGE AVEC LE MODULE THERMIQUE 1D DE PAROI
!            THBORD EST UTILISE PAR COU1DO EN SORTIE DE CONDLI
!          POUR LE RAYONNEMENT
!            THBORD EST DANS LA BOUCLE POUR CONSTUIRE LE FLUX QUI SERT
!            DANS RAYPAR.

!        LE CAS PLUSIEURS PHASES COUPLEES AVEC SYRTHES N'EST PAS PREVU.
!        LE CAS PLUSIEURS PHASES COUPLEES AVEC LE MODULE 1D  N'EST PAS PREVU.


!        CECI POURRAIT EN PRATIQUE ETRE HORS DE LA BOUCLE.

!===============================================================================

!  Pour le couplage SYRTHES ou module thermique 1D
!  -----------------------------------------------
!  Ici, on fait une boucle "inutile"  (on ne fait quelque chose
!    que pour ICPSYR(ISCAL) = 1). C'est pour preparer le traitement
!    eventuel de plusieurs temperatures (ie plusieurs couplages
!    SYRTHES a la fois ; noter cependant que meme dans ce cas,
!    une seule temperature sera recue de chaque couplage. En polyph,
!    il faudrait ensuite reconstruire les enthalpies des phases ...
!    plus tard si necessaire).
!  Ici, il ne peut y avoir qu'un seul scalaire avec ICPSYR = 1 et
!    ce uniquement s'il y a effectivement couplage avec SYRTHES
!    (sinon, on s'est arrete dans verini)
! Dans le cas du couplage avec le module 1D, on utilise le scalaire
!    couple avec Syrthes s'il y a couplage, sinon ISCALT(1).
!  La valeur de ISVTB a ete initialisee dans tridim
!    au numero du scalaire couple.


!  Pour le rayonnement
!  -------------------
!  On calcule la valeur en I' s'il y a une variable
!    thermique sur la phase


!  On recherche l'unique scalaire qui convient pour la phase courante
!     (ce peut etre T, H, ou E (en compressible))

iscat = 0

!     Si un scalaire est couple a SYRTHES ou au module 1D
if(isvtb.ne.0) then
  !         si ce n'est pas la variable thermique, ca ne va pas.
  if(isvtb.ne.iscalt) then
    write(nfecra,8000)isvtb,iscalt
    call csexit (1)
    !==========
    !         sinon, on calcule le gradient.
  else
    iscat = isvtb
  endif
endif


!     S'il y a du rayonnement
!       (il y a forcement une variable energetique)
!       on en calcule le gradient
if(iirayo.ge.1) then
  iscat = iscalt
endif

!     S'il y a un scalaire dont il faut calculer le gradient
!       ... on le calcule.
if (iscat .gt. 0) then

  ivar   = isca(iscat)

  if (ntcabs.gt.1 .and. itbrrb.eq.1) then

    inc = 1
    iccocg = 1
    nswrgp = nswrgr(ivar)
    imligp = imligr(ivar)
    iwarnp = iwarni(ivar)
    epsrgp = epsrgr(ivar)
    climgp = climgr(ivar)
    extrap = extrag(ivar)
    icliva = iclrtp(ivar,icoef)
    iphydp = 0

    call grdcel                                                 &
    !==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   ivar   , imrgra , inc    , iccocg , nswrgp , imligp ,  iphydp ,&
   iwarnp , nfecra ,                                              &
   epsrgp , climgp , extrap ,                                     &
   ia     ,                                                       &
   w1     , w1     , w1     ,                                     &
   rtpa(1,ivar)    , coefa(1,icliva) , coefb(1,icliva) ,          &
   w1     , w2     , w3     ,                                     &
!        ------   ------   ------
   w4     , w5     , w6     ,                                     &
   ra     )

    do ifac = 1 , nfabor
      iel = ifabor(ifac)
      thbord(ifac)       =                                                 &
           w1(iel)*diipb(1,ifac)+w2(iel)*diipb(2,ifac)+w3(iel)*diipb(3,ifac)  &
           + rtpa(iel,ivar)
    enddo

  else

    do ifac = 1 , nfabor
      iel = ifabor(ifac)
      thbord(ifac) = rtpa(iel,ivar)
    enddo

  endif

endif

!===============================================================================
! 6.  CONSTRUCTION DE LA VITESSE ET DU TENSEUR DE REYNOLDS
!        AU CENTRE DES FACES DE BORD (OBTENUS PAR Fi + II'.GRAD(Fi))
!        S'IL Y A DES SYMETRIES OU DES PAROIS TURBULENTES
!===============================================================================

! ---> INDICATEUR SYMETRIES OU PAROIS TURBULENTES

iclsym = 0
ipatur = 0
ipatrg = 0
do ifac = 1, nfabor
  if ( icodcl(ifac,iuiph).eq.4 ) then
    iclsym = 1
  elseif ( icodcl(ifac,iuiph).eq.5 ) then
    ipatur = 1
  elseif ( icodcl(ifac,iuiph).eq.6 ) then
    ipatrg = 1
  endif
  if (iclsym.ne.0.and.ipatur.ne.0.and.ipatrg.ne.0 ) goto 100
enddo
100 continue

if (irangp.ge.0) then
  call parcmx(iclsym)
  call parcmx(ipatur)
  call parcmx(ipatrg)
endif


! ---> CONSTRUCTION DE LA VITESSE AU CENTRE DES FACES DE BORD

if (iclsym.ne.0.or.ipatur.ne.0.or.ipatrg.ne.0) then


  do isou = 1, 3

    if(isou.eq.1) ivar = iuiph
    if(isou.eq.2) ivar = iviph
    if(isou.eq.3) ivar = iwiph

    if(ntcabs.gt.1) then

      iccocg = 1
      inc    = 1
      nswrgp = nswrgr(ivar)
      imligp = imligr(ivar)
      iwarnp = iwarni(ivar)
      epsrgp = epsrgr(ivar)
      climgp = climgr(ivar)
      extrap = extrag(ivar)
      icliva = iclrtp(ivar,icoef)
      iphydp = 0

      call grdcel                                               &
      !==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   ivar   , imrgra , inc    , iccocg , nswrgp , imligp , iphydp , &
   iwarnp , nfecra ,                                              &
   epsrgp , climgp , extrap ,                                     &
   ia     ,                                                       &
   w1     , w1     , w1     ,                                     &
   rtpa(1,ivar)    , coefa(1,icliva) , coefb(1,icliva) ,          &
   w1     , w2     , w3     ,                                     &
!        ------   ------   ------
   w4     , w5     , w6     ,                                     &
   ra     )

      do ifac = 1, nfabor
        iel = ifabor(ifac)
        coefu(ifac,isou) =                                                  &
             w1(iel)*diipb(1,ifac)+w2(iel)*diipb(2,ifac)+w3(iel)*diipb(3,ifac) &
             + rtpa(iel,ivar)
      enddo

    else

      do ifac = 1, nfabor
        iel = ifabor(ifac)
        coefu(ifac,isou) = rtpa(iel,ivar)
      enddo

    endif

  enddo

endif


! ---> CONSTRUCTION DU TENSEUR DE REYNOLDS AU CENTRE DES FACES DE BORD

if ((iclsym.ne.0.or.ipatur.ne.0.or.ipatrg.ne.0)                 &
     .and.itytur.eq.3) then


  do isou = 1 , 6

    if(isou.eq.1) ivar = ir11ip
    if(isou.eq.2) ivar = ir22ip
    if(isou.eq.3) ivar = ir33ip
    if(isou.eq.4) ivar = ir12ip
    if(isou.eq.5) ivar = ir13ip
    if(isou.eq.6) ivar = ir23ip


    if(ntcabs.gt.1.and.irijrb.eq.1) then

      ! CALCUL DU GRADIENT CELLULE DE Rij EN I

      inc = 1
      iccocg = 1
      nswrgp = nswrgr(ivar)
      imligp = imligr(ivar)
      iwarnp = iwarni(ivar)
      epsrgp = epsrgr(ivar)
      climgp = climgr(ivar)
      extrap = extrag(ivar)
      icliva = iclrtp(ivar,icoef)
      iphydp = 0

      call grdcel                                               &
      !==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   ivar   , imrgra , inc    , iccocg , nswrgp , imligp , iphydp , &
   iwarnp , nfecra ,                                              &
   epsrgp , climgp , extrap ,                                     &
   ia     ,                                                       &
   w1     , w1     , w1     ,                                     &
   rtpa(1,ivar)    , coefa(1,icliva) , coefb(1,icliva) ,          &
   w1     , w2     , w3     ,                                     &
!        ------   ------   ------
   w4     , w5     , w6     ,                                     &
   ra     )


      ! CALCUL DE LA VALEUR EN I' DE Rij

      do ifac = 1 , nfabor
        iel = ifabor(ifac)
        rijipb(ifac,isou) =                                                 &
             w1(iel)*diipb(1,ifac)+w2(iel)*diipb(2,ifac)+w3(iel)*diipb(3,ifac) &
             + rtpa(iel,ivar)
      enddo


      !   AU PREMIER PAS DE TEMPS, ON NE CONNAIT PAS COEFA ET COEFB
      !   (ILS SONT ANNULES DANS CONDLI), LE CALCUL DE RI' EST SIMPLIFIE

    else

      do ifac = 1 , nfabor
        iel = ifabor(ifac)
        rijipb(ifac,isou) = rtpa(iel,ivar)
      enddo

    endif

  enddo

endif

!===============================================================================
! 7.  TURBULENCE EN PAROI : TOUTES LES VARIABLES CONCERNEES PAR PHASE
!       (U,V,W,K,EPSILON,RIJ,TEMPERATURE)
!===============================================================================
! --- On a besoin de COEFU et de RIJIPB (et THBORD pour le rayonnement)
! --- On suppose que tout scalaire qui dispose de cl de paroi est
!       associe a une phase (qui permet entre autre de calculer yplus)

!     On initialise VISVDR a -999.D0.
!     Dans clptur, on amortit la viscosite turbulente sur les cellules
!     de paroi si on a active van Driest. La valeur finale est aussi
!     stockee dans VISVDR.
!     Plus loin, dans vandri, la viscosite sur les cellules
!     de paroi sera amortie une seconde fois. On se sert alors de
!     VISVDR pour lui redonner une valeur correcte.
if(itytur.eq.4.and.idries.eq.1) then
  do iel=1,ncel
    visvdr(iel) = -999.d0
  enddo
endif

if (ipatur.ne.0) then

  ! Smooth wall laws
  call clptur                                                   &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   iphas  , isvhb  ,                                              &
   icodcl ,                                                       &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb , rcodcl , &
   coefu  , rijipb , coefa  , coefb  , uetbor , visvdr ,          &
   hbord  , thbord ,                                              &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   ra     )

endif

if (ipatrg.ne.0) then

  ! Rough wall laws
  call clptrg                                                   &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   iphas  , isvhb  ,                                              &
   icodcl ,                                                       &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb , rcodcl , &
   coefu  , rijipb , coefa  , coefb  , uetbor , visvdr ,          &
   hbord  , thbord ,                                              &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   ra     )

endif

!===============================================================================
! 7.  SYMETRIES POUR LES VECTEURS ET TENSEURS
!       (U,V,W,RIJ)
!===============================================================================
!   On a besoin de COEFU et de RIJIPB

iismph = iisymp
do ifac = 1, nfabor
  ia(iismph+ifac-1) = 1
enddo

if (iclsym.ne.0) then

  call clsyvt                                                   &
  !==========
 ( idebia , idebra ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   iphas  ,                                                       &
   icodcl , ia(iismph) ,                                          &
   ia     ,                                                       &
   dt     , rtp    , rtpa   , propce , propfa , propfb , rcodcl , &
   coefu  , rijipb , coefa  , coefb  ,                            &
   w1     , w2     , w3     , w4     , w5     , w6     ,          &
   ra     )

endif

!===============================================================================
! 8.  VITESSE : SORTIE, DIRICHLET, NEUMANN
!===============================================================================

! ---> SORTIE : SI FLUX ENTRANT, ON "BLOQUE" A L'INFINI AVAL

isoent = 0
isorti = 0
do ifac = 1, nfabor

  flumbf = propfb(ifac,ipprob(ifluma(iuiph)))

  if( icodcl(ifac,iuiph).eq.9 ) then

    isorti = isorti + 1
    if( flumbf.lt.-epzero) then
      coefa(ifac,iclu) = 0.d0
      coefb(ifac,iclu) = 0.d0
      coefa(ifac,iclv) = 0.d0
      coefb(ifac,iclv) = 0.d0
      coefa(ifac,iclw) = 0.d0
      coefb(ifac,iclw) = 0.d0
      isoent = isoent + 1
    else
      coefa(ifac,iclu) = 0.d0
      coefb(ifac,iclu) = 1.d0
      coefa(ifac,iclv) = 0.d0
      coefb(ifac,iclv) = 1.d0
      coefa(ifac,iclw) = 0.d0
      coefb(ifac,iclw) = 1.d0
    endif

  endif

enddo

if (mod(ntcabs,ntlist).eq.0 .or. iwarni(iu).ge. 0) then
  isocpt(1) = isoent
  isocpt(2) = isorti
  if (irangp.ge.0) then
    ncpt = 2
    call parism(ncpt, isocpt)
  endif
  if (isocpt(2).gt.0 .and. (iwarni(iuiph).ge.2.or.isocpt(1).gt.0)) then
    write(nfecra,3010) isocpt(1), isocpt(2)
  endif
endif

! ---> DIRICHLET ET FLUX

do ii = 1, 3

  if(ii.eq.1) then
    ivar   = iuiph
    iclvar = iclu
  elseif(ii.eq.2) then
    ivar   = iviph
    iclvar = iclv
  elseif(ii.eq.3) then
    ivar   = iwiph
    iclvar = iclw
  endif

  do ifac = 1, nfabor

    iel = ifabor(ifac)

    ! --- Proprietes physiques
    visclc = propce(iel,ipcvis)
    visctc = propce(iel,ipcvst)

    ! --- Grandeurs geometriques
    distbf = distb(ifac)

    if (itytur.eq.3) then
      hint =   visclc         /distbf
    else
      hint = ( visclc+visctc )/distbf
    endif

    !      C.L DE TYPE DIRICHLET
    if( icodcl(ifac,ivar).eq.1 ) then
      hext = rcodcl(ifac,ivar,2)
      if(abs(hext).gt.rinfin*0.5d0) then
        pimp = rcodcl(ifac,ivar,1)
        coefa(ifac,iclvar) = pimp
        coefb(ifac,iclvar) = 0.d0
      else
        pimp = rcodcl(ifac,ivar,1)
        coefa(ifac,iclvar) = hext*pimp/(hint +hext)
        coefb(ifac,iclvar) = hint     /(hint +hext)
      endif

      !      C.L DE TYPE FLUX
    elseif( icodcl(ifac,ivar).eq.3 ) then
      coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
      coefb(ifac,iclvar) = 1.d0
    endif

  enddo

enddo

! ---> COEFAF ET COEFBF
!       POUR TOUS LES CODES SAUF 4, 5 ET 6 TRAITES SEPAREMENT

do ii = 1, 3

  if(ii.eq.1) then
    ivar   = iuiph
    iclvar = iclu
    iclvaf = icluf
  elseif(ii.eq.2) then
    ivar   = iviph
    iclvar = iclv
    iclvaf = iclvf
  elseif(ii.eq.3) then
    ivar   = iwiph
    iclvar = iclw
    iclvaf = iclwf
  endif

  if(iclvaf.ne.iclvar) then
    do ifac = 1, nfabor
      if( icodcl(ifac,ivar).eq.1.or.icodcl(ifac,ivar).eq.3.or.  &
           icodcl(ifac,ivar).eq.9                          ) then
        coefa(ifac,iclvaf) = coefa(ifac,iclvar)
        coefb(ifac,iclvaf) = coefb(ifac,iclvar)
      endif
    enddo
  endif

enddo


! --- La boucle sur les phases continue
!===============================================================================
! 9.  PRESSION : DIRICHLET, NEUMANN
!===============================================================================

do ifac = 1, nfabor

  iel = ifabor(ifac)

  ! --- Grandeurs geometriques
  distbf = distb(ifac)

  ! ON MET UN FLUX EN DT.GRAD P (W/m2) DANS USCLIM
  hint = dt(iel)/distbf

  ! On doit remodifier la valeur du  Dirichlet de pression de mani�re
  !  � retrouver P*. Car dans typecl.F on a travaill� avec la pression
  ! totale fournie par l'utilisateur :  Ptotale= P*+ rho.g.r
  ! En compressible, on laisse RCODCL tel quel

  !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE

  if( icodcl(ifac,ipriph).eq.1 ) then
    hext = rcodcl(ifac,ipriph,2)
    if ( ippmod(icompf).ge.0 ) then
      pimp = rcodcl(ifac,ipriph,1)
    else
      pimp = rcodcl(ifac,ipriph,1)                              &
           - ro0iph*( gx*(cdgfbo(1,ifac)-xxp0)                  &
           + gy*(cdgfbo(2,ifac)-xyp0)                  &
           + gz*(cdgfbo(3,ifac)-xzp0) )                &
           + pr0iph - p0iph
    endif
    if( abs(hext).gt.rinfin*0.5d0 ) then
      coefa(ifac,iclpr) = pimp
      coefb(ifac,iclpr) = 0.d0
    else
      coefa(ifac,iclpr) = hext*pimp/(hint +hext)
      coefb(ifac,iclpr) = hint     /(hint +hext)
    endif
  endif

  !      C.L DE TYPE FLUX
  if( icodcl(ifac,ipriph).eq.3 ) then
    coefa(ifac,iclpr) = -rcodcl(ifac,ipriph,3)/hint
    coefb(ifac,iclpr) = 1.d0
  endif

enddo


! --- La boucle sur les phases continue
!===============================================================================
! 10.  K, EPSILON, RIJ, V2F, OMEGA : DIRICHLET, NEUMANN
!===============================================================================

! ---> K-EPSILON ET K-OMEGA

if(itytur.eq.2 .or. iturb.eq.60) then

  do ii = 1, 2

    !     Pour le k-omega, on met les valeurs sigma_k2 et sigma_w2 car ce terme
    !     ne concerne en pratique que les entrees (pas de pb en paroi ou en flux
    !     nul)
    if(ii.eq.1 .and. itytur.eq.2) then
      ivar   = ikiph
      iclvar = iclk
      sigma  = sigmak
    elseif(ii.eq.1 .and. iturb.eq.60) then
      ivar   = ikiph
      iclvar = iclk
      sigma  = ckwsk2
    elseif (itytur.eq.2) then
      ivar   = iepiph
      iclvar = iclep
      sigma  = sigmae
    else
      ivar   = iomgip
      iclvar = iclomg
      sigma  = ckwsw2
    endif

    do ifac = 1, nfabor

      iel = ifabor(ifac)

      ! --- Proprietes physiques
      visclc = propce(iel,ipcvis)
      visctc = propce(iel,ipcvst)
      flumbf = propfb(ifac,ipprob(ifluma(ikiph)))

      ! --- Grandeurs geometriques
      distbf = distb(ifac)

      hint = (visclc+visctc/sigma)/distbf

      !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE
      if(icodcl(ifac,ivar).eq.1) then
        hext = rcodcl(ifac,ivar,2)
        pimp = rcodcl(ifac,ivar,1)
        coefa(ifac,iclvar) = hext*pimp/(hint +hext)
        coefb(ifac,iclvar) = hint     /(hint +hext)
        !      C.L DE TYPE FLUX
      elseif(icodcl(ifac,ivar).eq.3)then
        coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
        coefb(ifac,iclvar) = 1.d0
      endif
    enddo

  enddo

  ! ---> RIJ-EPSILON
  !         (ATTENTION, PAS DE VISCT)

elseif(itytur.eq.3) then

  !   --> RIJ

  do isou = 1, 6

    if(isou.eq.1) then
      ivar   = ir11ip
      iclvar = icl11
    elseif(isou.eq.2) then
      ivar   = ir22ip
      iclvar = icl22
    elseif(isou.eq.3) then
      ivar   = ir33ip
      iclvar = icl33
    elseif(isou.eq.4) then
      ivar   = ir12ip
      iclvar = icl12
    elseif(isou.eq.5) then
      ivar   = ir13ip
      iclvar = icl13
    elseif(isou.eq.6) then
      ivar   = ir23ip
      iclvar = icl23
    endif

    do ifac = 1, nfabor

      iel = ifabor(ifac)

      ! --- Proprietes physiques
      visclc = propce(iel,ipcvis)
      flumbf = propfb(ifac,ipprob(ifluma(ir11ip)))

      ! --- Grandeurs geometriques
      distbf = distb(ifac)

      if(icodcl(ifac,ivar).eq.1) then
        hint = visclc/distbf

        hext = rcodcl(ifac,ivar,2)
        pimp = rcodcl(ifac,ivar,1)
        coefa(ifac,iclvar) = hext*pimp/(hint +hext)
        coefb(ifac,iclvar) = hint     /(hint +hext)

      elseif(icodcl(ifac,ivar).eq.3)then

        hint = visclc/distbf

        coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
        coefb(ifac,iclvar) = 1.d0

      endif

    enddo

  enddo


  !   --> EPSILON

  ivar   = iepiph
  iclvar = iclep

  do ifac = 1, nfabor

    iel = ifabor(ifac)

    ! --- Proprietes physiques
    visclc = propce(iel,ipcvis)
    flumbf = propfb(ifac,ipprob(ifluma(iepiph)))

    ! --- Grandeurs geometriques
    distbf = distb(ifac)

    hint = visclc/distbf

    !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE
    if( icodcl(ifac,ivar).eq.1) then
      hext = rcodcl(ifac,ivar,2)
      pimp = rcodcl(ifac,ivar,1)
      coefa(ifac,iclvar) = hext*pimp/(hint +hext)
      coefb(ifac,iclvar) = hint     /(hint +hext)
      !      C.L DE TYPE FLUX
    elseif(                                                     &
         icodcl(ifac,ivar).eq.3)then
      coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
      coefb(ifac,iclvar) = 1.d0
    endif

  enddo

  ! ---> SPALART ALLMARAS

elseif(iturb.eq.70) then

  ivar   = inuiph
  iclvar = iclnu

  do ifac = 1, nfabor

    iel = ifabor(ifac)

    ! --- Proprietes physiques
    visclc = propce(iel,ipcvis)
    flumbf = propfb(ifac,ipprob(ifluma(inuiph)))

    ! --- Grandeurs geometriques
    distbf = distb(ifac)
    hint = visclc/distbf

    !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE
    if( icodcl(ifac,ivar).eq.1) then
      hext = rcodcl(ifac,ivar,2)
      pimp = rcodcl(ifac,ivar,1)
      coefa(ifac,iclvar) = hext*pimp/(hint +hext)
      coefb(ifac,iclvar) = hint     /(hint +hext)
      !      C.L DE TYPE FLUX
    elseif(                                                     &
         icodcl(ifac,ivar).eq.3)then
      coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
      coefb(ifac,iclvar) = 1.d0
    endif

  enddo


  ! ---> V2F

elseif(iturb.eq.50) then

  !   --> K, EPSILON ET PHI
  do ii = 1, 3

    if(ii.eq.1) then
      ivar   = ikiph
      iclvar = iclk
      sigma  = sigmak
    elseif(ii.eq.2) then
      ivar   = iepiph
      iclvar = iclep
      sigma  = sigmae
    else
      ivar   = iphiph
      iclvar = iclphi
      sigma  = sigmak
    endif

    do ifac = 1, nfabor

      iel = ifabor(ifac)

      ! --- Proprietes physiques
      visclc = propce(iel,ipcvis)
      visctc = propce(iel,ipcvst)
      flumbf = propfb(ifac,ipprob(ifluma(ikiph)))

      ! --- Grandeurs geometriques
      distbf = distb(ifac)

      hint = (visclc+visctc/sigma)/distbf

      !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE
      if(icodcl(ifac,ivar).eq.1) then
        hext = rcodcl(ifac,ivar,2)
        pimp = rcodcl(ifac,ivar,1)
        coefa(ifac,iclvar) = hext*pimp/(hint +hext)
        coefb(ifac,iclvar) = hint     /(hint +hext)
        !      C.L DE TYPE FLUX

      elseif(icodcl(ifac,ivar).eq.3)then
        coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
        coefb(ifac,iclvar) = 1.d0
      endif
    enddo

  enddo

  !   --> FB

  ivar   = ifbiph
  iclvar = iclfb

  do ifac = 1, nfabor

    ! --- Proprietes physiques
    visclc = 1.d0
    flumbf = propfb(ifac,ipprob(ifluma(ifbiph)))

    ! --- Grandeurs geometriques
    distbf = distb(ifac)

    hint = visclc/distbf

    !      C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE
    if( icodcl(ifac,ivar).eq.1) then
      hext = rcodcl(ifac,ivar,2)
      pimp = rcodcl(ifac,ivar,1)
      coefa(ifac,iclvar) = hext*pimp/(hint +hext)
      coefb(ifac,iclvar) = hint     /(hint +hext)
      !      C.L DE TYPE FLUX
    elseif(icodcl(ifac,ivar).eq.3)then
      coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
      coefb(ifac,iclvar) = 1.d0
    endif

  enddo

endif

! --- La boucle sur les phases continue
!===============================================================================
! 11. SCALAIRES (AUTRES QUE PRESSION, K, EPSILON, RIJ, OMEGA, VARIANCES)
!                     : DIRICHLET, NEUMANN
!===============================================================================

if(nscal.ge.1) then

  do ii = 1, nscal

    ivar   = isca(ii)
    iclvar = iclrtp(ivar,icoef)
    iclvaf = iclrtp(ivar,icoeff)

    isvhbl = 0
    if(ii.eq.isvhb) then
      isvhbl = isvhb
    endif

    if(ivisls(ii).gt.0) then
      ipcvsl = ipproc(ivisls(ii))
    else
      ipcvsl = 0
    endif

    ! --- Indicateur de prise en compte de Cp ou non
    !       (selon si le scalaire (scalaire associe pour une fluctuation)
    !        doit etre ou non traite comme une temperature)
    !      Si le scalaire est une variance et que le
    !        scalaire associe n'est pas resolu, on suppose alors qu'il
    !        doit etre traite comme un scalaire passif (defaut IHCP = 0)
    ihcp = 0
    if(iscavr(ii).le.nscal) then
      if(iscavr(ii).gt.0) then
        iscal = iscavr(ii)
      else
        iscal = ii
      endif
      if(iscsth(iscal).eq.0.or.iscsth(iscal).eq.2             &
           .or.iscsth(iscal).eq.3) then
        ihcp = 0
      elseif(abs(iscsth(iscal)).eq.1) then
        if(ipccp.gt.0) then
          ihcp = 2
        else
          ihcp = 1
        endif
      endif
    endif

    ! --- Boucle sur les faces
    do ifac = 1, nfabor

      iel = ifabor(ifac)

      ! --- Proprietes physiques
      visctc = propce(iel,ipcvst)
      flumbf = propfb(ifac,ipprob(ifluma(ivar)))

      ! --- Grandeurs geometriques
      distbf = distb(ifac)

      ! --- Prise en compte de Cp ou CV
      !      (dans le Cas compressible IHCP=0)

      cpp = 1.d0
      if(ihcp.eq.0) then
        cpp = 1.d0
      elseif(ihcp.eq.2) then
        cpp = propce(iel,ipccp )
      elseif(ihcp.eq.1) then
        cpp = cp0
      endif
      hint = cpp

      ! --- Viscosite variable ou non
      if (ipcvsl.le.0) then
        rkl = visls0(ii)
      else
        rkl = propce(iel,ipcvsl)
      endif

      ! --- Cas turbulent
      if (iturb.ne.0) then
        hint = hint*(rkl+visctc/sigmas(ii))/distbf
        !     Cas laminaire
      else
        hint  = hint*rkl/distbf
      endif

      ! --->  C.L DE TYPE DIRICHLET AVEC OU SANS COEFFICIENT D'ECHANGE

      if( icodcl(ifac,ivar).eq.1) then
        hext = rcodcl(ifac,ivar,2)
        if(abs(hext).ge.rinfin*0.5d0) then
          pimp = rcodcl(ifac,ivar,1)
          coefa(ifac,iclvar) = pimp
          coefb(ifac,iclvar) = 0.d0
        else
          pimp = rcodcl(ifac,ivar,1)
          coefa(ifac,iclvar) = hext*pimp/(hint+hext)
          coefb(ifac,iclvar) = hint     /(hint+hext)
        endif

        !     On utilise le Dirichlet pour les calculs de gradients
        !       et pour les flux de bord.

        if(iclvaf.ne.iclvar) then
          coefa(ifac,iclvaf) = coefa(ifac,iclvar)
          coefb(ifac,iclvaf) = coefb(ifac,iclvar)
        endif

        ! ---> COUPLAGE : on stocke le hint (lambda/d      en temperature,
        !                                    lambda/(cp d) en enthalpie,
        !                                    lambda/(cv d) en energie)

        if (isvhbl .gt. 0) then
          hbord(ifac) = hint
        endif


        !--> Rayonnement :

        !      On stocke le coefficient d'echange lambda/distance
        !      (ou son equivalent en turbulent) quelle que soit la
        !      variable thermique transportee (temperature ou enthalpie)
        !      car on l'utilise pour realiser des bilans aux parois qui
        !      sont faits en temperature (on cherche la temperature de
        !      paroi quelle que soit la variable thermique transportee pour
        !      ecrire des eps sigma T4).

        !     donc :

        !       lorsque la variable transportee est la temperature
        !         ABS(ISCSTH(II)).EQ.1 : RA(IHCONV-1+IFAC+NFABOR*(IPH-1)) = HINT
        !         puisque HINT = VISLS * CP / DISTBR
        !                      = lambda/distance en W/(m2 K)

        !       lorsque la variable transportee est l'enthalpie
        !         ISCSTH(II).EQ.2 : RA(IHCONV-1+IFAC+NFABOR*(IPH-1)) = HINT*CPR
        !         avec
        !            IF(IPCCP.GT.0) THEN
        !              CPR = PROPCE(IEL,IPCCP )
        !            ELSE
        !              CPR = CP0
        !            ENDIF
        !         puisque HINT = VISLS / DISTBR
        !                      = lambda/(CP * distance)

        !       lorsque la variable transportee est l'energie
        !         ISCSTH(II).EQ.3 :
        !         on procede comme pour l'enthalpie avec CV au lieu de CP
        !         (rq : il n'y a pas d'hypoth�se, sf en non orthogonal :
        !               le flux est le bon et le coef d'echange aussi)

        !      De meme plus bas et de meme dans clptur.

        !               Si on rayonne et que
        !                  le scalaire est la variable energetique

        if (iirayo.ge.1 .and. ii.eq.iscalt) then

          !                On calcule le coefficient d'echange en W/(m2 K)

          !                  Si on resout en enthalpie
          if(iscsth(ii).eq.2) then
            !                    Si Cp variable
            if(ipccp.gt.0) then
              propfb(ifac,ipprob(ihconv)) = hint*propce(iel,ipccp )
            else
              propfb(ifac,ipprob(ihconv)) = hint*cp0
            endif
            !                  Si on resout en energie (compressible)
          elseif(iscsth(ii).eq.3) then
            !                    Si Cv variable
            if(ipccv.gt.0) then
              propfb(ifac,ipprob(ihconv)) = hint*propce(iel,ipccv )
            else
              propfb(ifac,ipprob(ihconv)) = hint*cv0
            endif
            !                  Si on resout en temperature
          elseif(abs(iscsth(ii)).eq.1) then
            propfb(ifac,ipprob(ihconv)) = hint
          endif

          !                On recupere le flux h(Ti'-Tp) (sortant ou
          !                             negatif si gain pour le fluide) en W/m2

          propfb(ifac,ipprob(ifconv)) =                       &
               hint*( (1.d0-coefb(ifac,iclvaf))*thbord(ifac)  &
               - coefa(ifac,iclvaf))

        endif

        ! --->  C.L DE TYPE FLUX

      elseif(icodcl(ifac,ivar).eq.3)then
        coefa(ifac,iclvaf)  = -rcodcl(ifac,ivar,3)/hint
        coefb(ifac,iclvaf)  = 1.d0
        if(iclvar.ne.iclvaf) then
          coefa(ifac,iclvar)  = 0.d0
          coefb(ifac,iclvar)  = 1.d0
        endif
        if (isvhbl .gt. 0) hbord(ifac) = hint


        !--> Rayonnement :

        if (iirayo.ge.1 .and. ii.eq.iscalt) then

          !                On calcule le coefficient d'echange en W/(m2 K)

          !                Si on resout en enthalpie
          if(iscsth(ii).eq.2) then
            !                  Si Cp variable
            if(ipccp.gt.0) then
              propfb(ifac,ipprob(ihconv)) = hint*propce(iel,ipccp )
            else
              propfb(ifac,ipprob(ihconv)) = hint*cp0
            endif
          elseif(iscsth(ii).eq.3) then
            !                    Si Cv variable
            if(ipccv.gt.0) then
              propfb(ifac,ipprob(ihconv)) = hint*propce(iel,ipccv )
            else
              propfb(ifac,ipprob(ihconv)) = hint*cv0
            endif
            !                Si on resout en temperature
          elseif(abs(iscsth(ii)).eq.1) then
            propfb(ifac,ipprob(ihconv)) = hint
          endif

          !              On recupere le flux h(Ti'-Tp) (sortant ou
          !                             negatif si gain pour le fluide)

          propfb(ifac,ipprob(ifconv)) = rcodcl(ifac,ivar,3)
        endif

      endif

    enddo

  enddo

endif

!===============================================================================
! 13.  VITESSE DE MAILLAGE EN ALE : DIRICHLET, NEUMANN
!===============================================================================
! (les conditions de glissement on ete traitees dans ALTYCL

if (iale.eq.1) then

  icluma = iclrtp(iuma ,icoef)
  iclvma = iclrtp(ivma ,icoef)
  iclwma = iclrtp(iwma ,icoef)

  do ifac = 1, nfabor

    iel = ifabor(ifac)
    distbf = distb(ifac)
    srfbn2 = surfbn(ifac)**2
    if (iortvm.eq.0) then
      hint = propce(iel,ipproc(ivisma(1)))/distbf
    else
      hint = ( propce(iel,ipproc(ivisma(1)))*surfbo(1,ifac)**2    &
             + propce(iel,ipproc(ivisma(2)))*surfbo(2,ifac)**2    &
             + propce(iel,ipproc(ivisma(3)))*surfbo(3,ifac)**2 )  &
           /distbf/srfbn2
    endif

    do ii = 1, 3
      if (ii.eq.1) ivar = iuma
      if (ii.eq.2) ivar = ivma
      if (ii.eq.3) ivar = iwma
      iclvar = iclrtp(ivar,icoef)

!      C.L DE TYPE DIRICHLET
      if( icodcl(ifac,ivar).eq.1 ) then
        hext = rcodcl(ifac,ivar,2)
        if(abs(hext).gt.rinfin*0.5d0) then
          pimp = rcodcl(ifac,ivar,1)
          coefa(ifac,iclvar) = pimp
          coefb(ifac,iclvar) = 0.d0
        else
          pimp = rcodcl(ifac,ivar,1)
          coefa(ifac,iclvar) = hext*pimp/(hint +hext)
          coefb(ifac,iclvar) = hint     /(hint +hext)
        endif

!      C.L DE TYPE FLUX
      elseif( icodcl(ifac,ivar).eq.3 ) then
        coefa(ifac,iclvar) = -rcodcl(ifac,ivar,3)/hint
        coefb(ifac,iclvar) = 1.d0
      endif

    enddo

    if (icodcl(ifac,iuma).eq.4) then
!     Face de glissement (si IUMA est de type 4, les autres aussi)
!     On force la vitesse de maillage normale a etre nulle, CL de Neumann
!       sur les autres composantes (calque sur CLSYVT). On prend directement
!       la valeur au centre de la cellule et pas reconstruite a la face (on
!       ne cherche pas une precision particuliere sur w)
      srfbnf = surfbn(ifac)
      rnx = surfbo(1,ifac)/srfbnf
      rny = surfbo(2,ifac)/srfbnf
      rnz = surfbo(3,ifac)/srfbnf
      upx = rtpa(iel,iuma)
      upy = rtpa(iel,ivma)
      upz = rtpa(iel,iwma)
      coefa(ifac,iuma) = - rnx*(rny*upy+rnz*upz)
      coefb(ifac,iuma) = 1.d0-rnx**2
      coefa(ifac,ivma) = - rny*(rnz*upz+rnx*upx)
      coefb(ifac,ivma) = 1.d0-rny**2
      coefa(ifac,iwma) = - rnz*(rnx*upx+rny*upy)
      coefb(ifac,iwma) = 1.d0-rnz**2
    endif

  enddo

endif

!===============================================================================
! 14.  CALCUL DES EFFORTS AUX BORDS (partie 1/5)
!===============================================================================

if (ineedf.eq.1) then
  iphas = 1
  do ifac = 1, nfabor
    iel = ifabor(ifac)
    visclc = propce(iel,ipproc(iviscl))
    visctc = propce(iel,ipproc(ivisct))
    if (itytur.eq.3) then
      vistot = visclc
    else
      vistot = visclc + visctc
    endif
    distbf = distb(ifac)
    srfbnf = surfbn(ifac)
    ra(iforbr+(ifac-1)*ndim)     = -vistot * ( coefa(ifac,icluf)  &
         + (coefb(ifac,icluf)-1.d0)*coefu(ifac,1) )/distbf*srfbnf
    ra(iforbr+(ifac-1)*ndim + 1) = -vistot * ( coefa(ifac,iclvf)  &
         + (coefb(ifac,iclvf)-1.d0)*coefu(ifac,2) )/distbf*srfbnf
    ra(iforbr+(ifac-1)*ndim + 2) = -vistot * ( coefa(ifac,iclwf)  &
         + (coefb(ifac,iclwf)-1.d0)*coefu(ifac,3) )/distbf*srfbnf
  enddo
endif

!===============================================================================
! 15.  FORMATS
!===============================================================================

#if defined(_CS_LANG_FR)

 1000 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ ATTENTION : ARRET LORS DE L''ENTREE DES COND. LIM.      ',/,&
'@    =========                                               ',/,&
'@      INCOHERENCE ENTRE OPTIONS DE CALCUL ET COND. LIM.     ',/,&
'@                                                            ',/,&
'@      la prise en compte des termes d''echo de paroi        ',/,&
'@      du modele de turbulence Rij-epsilon est activee       ',/,&
'@      IRIJEC = ',I10,'                                      ',/,&
'@      Ou bien l amortissement de la viscosite turbulente    ',/,&
'@      est active IDRIES = ',I10,'en LES                     ',/,&
'@    mais aucune face de bord de type paroi n''est detectee. ',/,&
'@    L''incoherence indiquee ci-dessus n''est pas bloquante  ',/,&
'@      mais peut resulter d''une erreur lors de la           ',/,&
'@      specification des conditions aux limites.             ',/,&
'@                                                            ',/,&
'@    Par securite, le calcul ne sera pas execute.            ',/,&
'@                                                            ',/,&
'@    Verifier les conditions aux limites dans usclim si le   ',/,&
'@      domaine comporte des parois.                          ',/,&
'@    Eliminer l''option IRIJEC de usini1 si le domaine ne    ',/,&
'@      comporte pas de paroi (ou conditions ICODCL = 5 en    ',/,&
'@      vitesse).                                             ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)
 3010 format(                                                           &
 'Debit entrant retenu en ',I10   ,                  &
                                      ' faces de sortie sur ',I10)
 8000 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ ATTENTION : COND. LIM.                                  ',/,&
'@    =========                                               ',/,&
'@     Le scalaire ',I10   ,' est couple a SYRTHES            ',/,&
'@      mais n''est pas la variable energetique               ',/,&
'@         ISCALT = ',I10                               ,/,&
'@                                                            ',/,&
'@     Le calcul ne sera pas execute.                         ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)

#else

 1000 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ WARNING: ABORT IN THE BOUNDARY CONDITIONS SPECIFICATION ',/,&
'@    =========                                               ',/,&
'@      INCOHERENCY BETWEEN CALCULATION OPTIONS AND BOUND COND',/,&
'@                                                            ',/,&
'@      The wall-echo terms of the Rij-epsilon turbulence     ',/,&
'@      model are taken into account                          ',/,&
'@      IRIJEC = ',I10,'                                      ',/,&
'@      Or the Van Driest damping of the turbulent viscosity  ',/,&
'@      is active IDRIES = ',I10,'in LES                      ',/,&
'@    but no wall boundary face is detected.                  ',/,&
'@    This incoherency is not blocking but may result from    ',/,&
'@      an error during the boundary conditions               ',/,&
'@      specification.                                        ',/,&
'@                                                            ',/,&
'@    By safety, the calculation will not be run.             ',/,&
'@                                                            ',/,&
'@    Verify the boundary conditions in usclim if the domain  ',/,&
'@      has any walls.                                        ',/,&
'@    Remove the option IRIJEC from usini1 if the domain does ',/,&
'@      not have any wall (or conditions ICODCL = 5 for the   ',/,&
'@      velocity).                                            ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)
 3010 format(                                                           &
 'Incoming flow detained for ', I10   ,              &
                                          ' outlet faces on ',I10)
 8000 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ WARNING: BOUNDARY CONDITIONS                            ',/,&
'@    ========                                                ',/,&
'@     The scalar ',I10   ,' is coupled with SYRTHES          ',/,&
'@      but is not the energy variable                        ',/,&
'@         ISCALT = ',I10                               ,/,&
'@                                                            ',/,&
'@     The calculation will not be run.                       ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)

#endif

!----
! FIN
!----

return
end subroutine
