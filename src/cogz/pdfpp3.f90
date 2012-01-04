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

subroutine pdfpp3 &
!================

 ( ncelet , ncel  ,                                               &
   fm     , fp2m  , yfm    , yfp2m , coyfp  ,                     &
   propce )

!===============================================================================
! FONCTION :
! ----------

! CALCUL DES PARAMETRES DE LA PDF
! PDF LIBBY - WILLIAMS 3 POINTS AVEC HYPOTHESE DE CURL
!       PDFPP3 RIVISE

! COMMENTAIRES :
! ------------

!    Dans un diagramme (F, Yf), on construit deux droites:
!         - La droite de combustion complete
!         - La droite de melange

!    Dans ce domaine, nous allons trouver deux pics qui
!    definiront une troisieme droite sur laquelle on definit
!    une abscisse curviligne G.


! LE RESULTAT EST :
! ---------------

!    CALCUL DES PARAMETRES ASSOCIES AUX FONCTIONS DIRAC

!      Les Diracs sont en position [F(.,1),Y(.,1)] et [F(.,2),Y(.,2)]
!      Leurs amplitudes respectives sont D(.,1) et D(.,2)
!      Pour chaque dirac,
!          on calcule la temperature [T(.,1), T(.,2)]
!                  la masse volumique [RHO(.,1), RHO(.,2)]
!                  le terme source chimique [W(.,1),W(.,2)]


!-------------------------------------------------------------------------------
! Arguments
!__________________.____._____.________________________________________________.
! name             !type!mode ! role                                           !
!__________________!____!_____!________________________________________________!
! ncelet           ! i  ! <-- ! number of extended (real + ghost) cells        !
! ncel             ! i  ! <-- ! number of cells                                !
! fm               ! tr ! <-- ! moyenne de la fraction de melange              !
! fp2m             ! tr ! <-- ! variance de la fraction de melange             !
! yfm              ! tr ! <-- ! moyenne de la fraction massique                !
! yfp2m            ! tr ! <-- ! variance de la fraction massique               !
! coyfp            ! tr !  ->           ! covariance
! propce(ncelet, *)! ra ! <-- ! physical properties at cell centers            !
!__________________!____!_____!________________________________________________!

!     TYPE : E (ENTIER), R (REEL), A (ALPHANUMERIQUE), T (TABLEAU)
!            L (LOGIQUE)   .. ET TYPES COMPOSES (EX : TR TABLEAU REEL)
!     MODE : <-- donnee, --> resultat, <-> Donnee modifiee
!            --- tableau de travail
!===============================================================================

!==============================================================================
! Module files
!==============================================================================

use paramx
use numvar
use optcal
use cstphy
use cstnum
use entsor
use pointe
use ppppar
use ppthch
use ppincl
use coincl

!===============================================================================

implicit none

! Arguments

integer          ncelet, ncel

double precision fm(ncelet)   , fp2m(ncelet)
double precision yfm(ncelet)  , yfp2m(ncelet)
double precision coyfp(ncelet)
double precision propce(ncelet,*)

! Local variables

integer          iel, igg, idirac
integer          mode
integer          clicoy, cliy1, cliy2 , cliy2p
integer          clif  , cliy , clifp2, clyfp2

double precision coefg(ngazgm), epsi
double precision yfuel
double precision yoxyd, yo2
double precision yprod,fmp,fp2mp,yfmp,yfp2mp,coyfpp
double precision y1, y2, f1, f2
double precision cstfa1, cstfa2, yfmpmx, cst
double precision dyfmp
double precision climax, climin

! --- Position des Diracs

double precision f(ndracm)    , y(ndracm)     , d(ndracm)
double precision h(ndracm)    , teml(ndracm)
double precision maml(ndracm) , w(ndracm)
double precision rhol(ndracm) , theta(ndracm)
double precision ymin(ndracm)  , ymax(ndracm)
double precision y2p(ndracm)

! --- Pointeurs & autres

integer          ipctem, ipcmam,  ipcrom
integer          ipampl(ndracm), ipfmel(ndracm)
integer          ipfmal(ndracm), ipteml(ndracm)
integer          ipmaml(ndracm)
integer          iprhol(ndracm)
integer          iptscl(ndracm)
integer          ipcfue, ipcoxy, ipcpro, ipctsc
double precision nbmol,  temsmm
double precision sum7, sum8, sum9, sum10, sum11, sum12, sum17
double precision sum1, sum2, sum3, sum4, sum5, sum6, sum16, sum15

integer ipass
data    ipass /0/
save    ipass

!===============================================================================

! ---> Position des variables

do idirac = 1, ndirac
  ipampl(idirac) = ipproc(iampl(idirac))
  ipfmel(idirac) = ipproc(ifmel(idirac))
  ipfmal(idirac) = ipproc(ifmal(idirac))
  ipteml(idirac) = ipproc(iteml(idirac))
  ipmaml(idirac) = ipproc(imaml(idirac))
  iprhol(idirac) = ipproc(irhol(idirac))
  iptscl(idirac) = ipproc(itscl(idirac))
enddo
ipcfue = ipproc(iym(1))
ipcoxy = ipproc(iym(2))
ipcpro = ipproc(iym(3))
ipctsc = ipproc(itsc)
ipctem = ipproc(itemp)
ipcrom = ipproc(irom)
ipcmam = ipproc(imam)

! ---> Initialisation

do igg = 1, ngazgm
  coefg(igg) = zero
enddo
epsi = 1.d-6

!     Compteur pour clipping

clicoy  = 0
cliy1   = 0
cliy2   = 0
cliy2p  = 0
clif    = 0
cliy    = 0
clifp2  = 0
clyfp2 = 0

!===============================================================================
! 0.  CALCULS PRELIMINAIRES
!===============================================================================

ipass = ipass + 1

! Controle de l intialisation de FMIN et FMAX

if ( (ipass.le.1 .and. isuite.eq.0 ) .or.                         &
     (ipass.le.1 .and. isuite.eq.1                                &
                 .and. initro.ne.1) ) then
  fmin = 4.405286343612334e-02
  fmax = 5.506607929515418e-02
endif

do iel =1, ncel

!-- F
  if ((fm(iel).le.fmin).or.(fm(iel).ge.fmax)) then
    fmp    =  max (min(fmax,fm(iel)),fmin)
    clif = clif +1
  else
    fmp = fm(iel)
  endif
!---Y
  climax =  (fmax-fmp)*fmin/(fmax-fmin)
  climin = max(zero,(fmp-fs(1))/(1.d0-fs(1)))
  if (( yfm(iel).ge.climax).or.(yfm(iel).lt.climin)) then
    yfmp = max(climin,min(yfm(iel),climax))
    cliy = cliy + 1
  else
    yfmp = yfm(iel)
  endif
!-- FP2M
  climax = (fmax -fmp)*(fmp-fmin)
  climin = zero

  if ((fp2m(iel).ge.climax).or.(fp2m(iel).lt.climin)) then
    fp2mp = max(climin,min(fp2m(iel),climax))
    clifp2 = clifp2 + 1
  else
    fp2mp = fp2m(iel)
  endif
! -- YFP2M
!    YFMAX = FMIN dans le cas Moreau
  climax = (fmin-yfmp)*yfmp
  climin = zero
  if ((yfp2m(iel).ge.climax).or.(yfp2m(iel).lt.climin)) then
    yfp2mp = max(climin,min(yfp2m(iel),climax))
    clyfp2 = clyfp2 + 1
  else
    yfp2mp = yfp2m(iel)
  endif

! --> Clip pour la covariance

  climax = sqrt(fp2mp*yfp2mp)
  climin = -sqrt(fp2mp*yfp2mp)
  if (coyfp(iel).ge.climax) then
    coyfpp = climax
    clicoy = clicoy + 1
  elseif (coyfp(iel).le.climin) then
    coyfpp = climin
    clicoy = clicoy + 1
  else
    coyfpp = coyfp(iel)
  endif

  yfmpmx = (fmax - fmp)*fmin/(fmax - fmin)
  dyfmp   = (yfmpmx - yfmp)

  if (((fp2mp.lt.epsi).and.(yfp2mp.lt.epsi))                      &
       .or.                                                       &
       ((yfmp.lt.epsi ).or.(dyfmp.lt.epsi))                       &
       .or.                                                       &
       ((fmp -fmin).lt.epsi)                                      &
       .or.                                                       &
       ( fp2mp.lt.epsi     )                                      &
       .or.                                                       &
       (((fmax -fmp).lt.epsi)             )) then

!===============================================================================
!   1.    NON PASSAGE PAR PDF
!===============================================================================

    sum1 = zero
    sum2 = zero
    sum3 = zero
    sum4 = zero
    sum5 = zero
    sum6 = zero
    sum15 = zero
    sum16 = zero

    do idirac =1, ndirac
      d(idirac) = 1.d0 / ndirac
      f(idirac) = fmp
      y(idirac) = yfmp

!---> Calcul de l'enthalpie

      h(idirac) = ((hmax-hmin)*f(idirac) + hmin*fmax - hmax*fmin) &
          / (fmax-fmin)

! ---> Calcul de la fraction massique des gaz (F, O et P)

      yfuel = y(idirac)
      yoxyd = 1.d0 - (coeff3+1.0d0)*f(idirac) + coeff3*y(idirac)
      yprod = 1.d0 - yfuel - yoxyd
      yo2   = coeff1 - (coeff1 + coeff2) * f(idirac)              &
           + coeff2 * y(idirac)

! ---> Calcul de la masse molaire et de la temperature

      coefg(1) = yfuel
      coefg(2) = yoxyd
      coefg(3) = yprod

! ------ Masse molaire

      nbmol = 0.d0
      do igg = 1, ngazg
        nbmol = nbmol + coefg(igg)/wmolg(igg)
      enddo
      maml(idirac) = 1.d0/nbmol

! ------ Calcul de la temperature pour le pic 1 et 2

      mode    = 1
      call cothht                                                 &
      !==========
           ( mode   , ngazg , ngazgm  , coefg  ,                  &
           npo    , npot  , th      , ehgazg ,                    &
           h(idirac)     , teml(idirac)    )

!     ---> Calcul de la masse volumique en 1 et 2

      if ( ipass.gt.1 .or.                                        &
          (isuite.eq.1.and.initro.eq.1) ) then
        rhol(idirac) = p0 * maml(idirac)                   &
             / (rr*teml(idirac))
      else
        rhol(idirac) = ro0
      endif

! ---> Calcul du terme source en 1 et 2 du scalaire YFM

      theta(idirac) = ta / teml(idirac)                           &
           * (1.d0 - teml(idirac) / tstar)

      w(idirac) = vref / lref * (- d(idirac)*rhol(idirac)         &
           * yfuel*yo2                                            &
           * exp( -theta(idirac) ))
!     -> BO 27/06 Controle du signe de W

      w(idirac) = min( w(idirac), zero)

! ---> Masse molaire du melange

      sum1 = sum1 + d(idirac)*maml(idirac)

! ---> Temperature du melange

      sum2 = sum2 + d(idirac)*teml(idirac)

! ---> Temperature / Masse molaire

      sum3 = sum3 + d(idirac)*teml(idirac)/maml(idirac)

! ---> Fractions massiques des especes globales

      sum4 = sum4 + yfuel*d(idirac)

      sum5 = sum5 + yoxyd*d(idirac)

      sum6 = sum6 + yprod*d(idirac)

      sum15 = sum15 +rhol(idirac)*d(idirac)

      sum16 = sum16 +w(idirac)

! ---> Stockage des proprietes via PROPCE

      propce(iel,ipampl(idirac)) = d(idirac)
      propce(iel,ipfmel(idirac)) = f(idirac)
      propce(iel,ipfmal(idirac)) = y(idirac)
      propce(iel,ipteml(idirac)) = teml(idirac)
      propce(iel,ipmaml(idirac)) = maml(idirac)
      propce(iel,iprhol(idirac)) = rhol(idirac)
      propce(iel,iptscl(idirac)) = w(idirac)

    enddo

    propce(iel,ipcmam) = sum1
    propce(iel,ipctem) = sum2
    temsmm             = sum3
    propce(iel,ipcfue) = sum4
    propce(iel,ipcoxy) = sum5
    propce(iel,ipcpro) = sum6
    propce(iel,ipctsc) = sum16

!---> Masse volumique du melange

    if ( ipass.gt.1 .or.                                          &
        (isuite.eq.1.and.initro.eq.1) ) then
      propce(iel,ipcrom) = srrom*propce(iel,ipcrom)               &
                          +(1.d0-srrom)*(p0/(rr*temsmm))
    endif

  else

!==================================================================================
!    2.    PASSAGE PAR PDF
!==================================================================================

! -------> Constantes

    cst = 1.d0

!-------->Calcul de F1 et F2 avec Curl em F

    call lwcurl                                                   &
!         =========
         ( cst  , fmp , fp2mp  ,                                  &
         fmin , fmax ,                                            &
         f1 , f2 , cstfa1 , cstfa2 )

! ------>  On calcul les Moyennes conditionnelles Y1, Y2

    y2 = ((fmp*yfmp + coyfpp) - f1*yfmp)                          &
         /(cstfa1*(f2 - f1))
    y1 = (yfmp - cstfa2*y2)/cstfa1

    ymin(1) = max(zero , ((f1- fs(1))/(1d0-fs(1))))
    ymax(1) = (fmax - f1)*fmin/(fmax - fmin)
    ymin(2) = max(zero , ((f2- fs(1))/(1d0-fs(1))))
    ymax(2) = (fmax - f2)*fmin/(fmax - fmin)

! clipping pour les moyennes conditionnelles

! Y1 = MAX(YMIN(1),MIN(Y1,YMAX(1)))
!  ===> compteur

    if (y1.ge.ymax(1)) then
      y1 = ymax(1)
      cliy1 = cliy1 + 1
    elseif (y1.le.ymin(1)) then
      y1 = ymin(1)
      cliy1 = cliy1 + 1
    endif
! == fin
! Y2 = MAX(YMIN(2),MIN(Y2,YMAX(2)))

    if (y2.ge.ymax(2)) then
      y2 = ymax(2)
      cliy2 = cliy2 + 1
    elseif (y2.le.ymin(2)) then
      y2 = ymin(2)
      cliy2 = cliy2 + 1
    endif

    y2p(1)  = ((yfmp**2 + yfp2mp) - cstfa2*(y2**2))               &
         /cstfa1 - y1**2
!          WRITE(NFECRA,*) ' Y2P(1)=',Y2P(1)

! clipping pour variance conditionnelles

!          Y2P(1) = MAX(ZERO,
!     &           MIN(Y2P(1),((Y1-YMIN(1))*(YMAX(1) - Y1))))
!  ====> Compteur

    climax =( (y1-ymin(1))*(ymax(1) - y1))
    climin = zero
    if (y2p(1).ge.climax) then
      y2p(1) = climax
      cliy2p = cliy2p + 1
    elseif (y2p(1).le.climin) then
      y2p(1) = climin
      cliy2p = cliy2p + 1
    endif
!==== fin
    call lwcurl                                                   &
!         =========
         ( cstfa1  , y1   , y2p(1)  ,                             &
         ymin(1) , ymax(1) ,                                      &
         y(1) , y(2) , d(1) , d(2) )

! ---------> Parametres des dirac en F1

    f(1) = f1
    f(2) = f1

! ---------> Parametres du dirac en F2

    f(3) = f2
    y(3) = y2
    d(3) = cstfa2

!===============================================================================
! 3.  DETERMINATION DES GRANDEURS THERMOCHIMIQUES DES DEUX PICS
!===============================================================================

! ---> Calcul de l'enthalpies en 1 et 2

    sum7  = zero
    sum8  = zero
    sum9  = zero
    sum10 = zero
    sum11 = zero
    sum12 = zero
    sum17 = zero

    do idirac = 1, ndirac
      h(idirac) = ( (hmax-hmin)*f(idirac)                         &
                   + hmin*fmax - hmax*fmin) / (fmax-fmin)

! ---> Calcul de la fraction massique des gaz (F, O et P) en 1 et 2

      yfuel = y(idirac)
      yoxyd = 1.d0 - (coeff3+1.0d0)*f(idirac)                     &
           + coeff3*y(idirac)
      yprod = 1.d0 - yfuel - yoxyd
      yo2   = coeff1 - (coeff1 + coeff2) * f(idirac)              &
                     + coeff2 * y(idirac)

! ---> Calcul de la masse molaire et de la temperature en 1 et 2

      coefg(1) = yfuel
      coefg(2) = yoxyd
      coefg(3) = yprod

! ------ Masse molaire pour le pic 1 et 2

      nbmol = 0.d0
      do igg = 1, ngazg
        nbmol = nbmol + coefg(igg)/wmolg(igg)
      enddo
      maml(idirac) = 1.d0/nbmol

! ------ Calcul de la temperature pour le pic 1 et 2

      mode    = 1
      call cothht                                                 &
      !==========
           ( mode   , ngazg , ngazgm  , coefg  ,                  &
           npo    , npot  , th      , ehgazg ,                    &
           h(idirac)      , teml(idirac)    )

! ---> Calcul de la masse volumique en 1 et 2

      if ( ipass.gt.1 .or.                                        &
          (isuite.eq.1.and.initro.eq.1) ) then
        rhol(idirac) = p0 * maml(idirac)                   &
             /(rr*teml(idirac))
      else
        rhol(idirac) = ro0
      endif

! ---> Calcul du terme source en 1 et 2 du scalaire YFM

      theta(idirac) = ta / teml(idirac)                           &
           *(1.d0 - teml(idirac)/tstar)

      w(idirac) = vref / lref                                     &
           *(- d(idirac)*rhol(idirac)                             &
           * yfuel*yo2                                            &
           * exp( -theta(idirac) ))
! ---> Controle du signe de W

      w(idirac) = min( w(idirac), zero)


! ---> Masse molaire du melange

      sum7 = sum7 + d(idirac)*maml(idirac)

! ---> Temperature du melange

      sum8 = sum8 + d(idirac)*teml(idirac)

! ---> Temperature / Masse molaire

      sum9 = sum9 + d(idirac)*teml(idirac)                        &
           /maml(idirac)

! ---> Fractions massiques des especes globales

      sum10 = sum10 + yfuel*d(idirac)

      sum11 = sum11 + yoxyd*d(idirac)

      sum12 = sum12 + yprod*d(idirac)

      sum17 = sum17 + w(idirac)

! ---> Stockage des proprietes via PROPCE

      propce(iel,ipampl(idirac)) = d(idirac)
      propce(iel,ipfmel(idirac)) = f(idirac)
      propce(iel,ipfmal(idirac)) = y(idirac)
      propce(iel,ipmaml(idirac)) = maml(idirac)
      propce(iel,ipteml(idirac)) = teml(idirac)
      propce(iel,iprhol(idirac)) = rhol(idirac)
      propce(iel,iptscl(idirac)) = w(idirac)


      if ((f(idirac).ne.zero).and.(y(idirac).ne.zero)) then
        if ((f(idirac).gt.fs(1)).or.                              &
             (f(idirac).lt.0.8*fs(1))) then
          WRITE(NFECRA,*)'==============F OUT=============*',     &
               idirac
          WRITE(NFECRA,*)'F',F(IDIRAC)
          WRITE(NFECRA,*)' IEL =', IEL
        endif

        if ((y(idirac).gt.f(idirac))                              &
             .or.(y(idirac).lt.-epsi)) then
          WRITE(NFECRA,*)'=============Y OUT=================',   &
               idirac
          WRITE(NFECRA,*)'Y',Y(IDIRAC)
          WRITE(NFECRA,*)' IEL =', IEL
        endif
      endif
    enddo

    propce(iel,ipcmam) = sum7
    propce(iel,ipctem) = sum8
    temsmm             = sum9
    propce(iel,ipcfue) = sum10
    propce(iel,ipcoxy) = sum11
    propce(iel,ipcpro) = sum12
    propce(iel,ipctsc) = sum17

! ---> Masse volumique du melange

    if ( ipass.gt.1 .or.                                          &
        (isuite.eq.1.and.initro.eq.1) ) then
      propce(iel,ipcrom) = srrom * propce(iel,ipcrom)             &
           + (1.d0-srrom) * (p0/(rr*temsmm))
    endif

  endif
enddo

end subroutine
