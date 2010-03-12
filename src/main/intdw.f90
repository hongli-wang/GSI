module intdwmod

!$$$ module documentation block
!           .      .    .                                       .
! module:   intdwmod    module for intdw and its tangent linear intdw_tl
!   prgmmr:
!
! abstract: module for intdw and its tangent linear intdw_tl
!
! program history log:
!   2005-05-12  Yanqiu zhu - wrap intdw and its tangent linear intdw_tl into one module
!   2005-11-16  Derber - remove interfaces
!   2008-11-26  Todling - remove intdw_tl
!   2009-08-13  lueken - updated documentation
!
! subroutines included:
!   sub intdw_
!
! variable definitions:
!
! attributes:
!   language: f90
!   machine:
!
!$$$ end documentation block

implicit none

PRIVATE
PUBLIC intdw

interface intdw; module procedure &
          intdw_
end interface

contains

subroutine intdw_(dwhead,ru,rv,su,sv)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    intw        apply nonlin qc operator for lidar winds
!   prgmmr: derber           org: np23                date: 1991-02-26
!
! abstract: apply observation operator and adjoint for lidar winds
!             with nonlinear qc operator
!
! program history log:
!   1991-02-26  derber
!   1999-11-22  yang
!   2004-08-02  treadon - add only to module use, add intent in/out
!   2004-10-07  parrish - add nonlinear qc option
!   2005-03-01  parrish - nonlinear qc change to account for inflated obs error
!   2005-04-11  treadon - merge intdw and intdw_qc into single routine
!   2005-08-02  derber  - modify for variational qc parameters for each ob
!   2005-09-28  derber  - consolidate location and weight arrays
!   2006-07-28  derber  - modify to use new inner loop obs data structure
!                       - unify NL qc
!   2007-02-15  rancic - add foto
!   2007-03-19  tremolet - binning of observations
!   2007-06-05  tremolet - use observation diagnostics structure
!   2007-07-09  tremolet - observation sensitivity
!   2008-06-02  safford - rm unused vars
!   2008-01-04  tremolet - Don't apply H^T if l_do_adjoint is false
!   2008-11-28  todling  - turn FOTO optional; changed ptr%time handle
!
! usage: call intdw(ru,rv,su,sv)
!   input argument list:
!     dwhead   - obs type pointer to obs structure
!     su       - u increment in grid space
!     sv       - v increment in grid space
!
!   output argument list:
!     dwhead   - obs type pointer to obs structure
!     ru       - output u adjoint operator results 
!     rv       - output v adjoint operator results 
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,i_kind
  use constants, only: half,one,tiny_r_kind,cg_term,r3600
  use obsmod, only: dw_ob_type,lsaveobsens,l_do_adjoint
  use qcmod, only: nlnqc_iter,varqc_iter
  use gridmod, only: latlon1n
  use jfunc, only: jiter,l_foto,xhat_dt,dhat_dt
  implicit none

! Declare passed variables
  type(dw_ob_type),pointer        ,intent(in   ) :: dwhead
  real(r_kind),dimension(latlon1n),intent(in   ) :: su,sv
  real(r_kind),dimension(latlon1n),intent(inout) :: ru,rv

! Declare local variables
  integer(i_kind) j1,j2,j3,j4,j5,j6,j7,j8
! real(r_kind) penalty
  real(r_kind) val,valu,valv,w1,w2,w3,w4,w5,w6,w7,w8,pg_dw
  real(r_kind) cg_dw,p0,grad,wnotgross,wgross,time_dwi
  type(dw_ob_type), pointer :: dwptr


  dwptr => dwhead
  do while (associated(dwptr))
     j1=dwptr%ij(1)
     j2=dwptr%ij(2)
     j3=dwptr%ij(3)
     j4=dwptr%ij(4)
     j5=dwptr%ij(5)
     j6=dwptr%ij(6)
     j7=dwptr%ij(7)
     j8=dwptr%ij(8)
     w1=dwptr%wij(1)
     w2=dwptr%wij(2)
     w3=dwptr%wij(3)
     w4=dwptr%wij(4)
     w5=dwptr%wij(5)
     w6=dwptr%wij(6)
     w7=dwptr%wij(7)
     w8=dwptr%wij(8)
     

!    Forward model
     val=(w1*su(j1)+w2*su(j2)+w3*su(j3)+w4*su(j4)+                   &
          w5*su(j5)+w6*su(j6)+w7*su(j7)+w8*su(j8))*dwptr%sinazm+     &
         (w1*sv(j1)+w2*sv(j2)+w3*sv(j3)+w4*sv(j4)+                   &
          w5*sv(j5)+w6*sv(j6)+w7*sv(j7)+w8*sv(j8))*dwptr%cosazm

     if ( l_foto ) then
        time_dwi=dwptr%time*r3600
        val=val+                                              &
          ((w1*xhat_dt%u(j1)+w2*xhat_dt%u(j2)+                &
            w3*xhat_dt%u(j3)+w4*xhat_dt%u(j4)+                &
            w5*xhat_dt%u(j5)+w6*xhat_dt%u(j6)+                &
            w7*xhat_dt%u(j7)+w8*xhat_dt%u(j8))*dwptr%sinazm+  &
           (w1*xhat_dt%v(j1)+w2*xhat_dt%v(j2)+                &
            w3*xhat_dt%v(j3)+w4*xhat_dt%v(j4)+                &
            w5*xhat_dt%v(j5)+w6*xhat_dt%v(j6)+                &
            w7*xhat_dt%v(j7)+w8*xhat_dt%v(j8))*dwptr%cosazm)  &
            *time_dwi
     endif

     if (lsaveobsens) then
        dwptr%diags%obssen(jiter) = val * dwptr%raterr2 * dwptr%err2
     else
        if (dwptr%luse) dwptr%diags%tldepart(jiter)=val
     endif

!    Do Adjoint
     if (l_do_adjoint) then
        if (lsaveobsens) then
           grad = dwptr%diags%obssen(jiter)
 
        else
           val=val-dwptr%res
 
!          gradient of nonlinear operator
           if (nlnqc_iter .and. dwptr%pg > tiny_r_kind .and. &
                                dwptr%b  > tiny_r_kind) then
              pg_dw=varqc_iter*dwptr%pg
              cg_dw=cg_term/dwptr%b
              wnotgross= one-pg_dw
              wgross = pg_dw*cg_dw/wnotgross
              p0   = wgross/(wgross+exp(-half*dwptr%err2*val**2))
              val = val*(one-p0)
           endif

           grad = val * dwptr%raterr2 * dwptr%err2
        endif

!       Adjoint
        valu=dwptr%sinazm * grad
        valv=dwptr%cosazm * grad
        ru(j1)=ru(j1)+w1*valu
        ru(j2)=ru(j2)+w2*valu
        ru(j3)=ru(j3)+w3*valu
        ru(j4)=ru(j4)+w4*valu
        ru(j5)=ru(j5)+w5*valu
        ru(j6)=ru(j6)+w6*valu
        ru(j7)=ru(j7)+w7*valu
        ru(j8)=ru(j8)+w8*valu
        rv(j1)=rv(j1)+w1*valv
        rv(j2)=rv(j2)+w2*valv
        rv(j3)=rv(j3)+w3*valv
        rv(j4)=rv(j4)+w4*valv
        rv(j5)=rv(j5)+w5*valv
        rv(j6)=rv(j6)+w6*valv
        rv(j7)=rv(j7)+w7*valv
        rv(j8)=rv(j8)+w8*valv
        if(l_foto)then
           valu = valu*time_dwi
           valv = valv*time_dwi
           dhat_dt%u(j1)=dhat_dt%u(j1)+w1*valu
           dhat_dt%u(j2)=dhat_dt%u(j2)+w2*valu
           dhat_dt%u(j3)=dhat_dt%u(j3)+w3*valu
           dhat_dt%u(j4)=dhat_dt%u(j4)+w4*valu
           dhat_dt%u(j5)=dhat_dt%u(j5)+w5*valu
           dhat_dt%u(j6)=dhat_dt%u(j6)+w6*valu
           dhat_dt%u(j7)=dhat_dt%u(j7)+w7*valu
           dhat_dt%u(j8)=dhat_dt%u(j8)+w8*valu
           dhat_dt%v(j1)=dhat_dt%v(j1)+w1*valv
           dhat_dt%v(j2)=dhat_dt%v(j2)+w2*valv
           dhat_dt%v(j3)=dhat_dt%v(j3)+w3*valv
           dhat_dt%v(j4)=dhat_dt%v(j4)+w4*valv
           dhat_dt%v(j5)=dhat_dt%v(j5)+w5*valv
           dhat_dt%v(j6)=dhat_dt%v(j6)+w6*valv
           dhat_dt%v(j7)=dhat_dt%v(j7)+w7*valv
           dhat_dt%v(j8)=dhat_dt%v(j8)+w8*valv
        end if
     endif

     dwptr => dwptr%llpoint

  end do

  return
end subroutine intdw_

end module intdwmod
