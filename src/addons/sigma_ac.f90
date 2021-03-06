subroutine sigma_ac(fnum,n1,n2,n3,nk,bndrg,evalmap,neval,sigx,vxcnk,&
                     &vclnk,sigc,sigcr)
use modmain
use mod_linresp
use mod_addons_q
use mod_nrkp
use mod_expigqr
implicit none
!
integer,intent(in) :: fnum
integer,intent(in) :: n1
integer,intent(in) :: n2
integer,intent(in) :: n3
integer,intent(in) :: nk
integer,intent(in) :: bndrg(2,nspinor)
integer,intent(in) :: evalmap(n1,n2,nk)
integer,intent(in) :: neval(n2,nk)
real(8),intent(in) :: sigx(n1,n2,nk)
real(8),intent(in) :: vxcnk(n1,n2,nk)
real(8),intent(in) :: vclnk(n1,n2,nk)
complex(8),intent(in) :: sigc(n1,n2,n3,nk)
complex(8),intent(out) :: sigcr(2,n1,n2,nk)
!
integer :: iw1,iw2,ist1,isp1,ikloc,n,ik,ibnd,fbnd,i,j
integer :: iloc,nevalloc(n2,nk)
complex(8),allocatable :: gn(:,:),ctmp(:,:,:,:)
complex(8),allocatable :: sigcoe(:,:,:,:)
complex(8) :: enk,wn(n3),zn(2)
!test
integer :: n0
complex(8) :: rwn(2*cpe_N+1)  ! change it later
complex(8),external :: ac_func
!
allocate(gn(n3,n3))
allocate(sigcoe(n3,n1,n2,nk))
allocate(ctmp(n3,n1,n2,nk))
!

sigcoe=zzero
sigcr=zzero
gn=zzero
ctmp=zzero
wn=zzero
!tmp1=zzero

!change order of indices
do ikloc=1,nkptnrloc
 do iw1=1,n3
  ctmp(iw1,:,:,ikloc)=sigc(:,:,iw1,ikloc)
 enddo
enddo

! iw mesh
n=0
do iw1=-int((n3-1)/2),int(n3/2)
 n=n+1
 wn(n)=zi*(2.d0*iw1+1)*pi/bhbar
 if (iw1.eq.0) n0=n
enddo


! Pade approximation by Vidberg and Serene
if (ac_sigma.eq.1) then

  if (mpi_grid_root()) write(fnum,'("Perform Pade approximation for &
                        &the self-energy")')
  do ikloc=1,nk
   do isp1=1,n2
    do ist1=1,n1
     do iw1=1,n3
      do iw2=iw1,n3
       if (iw1.eq.1) then
        gn(1,iw2)=ctmp(iw2,ist1,isp1,ikloc)
       else
        gn(iw1,iw2)=(gn(iw1-1,iw1-1)-gn(iw1-1,iw2))/&
                 &(wn(iw2)-wn(iw1-1))/gn(iw1-1,iw2)
       endif
      enddo !iw2
      ! gn(i,i) are the coefficients of the fitted self-energy
      sigcoe(iw1,ist1,isp1,ikloc)=gn(iw1,iw1)
     enddo !iw1
    enddo !ist1
   enddo !ist2
  enddo !ikloc

  do ikloc=1,nk
   ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
   do isp1=1,n2
    ibnd=bndrg(1,isp1)
    do ist1=1,n1
     do iw1=1,2
      enk=dcmplx(evalsvnr(ibnd+ist1-1,ik)+(iw1-1)*del_e,lr_eta)
      sigcr(iw1,ist1,isp1,ikloc)=ac_func(n3,sigcoe(:,ist1,isp1,ikloc),wn,enk)
     enddo
    enddo
   enddo
  enddo

! continuous pole expansion by Staar
elseif (ac_sigma.eq.3) then

 if (mpi_grid_root()) write(fnum,'("Perform continuous-pole expansion for &
                        &the self-energy")')
 ! bands are parallelized along dim_q
 do ikloc=1,nk
  do isp1=1,n2
    nevalloc(isp1,ikloc)=mpi_grid_map(neval(isp1,ikloc),dim_q)
    if (mpi_grid_root()) &
    write(*,*) "isp1,ikloc,nevalloc:",isp1,ikloc,nevalloc(isp1,ikloc)
  enddo
 enddo
 
 ! define \omega_n along the real-w axis
 n=0
 do iw1=-cpe_N,cpe_N
  n=n+1
  rwn(n)=dcmplx(iw1)*cpe_delta/cpe_N
 enddo

 do ikloc=1,nk
  ik=mpi_grid_map(nkptnr,dim_k,loc=ikloc)
  do isp1=1,n2
   do iloc=1,nevalloc(isp1,ikloc)
     ! parallel over j along q_dim
     i=mpi_grid_map(neval(isp1,ikloc),dim_q,loc=iloc)
     ibnd=evalmap(i,isp1,ikloc)

     if (ibnd.gt.bndrg(2,isp1)) cycle
     if (mpi_grid_root()) write(*,*) "ibnd:",ibnd

     j=ibnd-bndrg(1,isp1)+1
     if (mpi_grid_root()) write(*,*) "j:",j

     zn(1)=dcmplx(evalsvnr(ibnd,ik),lr_eta)
     zn(2)=dcmplx(evalsvnr(ibnd,ik)+del_e,lr_eta)

     ! original algorithm of CPE
     if (mpi_grid_root()) write(fnum,'("Frank-Wolfe like algorithm!")')
     !
     call cpe_solver(ibnd,isp1,ik,ikloc,n0,n3,wn,ctmp(:,j,isp1,ikloc),n,&
                    &rwn,2,zn,sigx(j,isp1,ikloc),vxcnk(j,isp1,ikloc),&
                    &vclnk(j,isp1,ikloc),sigcr(:,j,isp1,ikloc))

     ! perform CPE once for degenerate states
     if (i.lt.neval(isp1,ikloc)) then
      fbnd=evalmap(i+1,isp1,ikloc)-1
      if (mpi_grid_root()) write(*,*) "fbnd:",fbnd
      if (fbnd.gt.ibnd) then
       do ist1=j+1,fbnd-bndrg(1,isp1)+1
        sigcr(:,ist1,isp1,ikloc)=sigcr(:,j,isp1,ikloc)
       enddo
      endif
     endif

   enddo !iloc
  enddo !isp1
 enddo !ikloc

 call mpi_grid_reduce(sigcr(1,1,1,1),2*n1*n2*nk,dims=(/dim_q/),all=.true.)
endif

deallocate(gn,ctmp,sigcoe)
return
end subroutine
