/* GDC -- D front-end for GCC
   Copyright (C) 2004 David Friedman

   Modified by
    Iain Buclaw, (C) 2010-2011

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#include "config.h"
#include "system.h"
#include "coretypes.h"
#include "tm.h"

#include "d-confdefs.h"

#include "gcc.h"

/* This bit is set if we saw a `-xfoo' language specification.  */
#define LANGSPEC        (1<<1)
/* This bit is set if they did `-lm' or `-lmath'.  */
#define MATHLIB         (1<<2)
/* This bit is set if they did `-pthread'.  */
#define WITHTHREAD      (1<<3)
/* This bit is set if they did `-lrt'.  */
#define TIMERLIB        (1<<4)
/* This bit is set if they did `-lc'.  */
#define WITHLIBC        (1<<6)
/* This bit is set if the arguments is a D source file. */
#define D_SOURCE_FILE   (1<<7)
/* This bit is set when the argument should not be passed to gcc or the backend */
#define REMOVE_ARG      (1<<8)

#ifndef MATH_LIBRARY
#define MATH_LIBRARY "-lm"
#endif
#ifndef MATH_LIBRARY_PROFILE
#define MATH_LIBRARY_PROFILE MATH_LIBRARY
#endif

#define RT_LIBRARY "-lrt"
#define RT_LIBRARY_PROFILE RT_LIBRARY

#ifndef LIBPHOBOS
#define LIBPHOBOS "-lgphobos"
#endif
#ifndef LIBPHOBOS_PROFILE
#define LIBPHOBOS_PROFILE LIBPHOBOS
#endif

/* This macro allows casting away const-ness to pass -Wcast-qual
   warnings.  DO NOT USE THIS UNLESS YOU REALLY HAVE TO!  It should
   only be used in certain specific cases.  One valid case is where
   the C standard definitions or prototypes force you to.  E.g. if you
   need to free a const object, or if you pass a const string to
   execv, et al. */
#ifndef CONST_CAST
#define CONST_CAST(TYPE,X) ((__extension__(union {const TYPE _q; TYPE _nq;})(X))._nq)
#endif

static char** all_d_sources = NULL;
static unsigned n_all_d_sources = 0;
static char * output_directory_option = NULL;
static int output_parents_option = 0;
static char * only_source_option = NULL;
    
/* Whether we need -pthread flag. */
extern int need_pthreads;

void
lang_specific_driver (int *in_argc, const char *const **in_argv,
                      int *in_added_libraries)
{
    int i, j;

    /* If nonzero, the user gave us the `-p' or `-pg' flag.  */
    int saw_profile_flag = 0;

    /* If nonzero, the user gave us the `-v' flag.  */
    int saw_verbose_flag = 0;

    /* Used by -debuglib */
    int saw_debug_flag = 0;

    /* This is a tristate:
       -1 means we should not link in libphobos
       0  means we should link in libphobos if it is needed
       1  means libphobos is needed and should be linked in.  */
    int library = 0;

    /* If nonzero, use the standard D runtime library when linking with
       standard libraries. */
    int phobos = 1;

    /* The number of arguments being added to what's in argv, other than
       libraries.  We use this to track the number of times we've inserted
       -xd/-xnone.  */
    int added = 0;

    /* Used to track options that take arguments, so we don't go wrapping
       those with -xd/-xnone.  */
    const char *quote = NULL;

    /* The new argument list will be contained in this.  */
    const char **arglist;

    /* Nonzero if we saw a `-xfoo' language specification on the
       command line.  Used to avoid adding our own -xd if the user
       already gave a language for the file.  */
    int saw_speclang = 0;

    /* "-lm" or "-lmath" if it appears on the command line.  */
    const char *saw_math = 0;

    /* "-pthread" if it appears on the command line.  */
    const char *saw_pthread = 0;

    /* "-lrt" if it appears on the command line.  */
    const char *saw_librt = 0;

    /* "-lc" if it appears on the command line.  */
    const char *saw_libc = 0;

    /* An array used to flag each argument that needs a bit set for
       LANGSPEC, MATHLIB, WITHTHREAD, or WITHLIBC.  */
    int *args;

    /* By default, we throw on the math library if we have one.  */
    int need_math = (MATH_LIBRARY[0] != '\0');

    /* True if we saw -static. */
    int static_link = 0;

    /* True if we should add -shared-libgcc to the command-line.  */
    int shared_libgcc = 1;

    /* True if libphobos should be linked statically.  */
    int static_phobos = 1;

    /* The total number of arguments with the new stuff.  */
    int argc;

    /* The argument list.  */
    const char *const *argv;

    /* What default library to use instead of phobos */
    const char *defaultlib = NULL;

    /* What debug library to use instead of phobos */
    const char *debuglib = NULL;

    /* The number of libraries added in.  */
    int added_libraries;

    /* The total number of arguments with the new stuff.  */
    int num_args = 1;

    argc = *in_argc;
    argv = *in_argv;
    added_libraries = *in_added_libraries;

    args = (int *) xcalloc (argc, sizeof (int));

    /* Keep track of all source files */
    n_all_d_sources = 0;

    for (i = 1; i < argc; i++)
    {
        /* If the previous option took an argument, we swallow it here.  */
        if (quote)
        {
            quote = NULL;
            continue;
        }

        /* We don't do this anymore, since we don't get them with minus
           signs on them.  */
        if (argv[i][0] == '\0' || argv[i][1] == '\0')
            continue;

        if (argv[i][0] == '-')
        {
            if (strcmp (argv[i], "-nostdlib") == 0
                || strcmp (argv[i], "-nodefaultlibs") == 0)
            {
                library = -1;
            }
            else if (strcmp (argv[i], "-nophoboslib") == 0)
            {
                added = 1; // force argument rebuild
                phobos = 0;
                args[i] |= REMOVE_ARG;
            }
            else if (strcmp (argv[i], "-defaultlib") == 0)
            {
                added = 1;
                phobos = 0;
                args[i] |= REMOVE_ARG;
                if (defaultlib != NULL)
                    free(CONST_CAST(char *, defaultlib));
                if (i + 1 == argc)
                {
                    error ("missing argument to '%s' option", argv[i] + 1);
                    break;
                }
                defaultlib = (const char *) xmalloc(sizeof(char) * (strlen(argv[++i]) + 3));
                strcpy(CONST_CAST(char *, defaultlib), "-l");
                strcat(CONST_CAST(char *, defaultlib), argv[i]);
                args[i] |= REMOVE_ARG;
            }
            else if (strcmp (argv[i], "-debuglib") == 0)
            {
                added = 1;
                phobos = 0;
                args[i] |= REMOVE_ARG;
                if (debuglib != NULL)
                    free(CONST_CAST(char *, debuglib));
                if (i + 1 == argc)
                {
                    error ("missing argument to '%s' option", argv[i] + 1);
                    break;
                }
                debuglib = (const char *) xmalloc(sizeof(char) * (strlen(argv[++i]) + 3));
                strcpy(CONST_CAST(char *, debuglib), "-l");
                strcat(CONST_CAST(char *, debuglib), argv[i]);
                args[i] |= REMOVE_ARG;
            }
            else if (strncmp (argv[i], "-l", 2) == 0)
            {
	      const char * arg;
	      if (argv[i][2] != '\0')
		arg = argv[i]+2;
	      else if ((argv[i+1]) != NULL)
		/* We need to swallow arg on next loop.  */
		quote = arg = argv[i+1];
  	      else  /* Error condition, message will be printed later.  */
		arg = "";

              if (strcmp (arg, "m") == 0
                  || strcmp (arg, "math") == 0
                  || strcmp (arg, MATH_LIBRARY) == 0)
              {
                  args[i] |= MATHLIB;
                  need_math = 0;
              }
              else if (strcmp (arg, "rt") == 0)
                  args[i] |= TIMERLIB;
              else if (strcmp (argv[i], "c") == 0)
                  args[i] |= WITHLIBC;
              else
                  /* Unrecognised libraries (e.g. -ltango) may require libphobos.  */
                  library = (library == 0) ? 1 : library;
            }
            else if (strcmp (argv[i], "-pthread") == 0)
                args[i] |= WITHTHREAD;
            else if (strcmp (argv[i], "-pg") == 0 || strcmp (argv[i], "-p") == 0)
                saw_profile_flag++;
            else if (strcmp (argv[i], "-v") == 0)
                saw_verbose_flag = 1;
            else if (strcmp (argv[i], "-g") == 0)
                saw_debug_flag = 1;
            else if (strncmp (argv[i], "-x", 2) == 0)
            {
	      const char * arg;
	      if (argv[i][2] != '\0')
		arg = argv[i]+2;
	      else if ((argv[i+1]) != NULL)
		/* We need to swallow arg on next loop.  */
		quote = arg = argv[i+1];
  	      else  /* Error condition, message will be printed later.  */
		arg = "";
	      if (library == 0 && (strcmp (arg, "d") == 0))
		library = 1;
		
                saw_speclang = 1;
            }
            else if (((argv[i][2] == '\0'
                            && strchr ("bBVDUoeTuIYmLiA", argv[i][1]) != NULL)
                        || strcmp (argv[i], "-Xlinker") == 0
                        || strcmp (argv[i], "-Tdata") == 0))
                quote = argv[i];
            else if ((argv[i][2] == '\0'
                        && strchr ("cSEM", argv[i][1]) != NULL)
                    || strcmp (argv[i], "-MM") == 0
                    || strcmp (argv[i], "-fsyntax-only") == 0)
            {
                /* Don't specify libraries if we won't link, since that would
                   cause a warning.  */
                library = -1;
            }
            else if (strcmp (argv[i], "-static") == 0)
                static_link = 1;
            else if (strcmp (argv[i], "-static-libgcc") == 0)
                shared_libgcc = 0;
            else if (strcmp (argv[i], "-static-libphobos") == 0)
            {
                static_phobos = 1;
                args[i] |= REMOVE_ARG;
            }
            else if (strncmp (argv[i], "-fonly=", 7) == 0)
            {
                int len;

                args[i] |= REMOVE_ARG;
                const char * only_source_arg = argv[i];

                len = strlen(only_source_arg);
                if (len <= 2 || only_source_arg[len-1] != 'd' ||
                        only_source_arg[len-2] != '.')
                {
                    only_source_option = concat(only_source_arg, ".d", NULL);
                }
                else
                {
                    only_source_option = xstrdup(only_source_arg);
                }
            }
            else if (strncmp (argv[i], "-fod=", 5) == 0)
            {
                args[i] |= REMOVE_ARG;
                output_directory_option = xstrdup(argv[i] + 5);
                fprintf(stderr, "** outputdir = '%s'\n", output_directory_option);
            }
            else if (strcmp (argv[i], "-fop") == 0)
            {
                args[i] |= REMOVE_ARG;
                output_parents_option = 1;
                fprintf(stderr, "** output parents\n");
            }
            else if (DEFAULT_WORD_SWITCH_TAKES_ARG (&argv[i][1]))
                i++;
            else
                /* Pass other options through.  */
                continue;
        }
        else
        {
            int len;

            if (library == 0)
                library = 1;

            len = strlen (argv[i]);
            if (len > 2
                    && (argv[i][len - 1] == 'd')
                    && (argv[i][len - 2] == '.'))
            {
                n_all_d_sources++;
                args[i] |= D_SOURCE_FILE;
            }
        }
    }

    if (quote)
        fatal ("argument to `%s' missing\n", quote);

    if (only_source_option)
    {
        all_d_sources = (char **) xmalloc (n_all_d_sources * sizeof(char *));
        n_all_d_sources = 0; /* will be incremented again below */
    }

    /* If we know we don't have to do anything, bail now.  */
    if (! added && library <= 0 && ! only_source_option)
    {
        free (args);
        return;
    }

    /* There's no point adding -shared-libgcc if we don't have a shared
       libgcc.  */
#ifndef ENABLE_SHARED_LIBGCC
    shared_libgcc = 0;
#endif

    /* Make sure to have room for the trailing NULL argument.  */
    /* There is one extra argument added here for the runtime
       library: -lgphobos.  The -pthread argument is added by
       setting need_pthreads. */
    num_args = argc + added + need_math + shared_libgcc + (library > 0) * 4 + 2;
    arglist = (const char **) xmalloc (num_args * sizeof (char *));

    i = 0;
    j = 0;

    /* Copy the 0th argument, i.e., the name of the program itself.  */
    arglist[i++] = argv[j++];

    /* NOTE: We start at 1 now, not 0.  */
    while (i < argc)
    {
        if (args[i] & REMOVE_ARG)
        {
            ++i;
            continue;
        }

        arglist[j] = argv[i];

        /* Make sure -lphobos is before the math library, since libphobos
           itself uses those math routines.  */
        if (!saw_math && (args[i] & MATHLIB) && library > 0)
        {
            --j;
            saw_math = argv[i];
        }

        if (!saw_pthread && (args[i] & WITHTHREAD) && library > 0)
        {
            --j;
            saw_pthread = argv[i];
        }

        if (!saw_librt && (args[i] & TIMERLIB) && library > 0)
        {
            --j;
            saw_librt = argv[i];
        }

        if (!saw_libc && (args[i] & WITHLIBC) && library > 0)
        {
            --j;
            saw_libc = argv[i];
        }

        if (args[i] & D_SOURCE_FILE)
        {
            if (all_d_sources)
                all_d_sources[n_all_d_sources++] = xstrdup(arglist[j]);
            if ( only_source_option )
            {
                j--;
            }

        }

        i++;
        j++;
    }

    if (only_source_option)
    {
        arglist[j++] = only_source_option;
        arglist[j++] = only_source_option + 7;
    }

    /* Add `-lgphobos' if we haven't already done so.  */
    if (library > 0 && phobos)
    {
        arglist[j++] = saw_profile_flag ? LIBPHOBOS_PROFILE : LIBPHOBOS;
        added_libraries++;
    }
    else if (saw_debug_flag && debuglib)
    {
        arglist[j++] = debuglib;
        added_libraries++;
    }
    else if (defaultlib)
    {
        arglist[j++] = defaultlib;
        added_libraries++;
    }

    if (saw_math)
        arglist[j++] = saw_math;
    else if (library > 0 && need_math)
    {
        arglist[j++] = saw_profile_flag ? MATH_LIBRARY_PROFILE : MATH_LIBRARY;
        added_libraries++;
    }

    if (saw_pthread)
        arglist[j++] = saw_pthread;
    else if (library > 0)
    {
        /* Handled in gcc.c  */
        need_pthreads = 1;
    }

    if (saw_librt)
        arglist[j++] = saw_librt;
#if TARGET_LINUX
    /* Only link if linking statically and target platform supports. */
    else if (library > 0 && (static_phobos || static_link))
    {
        arglist[j++] = saw_profile_flag ? RT_LIBRARY_PROFILE : RT_LIBRARY;
        added_libraries++;
    }
#endif

    if (saw_libc)
        arglist[j++] = saw_libc;

    if (shared_libgcc && !static_link)
        arglist[j++] = "-shared-libgcc";

    arglist[j] = NULL;

    *in_argc = j;
    *in_argv = arglist;
    *in_added_libraries = added_libraries;
}

/* Called before linking.  Returns 0 on success and -1 on failure.  */
int lang_specific_pre_link (void)  /* Not used for D.  */
{
    return 0;
}

/* Number of extra output files that lang_specific_pre_link may generate.  */
int lang_specific_extra_outfiles = 0;  /* Not used for D.  */

/* Table of language-specific spec functions.  */
const struct spec_function lang_specific_spec_functions[] =
{
  { 0, 0 }  /* Not used for D.  */
};
