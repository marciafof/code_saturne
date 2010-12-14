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

subroutine mtproj &
!================

 ( idbia0 , idbra0 ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   nbpmax , nvp    , nvep   , nivep  , ntersl , nvlsta , nvisbr , &
   nideve , nrdeve , nituse , nrtuse ,                            &
   itepa  ,                                                       &
   idevel , ituser , ia     ,                                     &
   dt     , rtpa   , rtp    , propce , propfa , propfb ,          &
   coefa  , coefb  ,                                              &
   ettp   , ettpa  , tepa   , statis , tslagr , parbor ,          &
   rdevel , rtuser , ra     )

!===============================================================================
! FONCTION :
! --------

! MODIFICATION UTILISATEUR EN FIN DE PAS DE TEMPS POUR MATISSE

!  COPIE ET SPECIALISATION DE USPROJ

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
! nbpmax           ! e  ! <-- ! nombre max de particules autorise              !
! nvp              ! e  ! <-- ! nombre de variables particulaires              !
! nvep             ! e  ! <-- ! nombre info particulaires (reels)              !
! nivep            ! e  ! <-- ! nombre info particulaires (entiers)            !
! ntersl           ! e  ! <-- ! nbr termes sources de couplage retour          !
! nvlsta           ! e  ! <-- ! nombre de var statistiques lagrangien          !
! nvisbr           ! e  ! <-- ! nombre de statistiques aux frontieres          !
! nideve, nrdeve   ! i  ! <-- ! sizes of idevel and rdevel arrays              !
! nituse, nrtuse   ! i  ! <-- ! sizes of ituser and rtuser arrays              !
! itepa            ! te ! <-- ! info particulaires (entiers)                   !
! (nbpmax,nivep    !    !     !   (cellule de la particule,...)                !
! idevel(nideve)   ! ia ! <-> ! integer work array for temporary development   !
! ituser(nituse)   ! ia ! <-> ! user-reserved integer work array               !
! ia(*)            ! ia ! --- ! main integer work array                        !
! dt(ncelet)       ! ra ! <-- ! time step (per cell)                           !
! rtp, rtpa        ! ra ! <-- ! calculated variables at cell centers           !
!  (ncelet, *)     !    !     !  (at current and previous time steps)          !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! propfa(nfac, *)  ! ra ! <-- ! physical properties at interior face centers   !
! propfb(nfabor, *)! ra ! <-- ! physical properties at boundary face centers   !
! coefa, coefb     ! ra ! <-- ! boundary conditions                            !
!  (nfabor, *)     !    !     !                                                !
! ettp             ! tr ! <-- ! tableaux des variables liees                   !
!  (nbpmax,nvp)    !    !     !   aux particules etape courante                !
! ettpa            ! tr ! <-- ! tableaux des variables liees                   !
!  (nbpmax,nvp)    !    !     !   aux particules etape precedente              !
! tepa             ! tr ! <-- ! info particulaires (reels)                     !
! (nbpmax,nvep)    !    !     !   (poids statistiques,...)                     !
! statis           ! tr ! <-- ! moyennes statistiques                          !
!(ncelet,nvlsta    !    !     !                                                !
! tslagr           ! tr ! <-- ! terme de couplage retour du                    !
!(ncelet,ntersl    !    !     !   lagrangien sur la phase porteuse             !
! parbor           ! tr ! <-- ! infos sur interaction des particules           !
!(nfabor,nvisbr    !    !     !   aux faces de bord                            !
! rdevel(nrdeve)   ! ra ! <-> ! real work array for temporary development      !
! rtuser(nrtuse)   ! ra ! <-> ! user-reserved real work array                  !
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
use pointe
use numvar
use optcal
use cstphy
use cstnum
use entsor
use parall
use period
use matiss
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0
integer          nvar   , nscal  , nphas
integer          nbpmax , nvp    , nvep   , nivep
integer          ntersl , nvlsta , nvisbr
integer          nideve , nrdeve , nituse , nrtuse

integer          itepa(nbpmax,nivep)
integer          idevel(nideve), ituser(nituse)
integer          ia(*)

double precision dt(ncelet), rtp(ncelet,*), rtpa(ncelet,*)
double precision propce(ncelet,*)
double precision propfa(nfac,*), propfb(ndimfb,*)
double precision coefa(ndimfb,*), coefb(ndimfb,*)
double precision ettp(nbpmax,nvp) , ettpa(nbpmax,nvp)
double precision tepa(nbpmax,nvep)
double precision statis(ncelet,nvlsta) , tslagr(ncelet,ntersl)
double precision parbor(nfabor,nvisbr)
double precision rdevel(nrdeve), rtuser(nrtuse), ra(*)

! Local variables

integer          idebia , idebra
integer          iel    , ifac   , ifml   , icoul
integer          iphas  , iuiph  , iflmab
double precision ts0    , vs0    , taamax , tpcmax , tppmax
double precision flmass , bilent , potflo

!===============================================================================
! 1. INITIALISATION
!===============================================================================

! --- Gestion memoire

idebia = idbia0
idebra = idbra0

! --- Une seule phase

iphas = 1

!===============================================================================
! 1. AFFICHAGES
!===============================================================================


! --- Affichages au dernier pas de temps seulement

if (ntmabs .eq. ntcabs) then

! --- Nombre de Richardson : calcul et affichage par
!       . mtimpi en convection forcee
!       . mttsns en convection naturelle


! --- Puissance totale
  if (irangp.le.0) then
    write(impmat,1001) puitot
  endif


! --- Debit enthalpique
  if (irangp.le.0) then
    write(impmat,1002) debcon
  endif


! --- Coeff d'echange
  if (irangp.le.0) then
    write(impmat,1011) cfecca
    write(impmat,1012) cfecma
  endif

! --- Bilan masse en sortie
!       (la correction par FRDTRA est la correction correspondant
!        au rapport d'echelle transverse entre le reel et le modele)
  iuiph  = iu(iphas)
  iflmab = ipprob(ifluma(iuiph))
  flmass = 0.d0
  do ifac = 1, nfabor
    ifml  = ifmfbr(ifac)
    icoul = iprfml(ifml,1)
    if (icoul.eq.icmtfo) then
      flmass = flmass + propfb(ifac,iflmab)
    endif
  enddo
  flmass = flmass * frdtra
  if (irangp.ge.0) call parsom(flmass)

  if (irangp.le.0) then
    write(impmat,1021) flmass
  endif

! --- Temperature moyenne dans la cheminee d'evacuation
!     (scalaire 1)
  ts0 = 0.d0
  vs0 = 0.d0
  do iel = 1, ncel
    ifml  = ifmcel(iel   )
    icoul = iprfml(ifml,1)
    if(icoul.eq.icmtco) then
      ts0 = ts0 + volume(iel)*rtp(iel,isca(itaamt))
      vs0 = vs0 + volume(iel)
    endif
  enddo
  ts0 = ts0/max(vs0,epzero)
  if (irangp.le.0) then
    write(impmat,1022) ts0
  endif


! --- Calcul du bilan enthalpique en pourcentage
!       On calcule le rapport de rhoUS * Cp * Delta T (Watt)
!         a PUITOT (multiplication par 1.D3 car PUITOT est en kW,
!         division par 100 pour obtenir une donnee en %)
!       L'ecart de temperature est pris comme l'ecart entre la
!         temperature de sortie TS0 et la temperature d'entree TINIT
  bilent =                                                        &
       cp0(iphas)*flmass*(ts0-tinit)/(puitot*1.d3)*100.d0
  if (irangp.le.0) then
    write(impmat,1031) bilent
  endif


! --- Calcul du potentiel de flottabilite
!       Calcul de delta_rho * g * delta_h en Pascal avec, a pression
!         constante : delta_rho = rho_ref/T_ref * delta_T
!         D'ou POTFLO = rho_ref/T_ref * delta_T * g * Delta_h
!       L'ecart de temperature est pris comme l'�cart entre la
!         temperature de sortie TS0 et la temperature d'entree TINIT
!       L'ecart de hauteur est pris entre le haut de la cheminee de
!         sortie et la mi hauteur de la zone de stockage (z=0 au sol)
  potflo = rrfmat/(trfmat+tkelvi)*(ts0-tinit)                     &
       * sqrt(gx**2+gy**2+gz**2)*(hcheva-0.5d0*epchel*nchest)
  if (irangp.le.0) then
    write(impmat,1032) potflo
  endif


! --- Calcul des max des scalaires
!     . TAA* : Temperature Air Ambiant (scalaire ITAAMT)
!     . TPC* : Temperature Peau Colis  (scalaire ITPCMT)
!     . TPP* : Temperature Peau Paroi  (scalaire ITPPMT)

  taamax = 0.d0
  tpcmax = 0.d0
  tppmax = 0.d0

  do iel = 1, ncel
    taamax = max(taamax , rtp(iel,isca(itaamt)))
    tpcmax = max(tpcmax , rtp(iel,isca(itpcmt)))
    tppmax = max(tppmax , rtp(iel,isca(itppmt)))
  enddo

  if (irangp.ge.0) then
    call parmax(taamax)
    call parmax(tpcmax)
    call parmax(tppmax)
  endif

  if (irangp.le.0) then
    write(impmat,1041) taamax
    write(impmat,1042) tpcmax
    write(impmat,1043) tppmax
  endif

  close(impmat)

!       Fin du test sur NTCABS
endif


!--------
! FORMATS
!--------


 1001 format(' Puissance totale de l''installation                   ', &
'  :',E12.5, ' kW')
 1002 format(' Debit enthalpique vers le ciel de l''entrepot         ', &
'  :',E12.5, ' kW')

 1011 format(' Coefficient d''echange moyen conteneur/air            ', &
'  :',E12.5,' W/m2/C')
 1012 format(' Coefficient d''echange moyen mur/air                  ', &
'  :',E12.5,' W/m2/C')

 1021 format(' Debit masse de circulation d''air                     ', &
'  :',E12.5, ' kg/s')
 1022 format(' Temperature d''air en sortie                          ', &
'  :',E12.5, ' �C')

 1031 format(' Bilan enthalpique                                    ',  &
'  :',E12.5, ' %')
 1032 format(' Potentiel de flottabilite                            ',  &
'  :',E12.5, ' Pa')

 1041 format(' Temperature maximale d''air ambiant                   ', &
'  :',E12.5, ' �C')
 1042 format(' Temperature maximale des conteneurs                  ',  &
'  :',E12.5, ' �C')
 1043 format(' Temperature maximale des murs                        ',  &
'  :',E12.5, ' �C')

return
end subroutine
