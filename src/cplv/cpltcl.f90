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

subroutine cpltcl &
!================

 ( nvar   , nscal  ,                                              &
   icodcl , itrifb , itypfb , izfppp ,                            &
   dt     , rtp    , rtpa   , propce , propfa , propfb ,          &
   coefa  , coefb  , rcodcl )

!===============================================================================
! FONCTION :
! --------

!   SOUS-PROGRAMME DU MODULE LAGRANGIEN COUPLE CHARBON PULVERISE :
!   --------------------------------------------------------------

!    ROUTINE UTILISATEUR POUR PHYSIQUE PARTICULIERE

!      COMBUSTION EULERIENNE DE CHARBON PULVERISE ET
!      TRANSPORT LAGRANGIEN DES PARTICULES DE CHARBON

!      CONDITIONS AUX LIMITES AUTOMATIQUES

!-------------------------------------------------------------------------------
! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! nvar             ! i  ! <-- ! total number of variables                      !
! nscal            ! i  ! <-- ! total number of scalars                        !
! icodcl           ! te ! --> ! code de condition limites aux faces            !
!  (nfabor,nvar    !    !     !  de bord                                       !
!                  !    !     ! = 1   -> dirichlet                             !
!                  !    !     ! = 3   -> densite de flux                       !
!                  !    !     ! = 4   -> glissemt et u.n=0 (vitesse)           !
!                  !    !     ! = 5   -> frottemt et u.n=0 (vitesse)           !
!                  !    !     ! = 6   -> rugosite et u.n=0 (vitesse)           !
!                  !    !     ! = 9   -> entree/sortie libre (vitesse          !
!                  !    !     !  entrante eventuelle     bloquee               !
! itrifb           ! ia ! <-- ! indirection for boundary faces ordering        !
! itypfb           ! ia ! <-- ! boundary face types                            !
! izfppp           ! te ! <-- ! numero de zone de la face de bord              !
! (nfabor)         !    !     !  pour le module phys. part.                    !
! dt(ncelet)       ! ra ! <-- ! time step (per cell)                           !
! rtp, rtpa        ! ra ! <-- ! calculated variables at cell centers           !
!  (ncelet, *)     !    !     !  (at current and previous time steps)          !
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
! propfa(nfac, *)  ! ra ! <-- ! physical properties at interior face centers   !
! propfb(nfabor, *)! ra ! <-- ! physical properties at boundary face centers   !
! coefa, coefb     ! ra ! <-- ! boundary conditions                            !
!  (nfabor, *)     !    !     !                                                !
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
use numvar
use optcal
use cstphy
use cstnum
use entsor
use parall
use ppppar
use ppthch
use coincl
use cpincl
use ppincl
use ppcpfu
use mesh

!===============================================================================

implicit none

! Arguments

integer          nvar   , nscal

integer          icodcl(nfabor,nvar)
integer          itrifb(nfabor), itypfb(nfabor)
integer          izfppp(nfabor)

double precision dt(ncelet), rtp(ncelet,*), rtpa(ncelet,*)
double precision propce(ncelet,*)
double precision propfa(nfac,*), propfb(nfabor,*)
double precision coefa(nfabor,*), coefb(nfabor,*)
double precision rcodcl(nfabor,nvar,3)

! Local variables

integer          ii, ifac, izone, mode, iel, ige, iok
integer          icha, ipbrom, icke, ipcvis
integer          nbrval
double precision qisqc, viscla, d2s3, uref2, rhomoy, dhy, xiturb
double precision ustar2, xkent, xeent, t1
double precision h1    (nozppm)
double precision qimpc (nozppm) , qcalc(nozppm)
double precision coefe (ngazem)
double precision f1mc  (ncharm) , f2mc (ncharm)

!===============================================================================
!===============================================================================
! 1.  INITIALISATIONS
!===============================================================================


ipbrom = ipprob(irom  )
ipcvis = ipproc(iviscl)

d2s3 = 2.d0/3.d0

!===============================================================================
! 1.  ECHANGES EN PARALLELE POUR LES DONNEES UTILISATEUR
!===============================================================================

!  En realite on pourrait eviter cet echange en modifiant uscpcl et en
!    demandant a l'utilisateur de donner les grandeurs dependant de la
!    zone hors de la boucle sur les faces de bord : les grandeurs
!    seraient ainsi disponibles sur tous les processeurs. Cependant,
!    ca rend le sous programme utilisateur un peu plus complique et
!    surtout, si l'utilisateur le modifie de travers, ca ne marche pas.
!  On suppose que toutes les grandeurs fournies sont positives, ce qui
!    permet d'utiliser un max pour que tous les procs les connaissent.
!    Si ce n'est pas le cas, c'est plus complique mais on peut s'en tirer
!    avec un max quand meme.

if(irangp.ge.0) then
  call parimx(nozapm,iqimp )
  !==========
  call parimx(nozapm,ientat)
  !==========
  call parimx(nozapm,ientcp)
  !==========
  call parrmx(nozapm,qimpat)
  !==========
  call parrmx(nozapm,timpat)
  !==========
  nbrval = nozppm*ncharm
  call parrmx(nbrval,qimpcp)
  !==========
  nbrval = nozppm*ncharm
  call parrmx(nbrval,timpcp)
  !==========
  nbrval = nozppm*ncharm*nclcpm
  call parrmx(nbrval,distch)
  !==========
endif


!===============================================================================
! 2.  CORRECTION DES VITESSES (EN NORME) POUR CONTROLER LES DEBITS
!     IMPOSES
!       ON BOUCLE SUR TOUTES LES FACES D'ENTREE
!                     =========================
!===============================================================================

! --- Debit calcule

do izone = 1, nozppm
  qcalc(izone) = 0.d0
enddo
do ifac = 1, nfabor
  izone = izfppp(ifac)
  if (izone .gt. 0) then
    if ( iqimp(izone).eq.2) then
      qcalc(izone) = qcalc(izone) -                               &
         ( rcodcl(ifac,iu,1)*surfbo(1,ifac) +              &
           rcodcl(ifac,iv,1)*surfbo(2,ifac) +              &
           rcodcl(ifac,iw,1)*surfbo(3,ifac) )
    else
      qcalc(izone) = qcalc(izone) - propfb(ifac,ipbrom) *         &
         ( rcodcl(ifac,iu,1)*surfbo(1,ifac) +              &
           rcodcl(ifac,iv,1)*surfbo(2,ifac) +              &
           rcodcl(ifac,iw,1)*surfbo(3,ifac) )
    endif
  endif
enddo

if(irangp.ge.0) then
  call parrsm(nozapm,qcalc )
endif

do izone = 1, nozapm
  if ( iqimp(izone).eq.0 ) then
    qimpc(izone) = qcalc(izone)
  endif
enddo

! --- Correction des vitesses en norme

iok = 0
do ii = 1, nzfppp
  izone = ilzppp(ii)
  if ( iqimp(izone).eq.1  .or.  iqimp(izone).eq.2) then
    if(abs(qcalc(izone)).lt.epzero) then
      write(nfecra,2001)izone,iqimp(izone),qcalc(izone)
      iok = iok + 1
    endif
  endif
enddo
if(iok.ne.0) then
  call csexit (1)
  !==========
endif
do ifac = 1, nfabor
  izone = izfppp(ifac)
   if (izone .gt. 0) then
     if ( iqimp(izone).eq.1 .or.  iqimp(izone).eq.2) then
       qimpc(izone) = qimpat(izone)
       qisqc = qimpc(izone)/qcalc(izone)
       rcodcl(ifac,iu,1) = rcodcl(ifac,iu,1)*qisqc
       rcodcl(ifac,iv,1) = rcodcl(ifac,iv,1)*qisqc
       rcodcl(ifac,iw,1) = rcodcl(ifac,iw,1)*qisqc
    endif
  endif

enddo



 2001 format(                                                           &
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/,&
'@ @@ ATTENTION : MODULE PHYSIQUES PARTICULIERES              ',/,&
'@    =========                                               ',/,&
'@     COMBUSTION CHARBON PULVERISE COUPLE AU                 ',/,&
'@     TRANSPORT LAGRANGIEN DES PARTICULES DE CHARBON :       ',/,&
'@     PROBLEME DANS LES CONDITIONS AUX LIMITES                ',/&
'@                                                            ',/,&
'@  Le debit est impose sur la zone IZONE =     ', I10         ,/,&
'@    puisque                IQIMP(IZONE) =     ', I10         ,/,&
'@  Or, sur cette zone, le produit RHO D S integre est nul :  ',/,&
'@    il vaut                             = ',E14.5            ,/,&
'@    (D est la direction selon laquelle est impose le debit).',/,&
'@                                                            ',/,&
'@  Le calcul ne peut etre execute.                           ',/,&
'@                                                            ',/,&
'@  Verifier uscpcl, et en particulier                        ',/,&
'@    - que le vecteur  RCODCL(IFAC,IU,1),             ',/,&
'@                      RCODCL(IFAC,IV,1),             ',/,&
'@                      RCODCL(IFAC,IW,1) qui determine',/,&
'@      la direction de la vitesse est non nul et n''est pas  ',/,&
'@      uniformement perpendiculaire aux face d''entree       ',/,&
'@    - que la surface de l''entree n''est pas nulle (ou que  ',/,&
'@      le nombre de faces de bord dans la zone est non nul)  ',/,&
'@    - que la masse volumique n''est pas nulle               ',/,&
'@                                                            ',/,&
'@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',/,&
'@                                                            ',/)

!===============================================================================
! 3.  REMPLISSAGE DU TABLEAU DES CONDITIONS LIMITES
!       ON BOUCLE SUR TOUTES LES FACES D'ENTREE
!                     =========================
!         ON DETERMINE LA FAMILLE ET SES PROPRIETES
!           ON IMPOSE LES CONDITIONS AUX LIMITES
!           POUR LA TURBULENCE

!===============================================================================

do ifac = 1, nfabor

  izone = izfppp(ifac)

!      ELEMENT ADJACENT A LA FACE DE BORD

  if ( itypfb(ifac).eq.ientre ) then

! ----  Traitement automatique de la turbulence

    if ( icalke(izone).ne.0 ) then

!       La turbulence est calculee par defaut si ICALKE different de 0
!          - soit a partir du diametre hydraulique, d'une vitesse
!            de reference adaptes a l'entree courante si ICALKE = 1
!          - soit a partir du diametre hydraulique, d'une vitesse
!            de reference et de l'intensite turvulente
!            adaptes a l'entree courante si ICALKE = 2

      uref2 = rcodcl(ifac,iu,1)**2                         &
            + rcodcl(ifac,iv,1)**2                         &
            + rcodcl(ifac,iw,1)**2
      uref2 = max(uref2,1.d-12)
      rhomoy = propfb(ifac,ipbrom)
      iel    = ifabor(ifac)
      viscla = propce(iel,ipcvis)
      icke   = icalke(izone)
      dhy    = dh(izone)
      xiturb = xintur(izone)
      ustar2 = 0.d0
      xkent = epzero
      xeent = epzero
      if (icke.eq.1) then
        call keendb                                               &
        !==========
        ( uref2, dhy, rhomoy, viscla, cmu, xkappa,                &
          ustar2, xkent, xeent )
      else if (icke.eq.2) then
        call keenin                                               &
        !==========
        ( uref2, xiturb, dhy, cmu, xkappa, xkent, xeent )
      endif

      if (itytur.eq.2) then

        rcodcl(ifac,ik,1)  = xkent
        rcodcl(ifac,iep,1) = xeent

      elseif (itytur.eq.3) then

        rcodcl(ifac,ir11,1) = d2s3*xkent
        rcodcl(ifac,ir22,1) = d2s3*xkent
        rcodcl(ifac,ir33,1) = d2s3*xkent
        rcodcl(ifac,ir12,1) = 0.d0
        rcodcl(ifac,ir13,1) = 0.d0
        rcodcl(ifac,ir23,1) = 0.d0
        rcodcl(ifac,iep,1)  = xeent

      elseif (iturb.eq.50) then

        rcodcl(ifac,ik,1)   = xkent
        rcodcl(ifac,iep,1)  = xeent
        rcodcl(ifac,iphi,1) = d2s3
        rcodcl(ifac,ifb,1)  = 0.d0

      elseif (iturb.eq.60) then

        rcodcl(ifac,ik,1)   = xkent
        rcodcl(ifac,iomg,1) = xeent/cmu/xkent

      elseif (iturb.eq.70) then

        rcodcl(ifac,inusa,1) = cmu*xkent**2/xeent

      endif

    endif

  endif

enddo

!===============================================================================
! 2.  REMPLISSAGE DU TABLEAU DES CONDITIONS LIMITES
!       ON BOUCLE SUR TOUTES LES FACES D'ENTREE
!                     =========================
!         ON DETERMINE LA FAMILLE ET SES PROPRIETES
!           ON IMPOSE LES CONDITIONS AUX LIMITES
!           POUR LES SCALAIRES
!===============================================================================

do ii = 1, nzfppp

  izone = ilzppp(ii)

! Une entree IENTRE est forcement du type
!            IENTAT = 1 ou IENTCP = 1

  if ( ientat(izone).eq.1 ) then

! ------ Calcul de H1(IZONE)

    do ige = 1, ngazem
      coefe(ige) = zero
    enddo
    coefe(io2) = wmole(io2) / (wmole(io2)+xsi*wmole(in2))
    coefe(in2) = 1.d0 - coefe(io2)
    do icha = 1, ncharm
      f1mc(icha) = zero
      f2mc(icha) = zero
    enddo
    t1   = timpat(izone)
    mode = -1
    call cpthp1                                                   &
    !==========
    ( mode  , h1(izone) , coefe  , f1mc   , f2mc   ,              &
      t1    )

    endif

enddo

do ifac = 1, nfabor

  izone = izfppp(ifac)

!      ELEMENT ADJACENT A LA FACE DE BORD

  if ( itypfb(ifac).eq.ientre ) then

! ----  Traitement automatique des scalaires physiques particulieres

    do icha = 1, ncharb

! ------ CL pour F1M et F2M du charbon ICHA
      rcodcl(ifac,isca(if1m(icha)),1) = zero
      rcodcl(ifac,isca(if2m(icha)),1) = zero

    enddo

! ------ CL pour F3M
    rcodcl(ifac,isca(if3m),1) = zero
! ------ CL pour FP4M
    rcodcl(ifac,isca(if4p2m),1)   = zero
! ------ CL pour HM
    do ige = 1, ngazem
      coefe(ige) = zero
    enddo
    coefe(io2) = wmole(io2) / (wmole(io2)+xsi*wmole(in2))
    coefe(in2) = 1.d0 - coefe(io2)
    do icha = 1, ncharm
      f1mc(icha) = zero
      f2mc(icha) = zero
    enddo
    t1   = timpat(izone)
    mode = -1
    call cpthp1                                                   &
    !==========
    ( mode  , h1(izone) , coefe  , f1mc   , f2mc   ,              &
      t1    )
    rcodcl(ifac,isca(ihm),1) = h1(izone)

  endif

enddo


!----
! FORMATS
!----


!----
! FIN
!----

return
end subroutine
