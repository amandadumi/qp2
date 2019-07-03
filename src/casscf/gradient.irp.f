use bitmasks

BEGIN_PROVIDER [ integer, nMonoEx ]
  BEGIN_DOC
  ! Number of single excitations
  END_DOC
  implicit none
  nMonoEx=n_core_orb*n_act_orb+n_core_orb*n_virt_orb+n_act_orb*n_virt_orb
END_PROVIDER

 BEGIN_PROVIDER [integer, excit, (2,nMonoEx)]
&BEGIN_PROVIDER [character*3, excit_class, (nMonoEx)]
  BEGIN_DOC
  ! a list of the orbitals involved in the excitation
  END_DOC
  
  implicit none
  integer                        :: i,t,a,ii,tt,aa,indx
  indx=0
  do ii=1,n_core_orb
    i=list_core(ii)
    do tt=1,n_act_orb
      t=list_act(tt)
      indx+=1
      excit(1,indx)=i
      excit(2,indx)=t
      excit_class(indx)='c-a'
    end do
  end do
  
  do ii=1,n_core_orb
    i=list_core(ii)
    do aa=1,n_virt_orb
      a=list_virt(aa)
      indx+=1
      excit(1,indx)=i
      excit(2,indx)=a
      excit_class(indx)='c-v'
    end do
  end do
  
  do tt=1,n_act_orb
    t=list_act(tt)
    do aa=1,n_virt_orb
      a=list_virt(aa)
      indx+=1
      excit(1,indx)=t
      excit(2,indx)=a
      excit_class(indx)='a-v'
    end do
  end do
  
  if (bavard) then
    write(6,*) ' Filled the table of the Monoexcitations '
    do indx=1,nMonoEx
      write(6,*) ' ex ',indx,' : ',excit(1,indx),' -> '              &
          ,excit(2,indx),'  ',excit_class(indx)
    end do
  end if
  
END_PROVIDER

BEGIN_PROVIDER [real*8, gradvec, (nMonoEx)]
  BEGIN_DOC
  ! calculate the orbital gradient <Psi| H E_pq |Psi> by hand, i.e. for
  ! each determinant I we determine the string E_pq |I> (alpha and beta
  ! separately) and generate <Psi|H E_pq |I>
  ! sum_I c_I <Psi|H E_pq |I> is then the pq component of the orbital
  ! gradient
  ! E_pq = a^+_pa_q + a^+_Pa_Q
  END_DOC
  implicit none
  integer                        :: ii,tt,aa,indx,ihole,ipart,istate
  real*8                         :: res
  
  do indx=1,nMonoEx
    ihole=excit(1,indx)
    ipart=excit(2,indx)
    call calc_grad_elem(ihole,ipart,res)
    gradvec(indx)=res
  end do
  
  real*8                         :: norm_grad
  norm_grad=0.d0
  do indx=1,nMonoEx
    norm_grad+=gradvec(indx)*gradvec(indx)
  end do
  norm_grad=sqrt(norm_grad)
  if (bavard) then
    write(6,*)
    write(6,*) ' Norm of the orbital gradient (via <0|EH|0>) : ', norm_grad
    write(6,*)
  endif
  
  
END_PROVIDER

subroutine calc_grad_elem(ihole,ipart,res)
  BEGIN_DOC
  ! eq 18 of Siegbahn et al, Physica Scripta 1980
  ! we calculate 2 <Psi| H E_pq | Psi>, q=hole, p=particle
  END_DOC
  implicit none
  integer                        :: ihole,ipart,mu,iii,ispin,ierr,nu,istate
  real*8                         :: res
  integer(bit_kind), allocatable :: det_mu(:,:),det_mu_ex(:,:)
  real*8                         :: i_H_psi_array(N_states),phase
  allocate(det_mu(N_int,2))
  allocate(det_mu_ex(N_int,2))
  
  res=0.D0
  
  do mu=1,n_det
    ! get the string of the determinant
    call det_extract(det_mu,mu,N_int)
    do ispin=1,2
      ! do the monoexcitation on it
      call det_copy(det_mu,det_mu_ex,N_int)
      call do_signed_mono_excitation(det_mu,det_mu_ex,nu             &
          ,ihole,ipart,ispin,phase,ierr)
      if (ierr.eq.1) then
        call i_H_psi(det_mu_ex,psi_det,psi_coef,N_int                &
            ,N_det,N_det,N_states,i_H_psi_array)
        do istate=1,N_states
          res+=i_H_psi_array(istate)*psi_coef(mu,istate)*phase
        end do
      end if
    end do
  end do
  
  ! state-averaged gradient
  res*=2.D0/dble(N_states)
  
end subroutine calc_grad_elem

BEGIN_PROVIDER [real*8, gradvec2, (nMonoEx)]
  BEGIN_DOC
  ! calculate the orbital gradient <Psi| H E_pq |Psi> from density
  ! matrices and integrals; Siegbahn et al, Phys Scr 1980
  ! eqs 14 a,b,c
  END_DOC
  implicit none
  integer                        :: i,t,a,indx
  real*8                         :: gradvec_it,gradvec_ia,gradvec_ta
  real*8                         :: norm_grad
  
  indx=0
  do i=1,n_core_orb
    do t=1,n_act_orb
      indx+=1
      gradvec2(indx)=gradvec_it(i,t)
    end do
  end do
  
  do i=1,n_core_orb
    do a=1,n_virt_orb
      indx+=1
      gradvec2(indx)=gradvec_ia(i,a)
    end do
  end do
  
  do t=1,n_act_orb
    do a=1,n_virt_orb
      indx+=1
      gradvec2(indx)=gradvec_ta(t,a)
    end do
  end do
  
  norm_grad=0.d0
  do indx=1,nMonoEx
    norm_grad+=gradvec2(indx)*gradvec2(indx)
  end do
  norm_grad=sqrt(norm_grad)
! if (bavard) then
    write(6,*)
    write(6,*) ' Norm of the orbital gradient (via D, P and integrals): ', norm_grad
    write(6,*)
! endif
  
END_PROVIDER

real*8 function gradvec_it(i,t)
  BEGIN_DOC
  ! the orbital gradient core -> active
  ! we assume natural orbitals
  END_DOC
  implicit none
  integer                        :: i,t
  
  integer                        :: ii,tt,v,vv,x,y
  integer                        :: x3,y3
  
  ii=list_core(i)
  tt=list_act(t)
  gradvec_it=2.D0*(Fipq(tt,ii)+Fapq(tt,ii))
  gradvec_it-=occnum(tt)*Fipq(ii,tt)
  do v=1,n_act_orb
    vv=list_act(v)
    do x=1,n_act_orb
      x3=x+n_core_orb
      do y=1,n_act_orb
        y3=y+n_core_orb
        gradvec_it-=2.D0*P0tuvx_no(t,v,x,y)*bielec_PQxx_no(ii,vv,x3,y3)
      end do
    end do
  end do
  gradvec_it*=2.D0
end function gradvec_it

real*8 function gradvec_ia(i,a)
  BEGIN_DOC
  ! the orbital gradient core -> virtual
  END_DOC
  implicit none
  integer                        :: i,a,ii,aa
  
  ii=list_core(i)
  aa=list_virt(a)
  gradvec_ia=2.D0*(Fipq(aa,ii)+Fapq(aa,ii))
  gradvec_ia*=2.D0
  
end function gradvec_ia

real*8 function gradvec_ta(t,a)
  BEGIN_DOC
  ! the orbital gradient active -> virtual
  ! we assume natural orbitals
  END_DOC
  implicit none
  integer                        :: t,a,tt,aa,v,vv,x,y
  
  tt=list_act(t)
  aa=list_virt(a)
  gradvec_ta=0.D0
  gradvec_ta+=occnum(tt)*Fipq(aa,tt)
  do v=1,n_act_orb
    do x=1,n_act_orb
      do y=1,n_act_orb
        gradvec_ta+=2.D0*P0tuvx_no(t,v,x,y)*bielecCI_no(x,y,v,aa)
      end do
    end do
  end do
  gradvec_ta*=2.D0
  
end function gradvec_ta

