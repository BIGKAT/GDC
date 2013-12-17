/* GDC -- D front-end for GCC
   Copyright (C) 2013 Free Software Foundation, Inc.

   GCC is free software; you can redistribute it and/or modify it under
   the terms of the GNU General Public License as published by the Free
   Software Foundation; either version 3, or (at your option) any later
   version.

   GCC is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or
   FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
   for more details.

   You should have received a copy of the GNU General Public License
   along with GCC; see the file COPYING3.  If not see
   <http://www.gnu.org/licenses/>.
*/

// GNU/GCC threads interface routines for D.
// This must match gthr-posix.h

module gcc.gthr_posix;

// POSIX threads specific definitions.
// Easy, since the interface is just one-to-one mapping.

import core.sys.posix.pthread;

alias gthread_key_t   = pthread_key_t;
alias gthread_once_t  = pthread_once_t;
alias gthread_mutex_t = pthread_mutex_t;

//enum GTHREAD_MUTEX_INIT = PTHREAD_MUTEX_INITIALIZER;
//enum GTHREAD_ONCE_INIT = PTHREAD_ONCE_INIT;

// Backend thread functions
extern(C):

// TODO: FreeBSD and Solaris exposes a dummy POSIX threads
// interface that will need to be handled here.
int gthread_active_p()
{
  return 1;
}

int gthread_once(gthread_once_t* once, void function() func)
{
  if (gthread_active_p())
    return pthread_once(once, func);
  else
    return -1;
}

int gthread_key_create(gthread_key_t* key, void function(void*) dtor)
{
  return pthread_key_create(key, dtor);
}

int gthread_key_delete(gthread_key_t key)
{
  return pthread_key_delete(key);
}

void* gthread_getspecific(gthread_key_t key)
{
  return pthread_getspecific(key);
}

int gthread_setspecific(gthread_key_t key, in void* ptr)
{
  return pthread_setspecific(key, ptr);
}

void gthread_mutex_init_function(gthread_mutex_t* mutex)
{
  if (gthread_active_p())
    pthread_mutex_init(mutex, null);
}

int gthread_mutex_destroy(gthread_mutex_t* mutex)
{
  if (gthread_active_p())
    return pthread_mutex_destroy(mutex);
  else
    return 0;
}

int gthread_mutex_lock(gthread_mutex_t* mutex)
{
  if (gthread_active_p())
    return pthread_mutex_lock(mutex);
  else
    return 0;
}

int gthread_mutex_trylock(gthread_mutex_t* mutex)
{
  if (gthread_active_p())
    return pthread_mutex_trylock(mutex);
  else
    return 0;
}

int gthread_mutex_unlock(gthread_mutex_t* mutex)
{
  if (gthread_active_p())
    return pthread_mutex_unlock(mutex);
  else
    return 0;
}

