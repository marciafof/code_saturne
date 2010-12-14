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

subroutine matrdt &
!================

 ( idbia0 , idbra0 ,                                              &
   nideve , nrdeve , nituse , nrtuse ,                            &
   iconvp , idiffp , isym   ,                                     &
   idevel , ituser , ia     ,                                     &
   coefbp , flumas , flumab , viscf  , viscb  ,                   &
   da     ,                                                       &
   rdevel , rtuser , ra     )

!===============================================================================
! FONCTION :
! ----------

! CONSTRUCTION DE LA DIAGONALE DE LA
!   MATRICE DE CONVECTION UPWIND/DIFFUSION/TS
!   POUR DETERMINATION DU PAS DE TEMPS VARIABLE, COURANT, FOURIER


!-------------------------------------------------------------------------------
!ARGU                             ARGUMENTS
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! idbia0           ! i  ! <-- ! number of first free position in ia            !
! idbra0           ! i  ! <-- ! number of first free position in ra            !
! nideve, nrdeve   ! i  ! <-- ! sizes of idevel and rdevel arrays              !
! nituse, nrtuse   ! i  ! <-- ! sizes of ituser and rtuser arrays              !
! iconvp           ! e  ! <-- ! indicateur = 1 convection, 0 sinon             !
! idiffp           ! e  ! <-- ! indicateur = 1 diffusion , 0 sinon             !
! isym             ! e  ! <-- ! indicateur = 1 matrice symetrique              !
!                  !    !     !              2 matrice non symetrique          !
! idevel(nideve)   ! ia ! <-> ! integer work array for temporary development   !
! ituser(nituse)   ! ia ! <-> ! user-reserved integer work array               !
! ia(*)            ! ia ! --- ! main integer work array                        !
! coefbp(nfabor    ! tr ! <-- ! tab b des cl pour le pdt considere             !
! flumas(nfac)     ! tr ! <-- ! flux de masse aux faces internes               !
! flumab(nfabor    ! tr ! <-- ! flux de masse aux faces de bord                !
! viscf(nfac)      ! tr ! <-- ! visc*surface/dist aux faces internes           !
! viscb(nfabor     ! tr ! <-- ! visc*surface/dist aux faces de bord            !
! da (ncelet       ! tr ! --> ! partie diagonale de la matrice                 !
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
use entsor
use parall
use mesh

!===============================================================================

implicit none

! Arguments

integer          idbia0 , idbra0
integer          nideve , nrdeve , nituse , nrtuse
integer          iconvp , idiffp , isym

integer          idevel(nideve), ituser(nituse), ia(*)

double precision coefbp(nfabor)
double precision flumas(nfac), flumab(nfabor)
double precision viscf(nfac), viscb(nfabor)
double precision da(ncelet )
double precision rdevel(nrdeve), rtuser(nrtuse), ra(*)

! Local variables

integer          ifac,ii,jj,iel
double precision flui,fluj,xaifa1,xaifa2

!===============================================================================

!===============================================================================
! 1. INITIALISATION
!===============================================================================

if(isym.ne.1.and.isym.ne.2) then
   write(nfecra,1000) isym
   call csexit (1)
endif

do iel = 1, ncel
  da(iel) = 0.d0
enddo
if(ncelet.gt.ncel) then
  do iel = ncel+1, ncelet
    da(iel) = 0.d0
  enddo
endif

!===============================================================================
! 2.    CALCUL DES TERMES EXTRADIAGONAUX INUTILE
!===============================================================================

!===============================================================================
! 3.     CONTRIBUTION DES TERMES X-TRADIAGONAUX A LA DIAGONALE
!===============================================================================

if(isym.eq.2) then

  if (ivecti.eq.1) then

!CDIR NODEP
    do ifac = 1,nfac
      ii = ifacel(1,ifac)
      jj = ifacel(2,ifac)
      fluj =-0.5d0*( flumas(ifac) +abs(flumas(ifac)) )
      flui = 0.5d0*( flumas(ifac) -abs(flumas(ifac)) )
      xaifa2 = iconvp*fluj -idiffp*viscf(ifac)
      xaifa1 = iconvp*flui -idiffp*viscf(ifac)
      da(ii) = da(ii) -xaifa2
      da(jj) = da(jj) -xaifa1
    enddo

  else

! VECTORISATION NON FORCEE
    do ifac = 1,nfac
      ii = ifacel(1,ifac)
      jj = ifacel(2,ifac)
      fluj =-0.5d0*( flumas(ifac) +abs(flumas(ifac)) )
      flui = 0.5d0*( flumas(ifac) -abs(flumas(ifac)) )
      xaifa2 = iconvp*fluj -idiffp*viscf(ifac)
      xaifa1 = iconvp*flui -idiffp*viscf(ifac)
      da(ii) = da(ii) -xaifa2
      da(jj) = da(jj) -xaifa1
    enddo

  endif

else

  if (ivecti.eq.1) then

!CDIR NODEP
    do ifac = 1,nfac
      ii = ifacel(1,ifac)
      jj = ifacel(2,ifac)
      flui = 0.5d0*( flumas(ifac) -abs(flumas(ifac)) )
      xaifa1 = iconvp*flui -idiffp*viscf(ifac)
      da(ii) = da(ii) -xaifa1
      da(jj) = da(jj) -xaifa1
    enddo

  else

! VECTORISATION NON FORCEE
    do ifac = 1,nfac
      ii = ifacel(1,ifac)
      jj = ifacel(2,ifac)
      flui = 0.5d0*( flumas(ifac) -abs(flumas(ifac)) )
      xaifa1 = iconvp*flui -idiffp*viscf(ifac)
      da(ii) = da(ii) -xaifa1
      da(jj) = da(jj) -xaifa1
    enddo

  endif

endif

!===============================================================================
! 4.     CONTRIBUTION DES FACETTES DE BORDS A LA DIAGONALE
!===============================================================================

if (ivectb.eq.1) then

!CDIR NODEP
  do ifac = 1, nfabor
    ii = ifabor(ifac)
    flui = 0.5d0*( flumab(ifac) -abs(flumab(ifac)) )
    fluj =-0.5d0*( flumab(ifac) +abs(flumab(ifac)) )
    da(ii) = da(ii) +iconvp*(-fluj + flui*coefbp(ifac) )          &
                    +idiffp*viscb(ifac)*(1.d0-coefbp(ifac))
  enddo

else

! VECTORISATION NON FORCEE
  do ifac = 1, nfabor
    ii = ifabor(ifac)
    flui = 0.5d0*( flumab(ifac) -abs(flumab(ifac)) )
    fluj =-0.5d0*( flumab(ifac) +abs(flumab(ifac)) )
    da(ii) = da(ii) +iconvp*(-fluj + flui*coefbp(ifac) )          &
                    +idiffp*viscb(ifac)*(1.d0-coefbp(ifac))
  enddo

endif

!--------
! FORMATS
!--------

#if defined(_CS_LANG_FR)

 1000 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ ATTENTION : ARRET DANS matrdt                           ',/,&
'@    =========                                               ',/,&
'@     APPEL DE matrdt              AVEC ISYM   = ',I10        ,/,&
'@                                                            ',/,&
'@  Le calcul ne peut pas etre execute.                       ',/,&
'@                                                            ',/,&
'@  Contacter l''assistance.                                  ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)

#else

 1000 format(                                                           &
'@'                                                            ,/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@'                                                            ,/,&
'@ @@ WARNING: ABORT IN matrdt'                                ,/,&
'@    ========'                                                ,/,&
'@     matrdt CALLED                WITH ISYM   = ',I10        ,/,&
'@'                                                            ,/,&
'@  The calculation will not be run.'                          ,/,&
'@'                                                            ,/,&
'@  Contact support.'                                          ,/,&
'@'                                                            ,/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@'                                                            ,/)

#endif

!----
! FIN
!----

return

end subroutine
