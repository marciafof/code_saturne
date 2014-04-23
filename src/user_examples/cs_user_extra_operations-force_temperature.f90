!-------------------------------------------------------------------------------

!VERS

! This file is part of Code_Saturne, a general-purpose CFD tool.
!
! Copyright (C) 1998-2014 EDF S.A.
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

!===============================================================================
! Purpose:
! -------

! \file cs_user_extra_operations-force_temperature.f90
! This is an example of cs_user_extra_operations.f90 which
! performs forced temperature

!-------------------------------------------------------------------------------

!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     nvar          total number of variables
!> \param[in]     nscal         total number of scalars
!> \param[in]     dt            time step (per cell)
!> \param[in]     rtp, rtpa     calculated variables at cell centers
!>                               (at current and previous time steps)
!> \param[in]     propce        physical properties at cell centers
!_______________________________________________________________________________

subroutine cs_f_user_extra_operations &
 ( nvar   , nscal  ,                                              &
   dt     , rtpa   , rtp    , propce )

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
use lagpar
use lagran
use lagdim
use parall
use period
use ppppar
use ppthch
use ppincl
use mesh
use field
use field_operator
use turbomachinery

!===============================================================================

implicit none

! Arguments

integer          nvar   , nscal

double precision dt(ncelet), rtp(ncelet,nflown:nvar), rtpa(ncelet,nflown:nvar)
double precision propce(ncelet,*)

! Local variables

!< [loc_var_dec]
integer          iel
integer          iscal
!< [loc_var_dec]

!===============================================================================

!===============================================================================
! Initialization
!===============================================================================

!===============================================================================
! Example: set temperature to 20 in a given region starting at t = 12s
! --------------------------------------------------------------------

! Do this with precaution...
! The user is responsible for the validity of results.
!===============================================================================

!< [example_1]
iscal = iscalt

if (ttcabs .ge. 12.d0) then

  if (iscal.gt.0 .and. iscal.le.nscal) then
    do iel = 1, ncel
      rtp(iel,isca(iscal)) = 20.d0
    enddo
  endif

  write(nfecra,3000)

endif
!< [example_1]

 3000 format                                                       &
  (/,                                                              &
   ' User modification of variables at the end of the time step',  &
   /)

return
end subroutine cs_f_user_extra_operations
