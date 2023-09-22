/**
 * \file            lwesp_sys_fuzz.c
 * \brief           System dependant functions for an embedded fuzzer
 */

/*
 * Copyright (c) 2022 Tilen MAJERLE
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE
 * AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * Based on lwesp_sys_posix.c of LwESP - Lightweight ESP-AT parser library.
 *
 * Original Author:          Tilen MAJERLE <tilen@majerle.eu>
 * Original Author:          imi415 <imi415.public@gmail.com>
 * Version:         v1.1.2-dev
 */
#include <stdlib.h>
#include "system/lwesp_sys.h"

#if !__DOXYGEN__

typedef void* (*lwesp_sys_posix_thread_fn) (void*);

/**
 * \brief           Custom message queue implementation for WIN32
 */
typedef struct {
    lwesp_sys_sem_t sem_not_empty;              /*!< Semaphore indicates not empty */
    lwesp_sys_sem_t sem_not_full;               /*!< Semaphore indicates not full */
    lwesp_sys_sem_t sem;                        /*!< Semaphore to lock access */
    size_t in, out, size;
    void* entries[1];
} fuzz_mbox_t;

/**
 * \brief           Check if message box is full
 * \param[in]       m: Message box handle
 * \return          1 if full, 0 otherwise
 */
static uint8_t
mbox_is_full(fuzz_mbox_t* m) {
    size_t size = 0;
    if (m->in > m->out) {
        size = (m->in - m->out);
    } else if (m->out > m->in) {
        size = m->size - m->out + m->in;
    }
    return size == m->size - 1;
}

/**
 * \brief           Check if message box is empty
 * \param[in]       m: Message box handle
 * \return          1 if empty, 0 otherwise
 */
static uint8_t
mbox_is_empty(fuzz_mbox_t* m) {
    return m->in == m->out;
}

uint8_t
lwesp_sys_init(void) {
    return 1;
}

uint32_t
lwesp_sys_now(void) {
    return 1; //Stub: Not required for most features.
}

// Handler for deadlock cases.
// The fuzzer harness only has a single thread, hence any wait implies a deadlock..
static void on_deadlock()
{
	// Cause a crash for the fuzzer to notice.
	*(volatile uint8_t*)128 = 1;
}
// Handler for invalid unlocking behaviour (e.g. unlocking a non-locked mutex).
static void on_invalid_unlock()
{
	// Cause a crash for the fuzzer to notice.
	*(volatile uint8_t*)129 = 1;
}
// Handler for very specific cases of detected (heap) corruption.
static void on_corruption()
{
	// Cause a crash for the fuzzer to notice.
	*(volatile uint8_t*)130 = 1;
}

#if LWESP_CFG_OS
static uint8_t sys_locked = 0;
uint8_t
lwesp_sys_protect(void) {
	//No multi threading / interrupts in the fuzzer harness, so no atomicity is required.
	if (sys_locked) on_deadlock();
	sys_locked = 1;
    return 1;
}

uint8_t
lwesp_sys_unprotect(void) {
	if (!sys_locked) on_invalid_unlock();
	sys_locked = 0;
    return 1;
}

uint8_t
lwesp_sys_mutex_create(lwesp_sys_mutex_t* p) {
    *p = malloc(sizeof(uint8_t));
    if (*p == NULL) {
        return 0;
    }
	**p = 0;
    return 1;
}

uint8_t
lwesp_sys_mutex_delete(lwesp_sys_mutex_t* p) {
	**p = 2;
    free(*p);
    return 1;
}

uint8_t
lwesp_sys_mutex_lock(lwesp_sys_mutex_t* p) {
	if (**p > 1) on_corruption();
	//No multi threading / interrupts in the fuzzer harness, so no atomicity is required.
	if (**p) on_deadlock();
	**p = 1;
    return 1;
}

uint8_t
lwesp_sys_mutex_unlock(lwesp_sys_mutex_t* p) {
	if (**p > 1) on_corruption();
	if (!**p) on_invalid_unlock();
	**p = 0;
    return 1;
}

uint8_t
lwesp_sys_mutex_isvalid(lwesp_sys_mutex_t* p) {
    if (p == NULL) {
        return 0;
    }
	if (**p > 1) on_corruption();
    return 1;
}

uint8_t
lwesp_sys_mutex_invalid(lwesp_sys_mutex_t* p) {
    *p = NULL;
    return 1;
}

uint8_t
lwesp_sys_sem_create(lwesp_sys_sem_t* p, uint8_t cnt) {
    *p = malloc(sizeof(int));
    if (*p == NULL) {
        return 0;
    }

    /* 
	* This function assumes a binary semaphore
    * should be created in some ports.
    */
	**p = !!cnt;
    return 1;
}

uint8_t
lwesp_sys_sem_delete(lwesp_sys_sem_t* p) {
    free(*p);

    return 1;
}

uint32_t
lwesp_sys_sem_wait(lwesp_sys_sem_t* p, uint32_t timeout) {
	// No threading nor interrupt support present, i.e. the counter cannot become negative.
	if (**p < 0 || **p >= 0x10000) on_corruption();
	if (**p == 0)
	{
		if (timeout == 0) on_deadlock();
		//If a timeout is set, immediately return.
		return LWESP_SYS_TIMEOUT;
	}
	--**p;
	//Should return the waited time,
	// but all callers in lwesp only compare it against LWESP_SYS_TIMEOUT.
    return 0;
}

uint8_t
lwesp_sys_sem_release(lwesp_sys_sem_t* p) {
	//Assume that the semaphore shouldn't normally reach +64K.
	if (**p < 0 || **p >= 0x10000) on_corruption();
	++**p;
    return 1;
}

uint8_t
lwesp_sys_sem_isvalid(lwesp_sys_sem_t* p) {
    if (p == NULL) {
        return 0;
    }
	//Assume that the semaphore shouldn't normally reach +64K.
	if (**p >= 0x10000) on_corruption();
    return 1;
}

uint8_t
lwesp_sys_sem_invalid(lwesp_sys_sem_t* p) {
    *p = NULL;

    return 1;
}

uint8_t
lwesp_sys_mbox_create(lwesp_sys_mbox_t* b, size_t size) {
    fuzz_mbox_t* mbox;

    *b = 0;

    mbox = malloc(sizeof(*mbox) + size * sizeof(void*));
    if (mbox != NULL) {
        memset(mbox, 0x00, sizeof(*mbox));
        mbox->size = size + 1;                  /* Set it to 1 more as cyclic buffer has only one less than size */
        lwesp_sys_sem_create(&mbox->sem, 1);
        lwesp_sys_sem_create(&mbox->sem_not_empty, 0);
        lwesp_sys_sem_create(&mbox->sem_not_full, 0);
        *b = mbox;
    }
    return *b != NULL;
}

uint8_t
lwesp_sys_mbox_delete(lwesp_sys_mbox_t* b) {
    fuzz_mbox_t* mbox = *b;
    lwesp_sys_sem_delete(&mbox->sem);
    lwesp_sys_sem_delete(&mbox->sem_not_full);
    lwesp_sys_sem_delete(&mbox->sem_not_empty);
    free(mbox);
    return 1;
}

uint32_t
lwesp_sys_mbox_put(lwesp_sys_mbox_t* b, void* m) {
    fuzz_mbox_t* mbox = *b;
    uint32_t time = lwesp_sys_now();            /* Get start time */

    lwesp_sys_sem_wait(&mbox->sem, 0);          /* Wait for access */

    /*
     * Since function is blocking until ready to write something to queue,
     * wait and release the semaphores to allow other threads
     * to process the queue before we can write new value.
     */
    while (mbox_is_full(mbox)) {
        lwesp_sys_sem_release(&mbox->sem);      /* Release semaphore */
        lwesp_sys_sem_wait(&mbox->sem_not_full, 0); /* Wait for semaphore indicating not full */
        lwesp_sys_sem_wait(&mbox->sem, 0);      /* Wait availability again */
    }
    mbox->entries[mbox->in] = m;
    if (++mbox->in >= mbox->size) {
        mbox->in = 0;
    }
    lwesp_sys_sem_release(&mbox->sem_not_empty);/* Signal non-empty state */
    lwesp_sys_sem_release(&mbox->sem);          /* Release access for other threads */
    return lwesp_sys_now() - time;
}

uint32_t
lwesp_sys_mbox_get(lwesp_sys_mbox_t* b, void** m, uint32_t timeout) {
    fuzz_mbox_t* mbox = *b;
    uint32_t time;

    time = lwesp_sys_now();

    /* Get exclusive access to message queue */
    if (lwesp_sys_sem_wait(&mbox->sem, timeout) == LWESP_SYS_TIMEOUT) {
        return LWESP_SYS_TIMEOUT;
    }
    while (mbox_is_empty(mbox)) {
        lwesp_sys_sem_release(&mbox->sem);
        if (lwesp_sys_sem_wait(&mbox->sem_not_empty, timeout) == LWESP_SYS_TIMEOUT) {
            return LWESP_SYS_TIMEOUT;
        }
        lwesp_sys_sem_wait(&mbox->sem, timeout);
    }
    *m = mbox->entries[mbox->out];
    if (++mbox->out >= mbox->size) {
        mbox->out = 0;
    }
    lwesp_sys_sem_release(&mbox->sem_not_full);
    lwesp_sys_sem_release(&mbox->sem);

    return lwesp_sys_now() - time;
}

uint8_t
lwesp_sys_mbox_putnow(lwesp_sys_mbox_t* b, void* m) {
    fuzz_mbox_t* mbox = *b;

    lwesp_sys_sem_wait(&mbox->sem, 0);
    if (mbox_is_full(mbox)) {
        lwesp_sys_sem_release(&mbox->sem);
        return 0;
    }
    mbox->entries[mbox->in] = m;
    if (mbox->in == mbox->out) {
        lwesp_sys_sem_release(&mbox->sem_not_empty);
    }
    if (++mbox->in >= mbox->size) {
        mbox->in = 0;
    }
    lwesp_sys_sem_release(&mbox->sem);
    return 1;
}

uint8_t
lwesp_sys_mbox_getnow(lwesp_sys_mbox_t* b, void** m) {
    fuzz_mbox_t* mbox = *b;

    lwesp_sys_sem_wait(&mbox->sem, 0);          /* Wait exclusive access */
    if (mbox->in == mbox->out) {
        lwesp_sys_sem_release(&mbox->sem);      /* Release access */
        return 0;
    }

    *m = mbox->entries[mbox->out];
    if (++mbox->out >= mbox->size) {
        mbox->out = 0;
    }
    lwesp_sys_sem_release(&mbox->sem_not_full); /* Queue not full anymore */
    lwesp_sys_sem_release(&mbox->sem);          /* Release semaphore */
    return 1;
}

uint8_t
lwesp_sys_mbox_isvalid(lwesp_sys_mbox_t* b) {
    return b != NULL && *b != NULL;
}

uint8_t
lwesp_sys_mbox_invalid(lwesp_sys_mbox_t* b) {
    *b = LWESP_SYS_MBOX_NULL;
    return 1;
}

uint8_t
lwesp_sys_thread_create(lwesp_sys_thread_t* t, const char* name,
                        lwesp_sys_thread_fn thread_func, void* const arg,
                        size_t stack_size, lwesp_sys_thread_prio_t prio) {
	//Stub
	//Hack: Release the 'thread started' semaphore, so lwesp_init can run through.
	if (name != NULL && !strcmp(name, "lwesp_produce")) {
		lwesp_sys_sem_release((lwesp_sys_sem_t*)arg);
	} else if (name != NULL && !strcmp(name, "lwesp_process")) {
		lwesp_sys_sem_release((lwesp_sys_sem_t*)arg);
	}
    *t = (void*)1;

    return 1;
}

uint8_t
lwesp_sys_thread_terminate(lwesp_sys_thread_t* t) {
    if (t != NULL) {
		if (*t != (void*)1) on_corruption();
    }

    return 1;
}

uint8_t
lwesp_sys_thread_yield(void) {
    /* Not implemented. */
    return 1;
}

#endif /* LWESP_CFG_OS */
#endif /* !__DOXYGEN__ */
