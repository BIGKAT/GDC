
/**
 * C's &lt;time.h&gt;
 * Authors: Walter Bright, Digital Mars, www.digitalmars.com
 * License: Public Domain
 * Macros:
 *	WIKI=Phobos/StdCTime
 */

module std.c.time;

private import std.c.stddef;
private import std.stdint;

extern (C):

version (GNU)
{
    public import gcc.config.libc : CLOCKS_PER_SEC, clock_t, time_t, tm;
    /*
    alias gcc.config.libc.CLOCKS_PER_SEC CLOCKS_PER_SEC;
    alias gcc.config.libc.clock_t clock_t;
    alias gcc.config.libc.time_t time_t;
    alias gcc.config.libc.tm tm;
    */
    extern int daylight;
    extern int timezone;
    extern int altzone;
    extern char *tzname[2];
    version (Windows)
    {
	const clock_t CLK_TCK        = 1000;
    }
    // Else: not implemented yet.  Could be be a constant or
    // a sysconf() call depending on the OS.
}
else
{
alias Clong_t clock_t;

version (Windows)
{   const clock_t CLOCKS_PER_SEC = 1000;
    const clock_t CLK_TCK        = 1000;
}
else version (linux)
{   const clock_t CLOCKS_PER_SEC = 1000000;
    extern (C) int sysconf(int);
    extern clock_t CLK_TCK;
    /*static this()
    {
	CLK_TCK = cast(clock_t) sysconf(2);
    }*/
}
else version (OSX)
{
    const clock_t CLOCKS_PER_SEC = 100;
    const clock_t CLK_TCK        = 100;
}
else
{
    static assert(0);
}

const uint TIMEOFFSET     = 315558000;

alias Clong_t time_t;

extern int daylight;
extern int timezone;
extern int altzone;
extern char *tzname[2];

struct tm
{      int     tm_sec,
               tm_min,
               tm_hour,
               tm_mday,
               tm_mon,
               tm_year,
               tm_wday,
               tm_yday,
               tm_isdst;
}
}

clock_t clock();
time_t time(time_t *);
time_t mktime(tm *);
char *asctime(in tm *);
char *ctime(in time_t *);
tm *localtime(in time_t *);
tm *gmtime(in time_t *);
size_t strftime(char *, size_t, in char *, in tm *);
char *_strdate(char *dstring);
char *_strtime(char *timestr);
double difftime(time_t t1, time_t t2);
void _tzset();
void tzset();

void sleep(time_t);
void usleep(uint);
void msleep(uint);

wchar_t *_wasctime(in tm *);
wchar_t *_wctime(in time_t *);
size_t wcsftime(wchar_t *, size_t, in wchar_t *, in tm *);
wchar_t *_wstrdate(wchar_t *);
wchar_t *_wstrtime(wchar_t *);
