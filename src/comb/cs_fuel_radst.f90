!-------------------------------------------------------------------------------

! This file is part of Code_Saturne, a general-purpose CFD tool.
!
! Copyright (C) 1998-2012 EDF S.A.
!
! This program is free software; you can redistribute it and/or modify it under
! the terms of the GNU General Public License as published by the Free Software
! Foundation; either version 2 of the License, or (at your option) any later
! version.
!
! This program is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
! details.
!
! You should have received a copy of the GNU General Public License along with
! this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
! Street, Fifth Floor, Boston, MA 02110-1301, USA.

!-------------------------------------------------------------------------------

subroutine cs_fuel_radst &
!=======================
  ( ivar   , ncelet , ncel   ,                                    &
    volume , rtpa   , propce , smbrs  , rovsdt )


!===============================================================================
!  FONCTION  :
!  ---------

! ROUTINE PHYSIQUE PARTICULIERE : FLAMME CHARBON PULVERISE
!   PRISE EN COMPTE DES TERMES SOURCES RADIATIFS
!   IMPLICITE ET EXPLICITE DANS L'EQUATION DES PARTICULES
!   DE LA CLASSE ICLA

!-------------------------------------------------------------------------------
! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! ivar             ! e  ! <-- ! numero de la variable scalaire                 !
!                  !    !     !   energie (enthalpie h2) pour le               !
!                  !    !     !   charbon                                      !
! ncelet           ! i  ! <-- ! number of extended (real + ghost) cells        !
! ncel             ! i  ! <-- ! number of cells                                !
! volume(ncelet    ! tr ! <-- ! volume des cellules                            !
! rtp, rtpa        ! ra ! <-- ! calculated variables at cell centers           !
!  (ncelet, *)     !    !     !  (at current and previous time steps)          !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! smbrs(ncelet     ! tr ! <-- ! second membre du systeme                       !
! rovsdt(ncelet    ! tr ! <-- ! diagonale du systeme                           !
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
use cstnum
use cstphy
use entsor
use numvar
use ppppar
use ppthch
use ppincl
use radiat

!===============================================================================

implicit none

! Arguments

integer          ivar , ncelet, ncel

double precision volume(ncelet)
double precision smbrs(ncelet)
double precision rovsdt(ncelet)
double precision rtpa(ncelet,*)
double precision propce(ncelet,*)

! Local variables

integer          iel , numcla , ipcl

!===============================================================================

!===============================================================================
! 1. RECHERCHE DE LA ZONE MEMOIRE POUR TROUVER LES BONS TERMES SOURCES
!===============================================================================

numcla = ivar-isca(ih2(1))+1
ipcl   = 1+numcla

!===============================================================================
! 2. PRISE EN COMPTE DES TERMES SOURCES RADIATIFS
!===============================================================================


do iel = 1,ncel
  propce(iel,ipproc(itsri(ipcl))) = max(-propce(iel,ipproc(itsri(ipcl))),zero)
enddo

do iel = 1,ncel
  if ( propce(iel,ipproc(iyfol(numcla))) .gt. epzero ) then

!--> PARTIE EXPLICITE

    smbrs(iel)  = smbrs(iel) +  propce(iel,ipproc(itsre(ipcl)))*volume(iel)  &
                               *rtpa(iel,isca(iyfol(numcla)))

!--> PARTIE IMPLICITE

    rovsdt(iel) = rovsdt(iel) + propce(iel,ipproc(itsri(ipcl)))*volume(iel)
  endif

enddo


!----
! End
!----

return

end subroutine
