!-------------------------------------------------------------------------------

!VERS


!     This file is part of the Code_Saturne Kernel, element of the
!     Code_Saturne CFD tool.

!     Copyright (C) 1998-2008 EDF S.A., France

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

subroutine usiniv &
!================

 ( idbia0 , idbra0 ,                                              &
   nvar   , nscal  , nphas  ,                                     &
   nideve , nrdeve , nituse , nrtuse ,                            &
   maxelt , lstelt ,                                              &
   idevel , ituser , ia     ,                                     &
   dt     , rtp    , propce , propfa , propfb , coefa  , coefb  , &
   rdevel , rtuser , ra     )

!===============================================================================
! Purpose:
! -------

!    User subroutine.

!    Initialize variables

! This subroutine is called at beginning of the computation
! (restart or not) before the loop time step

! This subroutine enables to initialize or modify (for restart)
!     unkown variables and time step values

! rom and viscl values are equal to ro0 and viscl0 or initialize
! by reading the restart file
! viscls and cp variables (when there are defined) have no value
! excepted if they are read from a restart file

! Physical quantities are defined in the following arrays:
!  propce (physical quantities defined at cell center),
!  propfa (physical quantities defined at interior face center),
!  propfa (physical quantities defined at border face center).
!
! Examples:
!  propce(iel, ipproc(irom  (iphas))) means rom  (iel, iphas)
!  propce(iel, ipproc(iviscl(iphas))) means viscl(iel, iphas)
!  propce(iel, ipproc(icp   (iphas))) means cp   (iel, iphas)
!  propce(iel, ipproc(ivisls(iscal))) means visls(iel, iscal)
!  propfa(ifac, ipprof(ifluma(ivar))) means flumas(ifac, ivar)
!  propfb(ifac, ipprob(irom (iphas))) means romb  (ifac, iphas)
!  propfb(ifac, ipprob(ifluma(ivar))) means flumab(ifac, ivar)

! Modification of the behaviour law of physical quantities (rom, viscl,
! viscls, cp) is not done here. It is the purpose of the user subroutine
! usphyv

! Cells identification
! ====================

! Cells may be identified using the 'getcel' subroutine.
! The syntax of this subroutine is described in the 'usclim' subroutine,
! but a more thorough description can be found in the user guide.


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
! nideve, nrdeve   ! i  ! <-- ! sizes of idevel and rdevel arrays              !
! nituse, nrtuse   ! i  ! <-- ! sizes of ituser and rtuser arrays              !
! maxelt           ! i  ! <-- ! max number of cells and faces (int/boundary)   !
! lstelt(maxelt)   ! ia ! --- ! work array                                     !
! idevel(nideve)   ! ia ! <-> ! integer work array for temporary development   !
! ituser(nituse)   ! ia ! <-> ! user-reserved integer work array               !
! ia(*)            ! ia ! --- ! main integer work array                        !
! dt(ncelet)       ! ra ! <-- ! time step (per cell)                           !
! rtp(ncelet, *)   ! ra ! <-- ! computed variables at cell centers at current  !
!                  !    !     ! time steps                                     !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! propfa(nfac, *)  ! ra ! <-- ! physical properties at interior face centers   !
! propfb(nfabor, *)! ra ! <-- ! physical properties at boundary face centers   !
! coefa, coefb     ! ra ! <-- ! boundary conditions                            !
!  (nfabor, *)     !    !     !                                                !
! rdevel(nrdeve)   ! ra ! <-> ! real work array for temporary development      !
! rtuser(nrtuse)   ! ra ! <-> ! user-reserved real work array                  !
! ra(*)            ! ra ! --- ! main real work array                           !
!__________________!____!_____!________________________________________________!

!     Type: i (integer), r (real), s (string), a (array), l (logical),
!           and composite types (ex: ra real array)
!     mode: <-- input, --> output, <-> modifies data, --- work array
!===============================================================================

!===============================================================================
! Module files
!===============================================================================

use paramx
use pointe
use numvar
use optcal
use cstphy
use entsor
use parall
use period
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0
integer          nvar   , nscal  , nphas
integer          nideve , nrdeve , nituse , nrtuse

integer          maxelt, lstelt(maxelt)
integer          idevel(nideve), ituser(nituse), ia(*)

double precision dt(ncelet), rtp(ncelet,*), propce(ncelet,*)
double precision propfa(nfac,*), propfb(nfabor,*)
double precision coefa(nfabor,*), coefb(nfabor,*)
double precision rdevel(nrdeve), rtuser(nrtuse), ra(*)

! Local variables

integer          idebia, idebra
integer          iel, iutile

!===============================================================================

! TEST_TO_REMOVE_FOR_USE_OF_SUBROUTINE_START
!===============================================================================

if(1.eq.1) then
!       Tag to know if a call to this subroutine has already been done
  iusini = 0
  return
endif

!===============================================================================
! TEST_TO_REMOVE_FOR_USE_OF_SUBROUTINE_END


!===============================================================================
! 1.  Initialization of local variables
!===============================================================================

idebia = idbia0
idebra = idbra0

!===============================================================================
! 2. Unknown variables initialization:
!      ONLY done if there is no restart computation
!===============================================================================

! --- Example:  isca(1) is the variable number in RTP related to the first
!               user-defined scalar variable
!               rtp(iel,isca(1)) is the value of this variable in cell number
!               iel.

if (isuite.eq.0) then

  do iel = 1, ncel
    rtp(iel,isca(1)) = 25.d0
  enddo

endif


!===============================================================================
! 3. Time step:
!===============================================================================

! --- Example: We do a computation restart with a variable in time and constant
!              in space time step or with a variable in time and space time
!              step. We want to modify the time step given by the reading of
!              the restart file (in order to overcome a too slow evolution
!              for instance)

! The test below allows checking that the following example compiles
! while disabling it by default.

iutile = 0

if(iutile.eq.0) return

! ----------------------------------------------


if(isuite.eq.1.and.(idtvar.eq.1.or.idtvar.eq.2)) then
  do iel = 1, ncel
    dt (iel) = 10.d0*dt(iel)
  enddo
endif

!--------
! Formats
!--------

!----
! End
!----

return
end subroutine
