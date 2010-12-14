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

subroutine vislmg &
!================

 ( idbia0 , idbra0 ,                                              &
   nvar   , nscal  , nphas  , ncepdp , ncesmp ,                   &
   nideve , nrdeve , nituse , nrtuse , iphas  ,                   &
   icepdc , icetsm , itypsm ,                                     &
   idevel , ituser , ia     ,                                     &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   coefa  , coefb  , ckupdc , smacel ,                            &
   w1     , w2     , w3     , w4     ,                            &
   w5     , w6     , w7     , w8     ,                            &
   rdevel , rtuser , ra     )

!===============================================================================
! FONCTION :
! --------

! CALCUL DE LA VISCOSITE TURBULENTE POUR
!          UN MODELE DE LONGUEUR DE MELANGE SIMPLE

! VISCT = ROM * (XKAPPA * L) **2 * SQRT ( 2 * Sij.Sij )
!       Sij = (DUi/Dxj + DUj/Dxi)/2

! On dispose des types de faces de bord au pas de temps
!   precedent (sauf au premier pas de temps, ou les tableaux
!   ITYPFB et ITRIFB n'ont pas ete renseignes)

! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! idbia0           ! i  ! <-- ! number of first free position in ia            !
! idbra0           ! i  ! <-- ! number of first free position in ra            !
! nvar             ! i  ! <-- ! total number of variables                      !
! nscal            ! i  ! <-- ! total number of scalars                        !
! nphas            ! i  ! <-- ! number of phases                               !
! ncepdp           ! i  ! <-- ! number of cells with head loss                 !
! ncesmp           ! i  ! <-- ! number of cells with mass source term          !
! nideve, nrdeve   ! i  ! <-- ! sizes of idevel and rdevel arrays              !
! nituse, nrtuse   ! i  ! <-- ! sizes of ituser and rtuser arrays              !
! iphas            ! i  ! <-- ! phase number                                   !
! icepdc(ncelet    ! te ! <-- ! numero des ncepdp cellules avec pdc            !
! icetsm(ncesmp    ! te ! <-- ! numero des cellules a source de masse          !
! itypsm           ! te ! <-- ! type de source de masse pour les               !
! (ncesmp,nvar)    !    !     !  variables (cf. ustsma)                        !
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
! ckupdc           ! tr ! <-- ! tableau de travail pour pdc                    !
!  (ncepdp,6)      !    !     !                                                !
! smacel           ! tr ! <-- ! valeur des variables associee a la             !
! (ncesmp,*   )    !    !     !  source de masse                               !
!                  !    !     !  pour ivar=ipr, smacel=flux de masse           !
! w1...8(ncelet    ! tr ! --- ! tableau de travail                             !
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
use numvar
use optcal
use cstphy
use entsor
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0
integer          nvar   , nscal  , nphas
integer          ncepdp , ncesmp
integer          nideve , nrdeve , nituse , nrtuse , iphas

integer          icepdc(ncepdp)
integer          icetsm(ncesmp), itypsm(ncesmp,nvar)
integer          idevel(nideve), ituser(nituse)
integer          ia(*)

double precision dt(ncelet), rtp(ncelet,*), rtpa(ncelet,*)
double precision propce(ncelet,*)
double precision propfa(nfac,*), propfb(ndimfb,*)
double precision coefa(ndimfb,*), coefb(ndimfb,*)
double precision ckupdc(ncepdp,6), smacel(ncesmp,nvar)
double precision w1(ncelet),w2(ncelet),w3(ncelet),w4(ncelet)
double precision w5(ncelet),w6(ncelet),w7(ncelet),w8(ncelet)
double precision rdevel(nrdeve), rtuser(nrtuse), ra(*)

! Local variables

integer          idebia, idebra
integer          iel, iccocg, inc, iphydp
integer          iuiph, iviph, iwiph
integer          ipcliu, ipcliv, ipcliw
integer          ipcrom, ipcvst
double precision coef, deux
double precision s11, s22, s33
double precision dudy, dudz, dvdx, dvdz, dwdx, dwdy

!===============================================================================

!===============================================================================
! 1.  INITIALISATION
!===============================================================================

! --- Memoire
idebia = idbia0
idebra = idbra0

! --- Numero des variables (dans RTP)
iuiph = iu(iphas)
iviph = iv(iphas)
iwiph = iw(iphas)

! --- Rang des variables dans PROPCE (prop. physiques au centre)
ipcvst = ipproc(ivisct(iphas))
ipcrom = ipproc(irom  (iphas))

! --- Rang des c.l. des variables dans COEFA COEFB
!        (c.l. std, i.e. non flux)
ipcliu = iclrtp(iuiph,icoef)
ipcliv = iclrtp(iviph,icoef)
ipcliw = iclrtp(iwiph,icoef)

!===============================================================================
! 2.  CALCUL DES GRADIENTS DE VITESSE ET DE
!       S11**2+S22**2+S33**2+2*(S12**2+S13**2+S23**2)
!===============================================================================

iccocg = 1
inc = 1
iphydp = 0

! W1 = DUDX, W2 = DUDY, W3=DUDZ

call grdcel                                                       &
!==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   nideve , nrdeve , nituse , nrtuse ,                            &
   iuiph  , imrgra , inc    , iccocg ,                            &
   nswrgr(iuiph) , imligr(iuiph) , iphydp , iwarni(iuiph) ,       &
   nfecra , epsrgr(iuiph) , climgr(iuiph) , extrag(iuiph) ,       &
   idevel , ituser , ia     ,                                     &
   w6     , w6     , w6     ,                                     &
   rtpa(1,iuiph) , coefa(1,ipcliu) , coefb(1,ipcliu) ,            &
   w1     , w2     , w3     ,                                     &
!        ------   ------   ------
   w6     , w7     , w8     ,                                     &
   rdevel , rtuser , ra     )

do iel = 1, ncel
  s11  = w1(iel)
  propce(iel,ipcvst) = s11**2
enddo


!            W2 = DUDY, W3=DUDZ
! W4 = DVDX, W1 = DVDY, W5=DVDZ

call grdcel                                                       &
!==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   nideve , nrdeve , nituse , nrtuse ,                            &
   iviph  , imrgra , inc    , iccocg ,                            &
   nswrgr(iviph) , imligr(iviph) , iphydp , iwarni(iviph) ,       &
   nfecra , epsrgr(iviph) , climgr(iviph) , extrag(iviph) ,       &
   idevel , ituser , ia     ,                                     &
   w6     , w6     , w6     ,                                     &
   rtpa(1,iviph) , coefa(1,ipcliv) , coefb(1,ipcliv) ,            &
   w4     , w1     , w5     ,                                     &
!        ------   ------   ------
   w6     , w7     , w8     ,                                     &
   rdevel , rtuser , ra     )

do iel = 1, ncel
  s22 = w1(iel)
  propce(iel,ipcvst) = propce(iel,ipcvst) + s22**2
enddo
do iel = 1, ncel
  dudy = w2(iel)
  dvdx = w4(iel)
  propce(iel,ipcvst) = propce(iel,ipcvst) + 0.5d0*(dudy+dvdx)**2
enddo


!                       W3=DUDZ
!            W1 = DVDY, W5=DVDZ
! W2 = DWDX, W4 = DWDY, W1=DWDZ

call grdcel                                                       &
!==========
 ( idebia , idebra ,                                              &
   nphas  ,                                                       &
   nideve , nrdeve , nituse , nrtuse ,                            &
   iwiph  , imrgra , inc    , iccocg ,                            &
   nswrgr(iwiph) , imligr(iwiph) , iphydp , iwarni(iwiph) ,       &
   nfecra , epsrgr(iwiph) , climgr(iwiph) , extrag(iwiph) ,       &
   idevel , ituser , ia     ,                                     &
   w6     , w6     , w6     ,                                     &
   rtpa(1,iwiph) , coefa(1,ipcliw) , coefb(1,ipcliw) ,            &
   w2     , w4     , w1     ,                                     &
!        ------   ------   ------
   w6     , w7     , w8     ,                                     &
   rdevel , rtuser , ra     )

do iel = 1, ncel
  s33 = w1(iel)
  propce(iel,ipcvst) = propce(iel,ipcvst) + s33**2
enddo
do iel = 1, ncel
  dudz = w3(iel)
  dwdx = w2(iel)
  dvdz = w5(iel)
  dwdy = w4(iel)
  propce(iel,ipcvst) =                                            &
    propce(iel,ipcvst) + 0.5d0*((dudz+dwdx)**2+(dvdz+dwdy)**2)
enddo


!===============================================================================
! 3.  CALCUL DE LA VISCOSITE (DYNAMIQUE)
!===============================================================================

deux = 2.d0
coef = (xkappa*xlomlg(iphas))**2 * sqrt(deux)

do iel = 1, ncel
  propce(iel,ipcvst) =                                            &
    propce(iel,ipcrom) * coef * sqrt(propce(iel,ipcvst))
enddo


!----
! FORMAT
!----


!----
! FIN
!----

return
end subroutine
