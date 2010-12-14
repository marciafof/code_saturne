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

subroutine vorpre &
!================

 ( idbia0 , idbra0 , ifinia , ifinra ,                            &
   nvar   , nscal  , nphas  ,                                     &
   nideve , nrdeve , nituse , nrtuse ,                            &
   irepvo ,                                                       &
   idevel , ituser , ia     ,                                     &
   propce , propfa , propfb ,                                     &
   rdevel , rtuser , ra     )

!===============================================================================
! FONCTION :
! --------

!    ROUTINE DE PREPATATION DE LA METHODE DES VORTEX
!    Gestion memoire, connectivites, ...
!-------------------------------------------------------------------------------
! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! idbia0           ! i  ! <-- ! number of first free position in ia            !
! idbra0           ! i  ! <-- ! number of first free position in ra            !
! ifinia           ! i  ! --> ! number of first free position in ia (at exit)  !
! ifinra           ! i  ! --> ! number of first free position in ra (at exit)  !
! nvar             ! i  ! <-- ! total number of variables                      !
! nscal            ! i  ! <-- ! total number of scalars                        !
! nphas            ! i  ! <-- ! number of phases                               !
! nideve, nrdeve   ! i  ! <-- ! sizes of idevel and rdevel arrays              !
! nituse, nrtuse   ! i  ! <-- ! sizes of ituser and rtuser arrays              !
! idevel(nideve)   ! ia ! <-> ! integer work array for temporary development   !
! irepvo           ! te ! <-- ! tab entier pour reperage des faces de          !
!                  !    !     ! bord pour la methode des vortex                !
! ituser(nituse)   ! ia ! <-> ! user-reserved integer work array               !
! ia(*)            ! ia ! --- ! main integer work array                        !
! dt(ncelet)       ! ra ! <-- ! time step (per cell)                           !
! rtp, rtpa        ! ra ! <-- ! calculated variables at cell centers           !
!  (ncelet, *)     !    !     !  (at current and previous time steps)          !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! propfa(nfac, *)  ! ra ! <-- ! physical properties at interior face centers   !
! propfb(nfabor, *)! ra ! <-- ! physical properties at boundary face centers   !
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
use pointe
use numvar
use optcal
use cstphy
use cstnum
use entsor
use parall
use period
use vorinc
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0 , ifinia , ifinra
integer          nvar   , nscal  , nphas
integer          nideve , nrdeve , nituse , nrtuse

integer          irepvo(nfabor)
integer          idevel(nideve), ituser(nituse), ia(*)

double precision propce(ncelet,*)
double precision propfa(nfac,*), propfb(nfabor,*)
double precision rdevel(nrdeve), rtuser(nrtuse), ra(*)

! Local variables

integer          idebia, idebra
integer          ifac, iel, ii, iphas
integer          ient, ipcvis, ipcrom
integer          iappel
integer          isurf(nentmx)
double precision xx, yy, zz
double precision xxv, yyv, zzv

!===============================================================================
! 1.  INITIALISATIONS
!===============================================================================

idebia = idbia0
idebra = idbra0

nvomax = 0
do ient = 1, nnent
  nvomax = max(nvort(ient),nvomax)
enddo

! NVOMAX = nombre max de vortex (utilise plus tard)

do ient = 1, nnent
  icvor2(ient) = 0
enddo

do ifac = 1, nfabor
  ient = irepvo(ifac)
  if(ient.ne.0) then
    icvor2(ient) = icvor2(ient) + 1
  endif
enddo

! ICVOR2 = compteur du nombre local de faces
!   utilisant des vortex a l'entree IENT

icvmax = 0
if(irangp.ge.0) then
  do ient = 1, nnent
    icvor(ient) = icvor2(ient)
    call parcpt(icvor(ient))
    !==========
    icvmax = max(icvmax,icvor(ient))
  enddo
else
  do ient = 1, nnent
    icvor(ient) = icvor2(ient)
    icvmax = max(icvmax,icvor(ient))
  enddo
endif

! ICVOR = nombre global de faces utilisant des vortex a l'entree IENT

! ICVMAX = max du nombre global de faces utilisant des vortex
! (toutes entrees confondues).

iappel = 2
call memvor                                                       &
!==========
 ( idebia , idebra , iappel , nfabor , ifinia , ifinra )

idebia = ifinia
idebra = ifinra

!===============================================================================
! 2. CONSTRUCTION DE LA " GEOMETRIE GOBALE "
!===============================================================================

do ient = 1, nnent
  icvor2(ient) = 0
  xsurfv(ient) = 0.d0
  isurf(ient)  = 0
enddo

! Chaque processeur stocke dans les tableaux RA(IW1X),...
! les coordonnees des faces ou il doit ensuite utiliser des vortex

iphas  = 1
ipcvis = ipproc(iviscl(iphas))
ipcrom = ipproc(irom(iphas))
do ifac = 1, nfabor
  ient = irepvo(ifac)
  if(ient.ne.0) then
    iel = ifabor(ifac)
    icvor2(ient) = icvor2(ient) + 1
    ra(iw1x+(ient-1)*icvmax+icvor2(ient)-1)= cdgfbo(1,ifac)
    ra(iw1y+(ient-1)*icvmax+icvor2(ient)-1)= cdgfbo(2,ifac)
    ra(iw1z+(ient-1)*icvmax+icvor2(ient)-1)= cdgfbo(3,ifac)
    ra(iw1v+(ient-1)*icvmax+icvor2(ient)-1) =                     &
      propce(iel,ipcvis)/propce(iel,ipcrom)
    xsurfv(ient) = xsurfv(ient) + sqrt(surfbo(1,ifac)**2          &
      + surfbo(2,ifac)**2 + surfbo(3,ifac)**2)
!         Vecteur surface d'une face de l'entree
    if (isurf(ient).eq.0) then
      surf(1,ient) = surfbo(1,ifac)
      surf(2,ient) = surfbo(2,ifac)
      surf(3,ient) = surfbo(3,ifac)
      isurf(ient)  = 1
    endif
  endif
enddo

if(irangp.ge.0) then
  do ient = 1, nnent
    call parsom(xsurfv(ient))
    !==========
  enddo
endif

! -------------
! En parallele
! -------------
if(irangp.ge.0) then
  do ient = 1, nnent
    call paragv                                                   &
    !==========
 ( icvor2(ient), icvor(ient),                                     &
   ra(iw1x  + (ient-1)*icvmax)   ,                                &
   ra(ixyzv + (ient-1)*3*icvmax) )
    call paragv                                                   &
    !==========
 ( icvor2(ient), icvor(ient),                                     &
   ra(iw1y  + (ient-1)*icvmax)              ,                     &
   ra(ixyzv + (ient-1)*3*icvmax +   icvmax) )
    call paragv                                                   &
    !==========
 ( icvor2(ient), icvor(ient),                                     &
   ra(iw1z  + (ient-1)*icvmax)              ,                     &
   ra(ixyzv + (ient-1)*3*icvmax + 2*icvmax) )
    call paragv                                                   &
    !==========
 ( icvor2(ient), icvor(ient),                                     &
   ra(iw1v  + (ient-1)*icvmax)   ,                                &
   ra(ivisv + (ient-1)*3*icvmax) )
  enddo

!  -> A la fin de cette etape, tous les processeurs connaissent
!     les coordonees des faces d'entree

else
! ----------------------
! Sur 1 seul processeur
! ----------------------
  do ient = 1,nnent
    do ii = 1, icvor(ient)
      ra(ixyzv+(ient-1)*3*icvmax+ii-1)=                           &
           ra(iw1x+(ient-1)*icvmax + ii -1)
      ra(ixyzv+(ient-1)*3*icvmax+icvmax + ii-1) =                 &
           ra(iw1y+(ient-1)*icvmax + ii -1)
      ra(ixyzv+(ient-1)*3*icvmax+2*icvmax + ii-1) =               &
           ra(iw1z+(ient-1)*icvmax + ii -1)
      ra(ivisv+(ient-1)*icvmax+ii-1) =                            &
           ra(iw1v+(ient-1)*icvmax+ii-1)
    enddo
  enddo
endif

!===============================================================================
! 3. CONSTRUCTION DE LA CONNECTIVITE
!===============================================================================

do ient = 1, nnent
  icvor2(ient) = 0
  do ifac = 1, icvmax
    ia(iifagl+(ient-1)*icvmax+ifac-1) = 0
  enddo
enddo

! On cherche ensuite le numero de la ligne du tableau RA(IXYZV) qui est
! associe a la Ieme face d'entree utilisant des vortex (dans la
! numerotation chronologique que suit ICVOR2).

do ifac = 1, nfabor
  ient = irepvo(ifac)
  if(ient.ne.0) then
    icvor2(ient) = icvor2(ient) + 1
    do ii = 1, icvor(ient)
      xx = cdgfbo(1,ifac)
      yy = cdgfbo(2,ifac)
      zz = cdgfbo(3,ifac)
      xxv = ra(ixyzv+(ient-1)*3*icvmax+ii-1)
      yyv = ra(ixyzv+(ient-1)*3*icvmax+icvmax+ii-1)
      zzv = ra(ixyzv+(ient-1)*3*icvmax+2*icvmax+ii-1)
      if(abs(xxv-xx).lt.epzero.and.abs(yyv-yy).lt.epzero.and.     &
           abs(zzv-zz).lt.epzero) then
        ia(iifagl+(ient-1)*icvmax+icvor2(ient)-1) = ii
      endif
    enddo
  endif
enddo

! La methode de vortex va generer un tableau de vitesse RA(IUVOR)
! qui aura la meme structure que RA(IXYZV).
! Le tableau RA(IXYZV) sera envoyee a tous les processeurs
! la vitesse a imposer � la Ieme face se trouvera � la ligne IA(IIFAGL+I)

iappel = 3
call memvor                                                       &
!==========
 ( idebia , idebra , iappel , nfabor , ifinia , ifinra )

! ---
! FIN
! ---

return
end subroutine
