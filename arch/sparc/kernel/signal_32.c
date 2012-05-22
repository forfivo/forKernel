/*  linux/arch/sparc/kernel/signal.c
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 *  Copyright (C) 1995 David S. Miller (davem@caip.rutgers.edu)
 *  Copyright (C) 1996 Miguel de Icaza (miguel@nuclecu.unam.mx)
 *  Copyright (C) 1997 Eddie C. Dost   (ecd@skynet.be)
 */

#include <linux/sched.h>
#include <linux/kernel.h>
#include <linux/signal.h>
#include <linux/errno.h>
#include <linux/wait.h>
#include <linux/ptrace.h>
#include <linux/unistd.h>
#include <linux/mm.h>
#include <linux/tty.h>
#include <linux/smp.h>
#include <linux/binfmts.h>	/* do_coredum */
#include <linux/bitops.h>
#include <linux/tracehook.h>

#include <asm/uaccess.h>
#include <asm/ptrace.h>
#include <asm/pgalloc.h>
#include <asm/pgtable.h>
#include <asm/cacheflush.h>	/* flush_sig_insns */
#include <asm/switch_to.h>

#include "sigutil.h"

#define _BLOCKABLE (~(sigmask(SIGKILL) | sigmask(SIGSTOP)))

extern void fpsave(unsigned long *fpregs, unsigned long *fsr,
		   void *fpqueue, unsigned long *fpqdepth);
extern void fpload(unsigned long *fpregs, unsigned long *fsr);

struct signal_frame {
	struct sparc_stackf	ss;
	__siginfo32_t		info;
	__siginfo_fpu_t __user	*fpu_save;
	unsigned long		insns[2] __attribute__ ((aligned (8)));
	unsigned int		extramask[_NSIG_WORDS - 1];
	unsigned int		extra_size; /* Should be 0 */
	__siginfo_rwin_t __user	*rwin_save;
} __attribute__((aligned(8)));

struct rt_signal_frame {
	struct sparc_stackf	ss;
	siginfo_t		info;
	struct pt_regs		regs;
	sigset_t		mask;
	__siginfo_fpu_t __user	*fpu_save;
	unsigned int		insns[2];
	stack_t			stack;
	unsigned int		extra_size; /* Should be 0 */
	__siginfo_rwin_t __user	*rwin_save;
} __attribute__((aligned(8)));

/* Align macros */
#define SF_ALIGNEDSZ  (((sizeof(struct signal_frame) + 7) & (~7)))
#define RT_ALIGNEDSZ  (((sizeof(struct rt_signal_frame) + 7) & (~7)))

static int _sigpause_common(old_sigset_t set)
{
	sigset_t blocked;
	siginitset(&blocked, set);
	return sigsuspend(&blocked);
}

asmlinkage int sys_sigsuspend(old_sigset_t set)
{
	return _sigpause_common(set);
}

asmlinkage void do_sigreturn(struct pt_regs *regs)
{
	struct signal_frame __user *sf;
	unsigned long up_psr, pc, npc;
	sigset_t set;
	__siginfo_fpu_t __user *fpu_save;
	__siginfo_rwin_t __user *rwin_save;
	int err;

	/* Always make any pending restarted system calls return -EINTR */
	current_thread_info()->restart_block.fn = do_no_restart_syscall;

	synchronize_user_stack();

	sf = (struct signal_frame __user *) regs->u_regs[UREG_FP];

	/* 1. Make sure we are not getting garbage from the user */
	if (!access_ok(VERIFY_READ, sf, sizeof(*sf)))
		goto segv_and_exit;

	if (((unsigned long) sf) & 3)
		goto segv_and_exit;

	err = __get_user(pc,  &sf->info.si_regs.pc);
	err |= __get_user(npc, &sf->info.si_regs.npc);

	if ((pc | npc) & 3)
		goto segv_and_exit;

	/* 2. Restore the state */
	up_psr = regs->psr;
	err |= __copy_from_user(regs, &sf->info.si_regs, sizeof(struct pt_regs));

	/* User can only change condition codes and FPU enabling in %psr. */
	regs->psr = (up_psr & ~(PSR_ICC | PSR_EF))
		  | (regs->psr & (PSR_ICC | PSR_EF));

	/* Prevent syscall restart.  */
	pt_regs_clear_syscall(regs);

	err |= __get_user(fpu_save, &sf->fpu_save);
	if (fpu_save)
		err |= restore_fpu_state(regs, fpu_save);
	err |= __get_user(rwin_save, &sf->rwin_save);
	if (rwin_save)
		err |= restore_rwin_state(rwin_save);

	/* This is pretty much atomic, no amount locking would prevent
	 * the races which exist anyways.
	 */
	err |= __get_user(set.sig[0], &sf->info.si_mask);
	err |= __copy_from_user(&set.sig[1], &sf->extramask,
			        (_NSIG_WORDS-1) * sizeof(unsigned int));
			   
	if (err)
		goto segv_and_exit;

	sigdelsetmask(&set, ~_BLOCKABLE);
	set_current_blocked(&set);
	return;

segv_and_exit:
	force_sig(SIGSEGV, current);
}

asmlinkage void do_rt_sigreturn(struct pt_regs *regs)
{
	struct rt_signal_frame __user *sf;
	unsigned int psr, pc, npc;
	__siginfo_fpu_t __user *fpu_save;
	__siginfo_rwin_t __user *rwin_save;
	mm_segment_t old_fs;
	sigset_t set;
	stack_t st;
	int err;

	synchronize_user_stack();
	sf = (struct rt_signal_frame __user *) regs->u_regs[UREG_FP];
	if (!access_ok(VERIFY_READ, sf, sizeof(*sf)) ||
	    (((unsigned long) sf) & 0x03))
		goto segv;

	err = __get_user(pc, &sf->regs.pc);
	err |= __get_user(npc, &sf->regs.npc);
	err |= ((pc | npc) & 0x03);

	err |= __get_user(regs->y, &sf->regs.y);
	err |= __get_user(psr, &sf->regs.psr);

	err |= __copy_from_user(&regs->u_regs[UREG_G1],
				&sf->regs.u_regs[UREG_G1], 15 * sizeof(u32));

	regs->psr = (regs->psr & ~PSR_ICC) | (psr & PSR_ICC);

	/* Prevent syscall restart.  */
	pt_regs_clear_syscall(regs);

	err |= __get_user(fpu_save, &sf->fpu_save);
	if (!err && fpu_save)
		err |= restore_fpu_state(regs, fpu_save);
	err |= __copy_from_user(&set, &sf->mask, sizeof(sigset_t));
	
	err |= __copy_from_user(&st, &sf->stack, sizeof(stack_t));
	
	if (err)
		goto segv;
		
	regs->pc = pc;
	regs->npc = npc;
	
	/* It is more difficult to avoid calling this function than to
	 * call it and ignore errors.
	 */
	old_fs = get_fs();
	set_fs(KERNEL_DS);
	do_sigaltstack((const stack_t __user *) &st, NULL, (unsigned long)sf);
	set_fs(old_fs);

	err |= __get_user(rwin_save, &sf->rwin_save);
	if (!err && rwin_save) {
		if (restore_rwin_state(rwin_save))
			goto segv;
	}

	sigdelsetmask(&set, ~_BLOCKABLE);
	set_current_blocked(&set);
	return;
segv:
	force_sig(SIGSEGV, current);
}

/* Checks if the fp is valid */
static inline int invalid_frame_pointer(void __user *fp, int fplen)
{
	if ((((unsigned long) fp) & 7) ||
	    !__access_ok((unsigned long)fp, fplen) ||
	    ((sparc_cpu_model == sun4 || sparc_cpu_model == sun4c) &&
	     ((unsigned long) fp < 0xe0000000 && (unsigned long) fp >= 0x20000000)))
		return 1;
	
	return 0;
}

static inline void __user *get_sigframe(struct sigaction *sa, struct pt_regs *regs, unsigned long framesize)
{
	unsigned long sp = regs->u_regs[UREG_FP];

	/*
	 * If we are on the alternate signal stack and would overflow it, don't.
	 * Return an always-bogus address instead so we will die with SIGSEGV.
	 */
	if (on_sig_stack(sp) && !likely(on_sig_stack(sp - framesize)))
		return (void __user *) -1L;

	/* This is the X/Open sanctioned signal stack switching.  */
	if (sa->sa_flags & SA_ONSTACK) {
		if (sas_ss_flags(sp) == 0)
			sp = current->sas_ss_sp + current->sas_ss_size;
	}

	sp -= framesize;

	/* Always align the stack frame.  This handles two cases.  First,
	 * sigaltstack need not be mindful of platform specific stack
	 * alignment.  Second, if we took this signal because the stack
	 * is not aligned properly, we'd like to take the signal cleanly
	 * and report that.
	 */
	sp &= ~15UL;

	return (void __user *) sp;
}

static int setup_frame(struct k_sigaction *ka, struct pt_regs *regs,
		       int signo, sigset_t *oldset)
{
	struct signal_frame __user *sf;
	int sigframe_size, err, wsaved;
	void __user *tail;

	/* 1. Make sure everything is clean */
	synchronize_user_stack();

	wsaved = current_thread_info()->w_saved;

	sigframe_size = sizeof(*sf);
	if (used_math())
		sigframe_size += sizeof(__siginfo_fpu_t);
	if (wsaved)
		sigframe_size += sizeof(__siginfo_rwin_t);

	sf = (struct signal_frame __user *)
		get_sigframe(&ka->sa, regs, sigframe_size);

	if (invalid_frame_pointer(sf, sigframe_size))
		goto sigill_and_return;

	tail = sf + 1;

	/* 2. Save the current process state */
	err = __copy_to_user(&sf->info.si_regs, regs, sizeof(struct pt_regs));
	
	err |= __put_user(0, &sf->extra_size);

	if (used_math()) {
		__siginfo_fpu_t __user *fp = tail;
		tail += sizeof(*fp);
		err |= save_fpu_state(regs, fp);
		err |= __put_user(fp, &sf->fpu_save);
	} else {
		err |= __put_user(0, &sf->fpu_save);
	}
	if (wsaved) {
		__siginfo_rwin_t __user *rwp = tail;
		tail += sizeof(*rwp);
		err |= save_rwin_state(wsaved, rwp);
		err |= __put_user(rwp, &sf->rwin_save);
	} else {
		err |= __put_user(0, &sf->rwin_save);
	}

	err |= __put_user(oldset->sig[0], &sf->info.si_mask);
	err |= __copy_to_user(sf->extramask, &oldset->sig[1],
			      (_NSIG_WORDS - 1) * sizeof(unsigned int));
	if (!wsaved) {
		err |= __copy_to_user(sf, (char *) regs->u_regs[UREG_FP],
				      sizeof(struct reg_window32));
	} else {
		struct reg_window32 *rp;

		rp = &current_thread_info()->reg_window[wsaved - 1];
		err |= __copy_to_user(sf, rp, sizeof(struct reg_window32));
	}
	if (err)
		goto sigsegv;
	
	/* 3. signal handler back-trampoline and parameters */
	regs->u_regs[UREG_FP] = (unsigned long) sf;
	regs->u_regs[UREG_I0] = signo;
	regs->u_regs[UREG_I1] = (unsigned long) &sf->info;
	regs->u_regs[UREG_I2] = (unsigned long) &sf->info;

	/* 4. signal handler */
	regs->pc = (unsigned long) ka->sa.sa_handler;
	regs->npc = (regs->pc + 4);

	/* 5. return to kernel instructions */
	if (ka->ka_restorer)
		regs->u_regs[UREG_I7] = (unsigned long)ka->ka_restorer;
	else {
		regs->u_regs[UREG_I7] = (unsigned long)(&(sf->insns[0]) - 2);

		/* mov __NR_sigreturn, %g1 */
		err |= __put_user(0x821020d8, &sf->insns[0]);

		/* t 0x10 */
		err |= __put_user(0x91d02010, &sf->insns[1]);
		if (err)
			goto sigsegv;

		/* Flush instruction space. */
		flush_sig_insns(current->mm, (unsigned long) &(sf->insns[0]));
	}
	return 0;

sigill_and_return:
	do_exit(SIGILL);
	return -EINVAL;

sigsegv:
	force_sigsegv(signo, current);
	return -EFAULT;
}

static int setup_rt_frame(struct k_sigaction *ka, struct pt_regs *regs,
			  int signo, sigset_t *oldset, siginfo_t *info)
{
	struct rt_signal_frame __user *sf;
	int sigframe_size, wsaved;
	void __user *tail;
	unsigned int psr;
	int err;

	synchronize_user_stack();
	wsaved = current_thread_info()->w_saved;
	sigframe_size = sizeof(*sf);
	if (used_math())
		sigframe_size += sizeof(__siginfo_fpu_t);
	if (wsaved)
		sigframe_size += sizeof(__siginfo_rwin_t);
	sf = (struct rt_signal_frame __user *)
		get_sigframe(&ka->sa, regs, sigframe_size);
	if (invalid_frame_pointer(sf, sigframe_size))
		goto sigill;

	tail = sf + 1;
	err  = __put_user(regs->pc, &sf->regs.pc);
	err |= __put_user(regs->npc, &sf->regs.npc);
	err |= __put_user(regs->y, &sf->regs.y);
	psr = regs->psr;
	if (used_math())
		psr |= PSR_EF;
	err |= __put_user(psr, &sf->regs.psr);
	err |= __copy_to_user(&sf->regs.u_regs, regs->u_regs, sizeof(regs->u_regs));
	err |= __put_user(0, &sf->extra_size);

	if (psr & PSR_EF) {
		__siginfo_fpu_t *fp = tail;
		tail += sizeof(*fp);
		err |= save_fpu_state(regs, fp);
		err |= __put_user(fp, &sf->fpu_save);
	} else {
		err |= __put_user(0, &sf->fpu_save);
	}
	if (wsaved) {
		__siginfo_rwin_t *rwp = tail;
		tail += sizeof(*rwp);
		err |= save_rwin_state(wsaved, rwp);
		err |= __put_user(rwp, &sf->rwin_save);
	} else {
		err |= __put_user(0, &sf->rwin_save);
	}
	err |= __copy_to_user(&sf->mask, &oldset->sig[0], sizeof(sigset_t));
	
	/* Setup sigaltstack */
	err |= __put_user(current->sas_ss_sp, &sf->stack.ss_sp);
	err |= __put_user(sas_ss_flags(regs->u_regs[UREG_FP]), &sf->stack.ss_flags);
	err |= __put_user(current->sas_ss_size, &sf->stack.ss_size);
	
	if (!wsaved) {
		err |= __copy_to_user(sf, (char *) regs->u_regs[UREG_FP],
				      sizeof(struct reg_window32));
	} else {
		struct reg_window32 *rp;

		rp = &current_thread_info()->reg_window[wsaved - 1];
		err |= __copy_to_user(sf, rp, sizeof(struct reg_window32));
	}

	err |= copy_siginfo_to_user(&sf->info, info);

	if (err)
		goto sigsegv;

	regs->u_regs[UREG_FP] = (unsigned long) sf;
	regs->u_regs[UREG_I0] = signo;
	regs->u_regs[UREG_I1] = (unsigned long) &sf->info;
	regs->u_regs[UREG_I2] = (unsigned long) &sf->regs;

	regs->pc = (unsigned long) ka->sa.sa_handler;
	regs->npc = (regs->pc + 4);

	if (ka->ka_restorer)
		regs->u_regs[UREG_I7] = (unsigned long)ka->ka_restorer;
	else {
		regs->u_regs[UREG_I7] = (unsigned long)(&(sf->insns[0]) - 2);

		/* mov __NR_sigreturn, %g1 */
		err |= __put_user(0x821020d8, &sf->insns[0]);

		/* t 0x10 */
		err |= __put_user(0x91d02010, &sf->insns[1]);
		if (err)
			goto sigsegv;

		/* Flush instruction space. */
		flush_sig_insns(current->mm, (unsigned long) &(sf->insns[0]));
	}
	return 0;

sigill:
	do_exit(SIGILL);
	return -EINVAL;

sigsegv:
	force_sigsegv(signo, current);
	return -EFAULT;
}

static inline int
handle_signal(unsigned long signr, struct k_sigaction *ka,
	      siginfo_t *info, sigset_t *oldset, struct pt_regs *regs)
{
	int err;

	if (ka->sa.sa_flags & SA_SIGINFO)
		err = setup_rt_frame(ka, regs, signr, oldset, info);
	else
		err = setup_frame(ka, regs, signr, oldset);

	if (err)
		return err;

	block_sigmask(ka, signr);
	tracehook_signal_handler(signr, info, ka, regs, 0);

	return 0;
}

static inline void syscall_restart(unsigned long orig_i0, struct pt_regs *regs,
				   struct sigaction *sa)
{
	switch(regs->u_regs[UREG_I0]) {
	case ERESTART_RESTARTBLOCK:
	case ERESTARTNOHAND:
	no_system_call_restart:
		regs->u_regs[UREG_I0] = EINTR;
		regs->psr |= PSR_C;
		break;
	case ERESTARTSYS:
		if (!(sa->sa_flags & SA_RESTART))
			goto no_system_call_restart;
		/* fallthrough */
	case ERESTARTNOINTR:
		regs->u_regs[UREG_I0] = orig_i0;
		regs->pc -= 4;
		regs->npc -= 4;
	}
}

/* Note that 'init' is a special process: it doesn't get signals it doesn't
 * want to handle. Thus you cannot kill init even with a SIGKILL even by
 * mistake.
 */
static void do_signal(struct pt_regs *regs, unsigned long orig_i0)
{
	struct k_sigaction ka;
	int restart_syscall;
	sigset_t *oldset;
	siginfo_t info;
	int signr;

	/* It's a lot of work and synchronization to add a new ptrace
	 * register for GDB to save and restore in order to get
	 * orig_i0 correct for syscall restarts when debugging.
	 *
	 * Although it should be the case that most of the global
	 * registers are volatile across a system call, glibc already
	 * depends upon that fact that we preserve them.  So we can't
	 * just use any global register to save away the orig_i0 value.
	 *
	 * In particular %g2, %g3, %g4, and %g5 are all assumed to be
	 * preserved across a system call trap by various pieces of
	 * code in glibc.
	 *
	 * %g7 is used as the "thread register".   %g6 is not used in
	 * any fixed manner.  %g6 is used as a scratch register and
	 * a compiler temporary, but it's value is never used across
	 * a system call.  Therefore %g6 is usable for orig_i0 storage.
	 */
	if (pt_regs_is_syscall(regs) && (regs->psr & PSR_C))
		regs->u_regs[UREG_G6] = orig_i0;

	if (test_thread_flag(TIF_RESTORE_SIGMASK))
		oldset = &current->saved_sigmask;
	else
		oldset = &current->blocked;

	signr = get_signal_to_deliver(&info, &ka, regs, NULL);

	/* If the debugger messes with the program counter, it clears
	 * the software "in syscall" bit, directing us to not perform
	 * a syscall restart.
	 */
	restart_syscall = 0;
	if (pt_regs_is_syscall(regs) && (regs->psr & PSR_C)) {
		restart_syscall = 1;
		orig_i0 = regs->u_regs[UREG_G6];
	}


	if (signr > 0) {
		if (restart_syscall)
			syscall_restart(orig_i0, regs, &ka.sa);
		if (handle_signal(signr, &ka, &info, oldset, regs) == 0) {
			/* a signal was successfully delivered; the saved
			 * sigmask will have been stored in the signal frame,
			 * and will be restored by sigreturn, so we can simply
			 * clear the TIF_RESTORE_SIGMASK flag.
			 */
			if (test_thread_flag(TIF_RESTORE_SIGMASK))
				clear_thread_flag(TIF_RESTORE_SIGMASK);
		}
		return;
	}
	if (restart_syscall &&
	    (regs->u_regs[UREG_I0] == ERESTARTNOHAND ||
	     regs->u_regs[UREG_I0] == ERESTARTSYS ||
	     regs->u_regs[UREG_I0] == ERESTARTNOINTR)) {
		/* replay the system call when we are done */
		regs->u_regs[UREG_I0] = orig_i0;
		regs->pc -= 4;
		regs->npc -= 4;
		pt_regs_clear_syscall(regs);
	}
	if (restart_syscall &&
	    regs->u_regs[UREG_I0] == ERESTART_RESTARTBLOCK) {
		regs->u_regs[UREG_G1] = __NR_restart_syscall;
		regs->pc -= 4;
		regs->npc -= 4;
		pt_regs_clear_syscall(regs);
	}

	/* if there's no signal to deliver, we just put the saved sigmask
	 * back
	 */
	if (test_thread_flag(TIF_RESTORE_SIGMASK)) {
		clear_thread_flag(TIF_RESTORE_SIGMASK);
		set_current_blocked(&current->saved_sigmask);
	}
}

void do_notify_resume(struct pt_regs *regs, unsigned long orig_i0,
		      unsigned long thread_info_flags)
{
	if (thread_info_flags & (_TIF_SIGPENDING | _TIF_RESTORE_SIGMASK))
		do_signal(regs, orig_i0);
	if (thread_info_flags & _TIF_NOTIFY_RESUME) {
		clear_thread_flag(TIF_NOTIFY_RESUME);
		tracehook_notify_resume(regs);
	}
}

asmlinkage int
do_sys_sigstack(struct sigstack __user *ssptr, struct sigstack __user *ossptr,
		unsigned long sp)
{
	int ret = -EFAULT;

	/* First see if old state is wanted. */
	if (ossptr) {
		if (put_user(current->sas_ss_sp + current->sas_ss_size,
			     &ossptr->the_stack) ||
		    __put_user(on_sig_stack(sp), &ossptr->cur_status))
			goto out;
	}

	/* Now see if we want to update the new state. */
	if (ssptr) {
		char *ss_sp;

		if (get_user(ss_sp, &ssptr->the_stack))
			goto out;
		/* If the current stack was set with sigaltstack, don't
		   swap stacks while we are on it.  */
		ret = -EPERM;
		if (current->sas_ss_sp && on_sig_stack(sp))
			goto out;

		/* Since we don't know the extent of the stack, and we don't
		   track onstack-ness, but rather calculate it, we must
		   presume a size.  Ho hum this interface is lossy.  */
		current->sas_ss_sp = (unsigned long)ss_sp - SIGSTKSZ;
		current->sas_ss_size = SIGSTKSZ;
	}
	ret = 0;
out:
	return ret;
}
