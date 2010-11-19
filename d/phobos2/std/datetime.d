/*******************************************************************************
 * Platform-independent high precision StopWatch.
 * 
 * This module provide:
 * $(UL
 *     $(LI StopWatch)
 *     $(LI Benchmarks)
 *     $(LI Some helper functions)
 * )
 * 
 * 
 * License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Kato Shoichi
 */
module std.datetime;

@safe:

import std.traits, std.exception, std.functional;

version (Windows)
{
    import core.sys.windows.windows;
    import std.windows.syserror;
}
else version (Posix)
{
    import core.sys.posix.time;
    import core.sys.posix.sys.time;
}

//##############################################################################
//##############################################################################
//###
//###   StopWatch
//###
//##############################################################################
//##############################################################################

/*******************************************************************************
 * System clock time.
 *
 * This type maintains the most high precision ticks of system clock in each
 * environment.
 * (For StopWatch)
 */
struct Ticks
{
@safe:// @@@BUG@@@ workaround for bug 4211


    /***************************************************************************
     * Ticks that is counted per 1[s].
     *
     * Confirm that it is not 0, to examine whether you can use Ticks.
     */
    static immutable long ticksPerSec;


    /***************************************************************************
     * Ticks when application begins.
     */
    static immutable Ticks appOrigin;


    @trusted
    shared static this()
    {
        version (Windows)
        {
            if (QueryPerformanceFrequency(cast(long*)&ticksPerSec) == 0)
            {
                ticksPerSec = 0;
            }
        }
        else version (Posix)
        {
            static if (is(typeof({ auto fp = &clock_gettime; })))
            {
                timespec ts;
                if ( clock_getres(CLOCK_REALTIME, &ts) != 0)
                {
                    ticksPerSec = 0;
                }
                else
                {
                    ticksPerSec = 1000_000_000 / ts.tv_nsec;
                }
            }
            else
            {
                ticksPerSec = 1_000_000;
            }
        }
        if (ticksPerSec != 0)
        {
            appOrigin = systime();
        }
    }


    unittest
    {
        assert(ticksPerSec);
    }


    /***************************************************************************
     * Unknown value for Ticks
     *
     * You can convert this value into number of seconds by dividing it
     * by ticksPerSec.
     */
    long value;


    /***************************************************************************
     * [s] as integer or real number
     *
     * Attention: This method truncate the number of digits after decimal point.
     */
    const
    T toSeconds(T)() if (isIntegral!T && T.sizeof >= 4)
    {
        return cast(T)(value/ticksPerSec);
    }


    /// ditto
    const
    T toSeconds(T)() if (isFloatingPoint!T)
    {
        //@@@BUG@@@ workaround for bug 4689
        long t = ticksPerSec;
        return value/cast(T)t;
    }


    /***************************************************************************
     * [s] as real number
     */
    @property alias toSeconds!real seconds;


    /***************************************************************************
     * [s] as integer
     */
    @property alias toSeconds!long sec;



    unittest
    {
        auto t = Ticks(ticksPerSec);
        assert(t.sec == 1);
        t = Ticks(ticksPerSec-1);
        assert(t.sec == 0);
        t = Ticks(ticksPerSec*2);
        assert(t.sec == 2);
        t = Ticks(ticksPerSec*2-1);
        assert(t.sec == 1);
        t = Ticks(-1);
        assert(t.sec == 0);
        t = Ticks(-ticksPerSec-1);
        assert(t.sec == -1);
        t = Ticks(-ticksPerSec);
        assert(t.sec == -1);
    }


    /***************************************************************************
     * Create Ticks from [s] as integer
     */
    static Ticks fromSeconds(T)(T sec) if (isNumeric!T)
    {
        return Ticks(cast(long)(sec * ticksPerSec));
    }


    unittest
    {
        auto t = Ticks.fromSeconds(1000000);
        assert(t.sec == 1000000);
        t = Ticks.fromSeconds(2000000);
        assert(t.sec == 2000000);
        t.value -= 1;
        assert(t.sec == 1999999);
    }


    /***************************************************************************
     * [ms] as integer or real number
     */
    const
    T toMilliseconds(T)() if (isIntegral!T && T.sizeof >= 4)
    {
        return value/(ticksPerSec/1000);
    }


    /// ditto
    const
    T toMilliseconds(T)() if (isFloatingPoint!T)
    {
        return toSeconds!T * 1000;
    }

    /***************************************************************************
     * [ms] as real number
     */
    @property alias toMilliseconds!real milliseconds;


    /***************************************************************************
     * [ms] as integer
     */
    @property alias toMilliseconds!long msec;


    /***************************************************************************
     * Create Ticks from [ms] as integer
     */
    static Ticks fromMilliseconds(long msec)
    {
        return Ticks(msec*(ticksPerSec/1000));
    }


    unittest
    {
        auto t = Ticks.fromMilliseconds(1000000);
        assert(t.msec == 1000000);
        t = Ticks.fromMilliseconds(2000000);
        assert(t.msec == 2000000);
        t.value -= 1;
        assert(t.msec == 1999999);
    }


    /***************************************************************************
     * [us] as integer or real number
     */
    const
    T toMicroseconds(T)() if (isIntegral!T && T.sizeof >= 4)
    {
        return value/(ticksPerSec/1000/1000);
    }


    /// ditto
    const
    T toMicroseconds(T)() if (isFloatingPoint!T)
    {
        return toMilliseconds!T * 1000;
    }


    /***************************************************************************
     * [us] as real number
     */
    @property alias toMicroseconds!real microseconds;


    /***************************************************************************
     * [us] as integer
     */
    alias toMicroseconds!long usec;


    /***************************************************************************
     * Create Ticks from [us] as integer
     */
    static Ticks fromMicroseconds(long usec)
    {
        return Ticks(usec*(ticksPerSec/1000/1000));
    }


    unittest
    {
        auto t = Ticks.fromMicroseconds(1000000);
        assert(t.usec == 1000000);
        t = Ticks.fromMicroseconds(2000000);
        assert(t.usec == 2000000);
        t.value -= 1;
        assert(t.usec == 1999999);
    }


    /***************************************************************************
     * operator overroading "-=, +="
     *
     * BUG: This should be return "ref Ticks", but bug2460 prevents that.
     */
    void opOpAssign(string op)(in Ticks t) if (op == "+" || op == "-")
    {
        mixin("value "~op~"= t.value;");
        //return this;
    }


    unittest
    {
        Ticks a = systime(), b = systime();
        a += systime();
        assert(a.seconds >= 0);
        b -= systime();
        assert(b.seconds <= 0);
    }


    /***************************************************************************
     * operator overroading "-, +"
     */
    const
    Ticks opBinary(string op)(in Ticks t) if (op == "-" || op == "+")
    {
        Ticks lhs = this;
        lhs.opOpAssign!op(t);
        return lhs;
    }


    unittest
    {
        auto a = systime();
        auto b = systime();
        assert((a + b).seconds > 0);
        assert((a - b).seconds <= 0);
    }


    /***************************************************************************
     * operator overroading "=="
     */
    const
    equals_t opEquals(ref const Ticks t)
    {
        return value == t.value;
    }


    unittest
    {
        auto t1 = systime();
        assert(t1 == t1);
    }


    /***************************************************************************
     * operator overroading "<, >, <=, >="
     */
    const
    int opCmp(ref const Ticks t)
    {
        return value < t.value? -1: value == t.value ? 0 : 1;
    }


    unittest
    {
        auto t1 = systime();
        auto t2 = systime();
        assert(t1 <= t2);
        assert(t2 >= t1);
    }


    /***************************************************************************
     * operator overroading "*=, /="
     */
    void opOpAssign(string op, T)(T x)
        if ((op == "*" || op == "/") && isNumeric!(T))
    {
        mixin("value "~op~"= x;");
    }


    unittest
    {
        immutable t = systime();
        // *
        {
            Ticks t1 = t, t2 = t;
            t1 *= 2;
            assert(t < t1);
            t2 *= 2.1L;
            assert(t2 > t1);
        }
        // /
        {
            Ticks t1 = t, t2 = t;
            t1 /= 2;
            assert(t1 < t);
            t2 /= 2.1L;
            assert(t2 < t1);
        }
    }


    /***************************************************************************
     * operator overroading "*", "/"
     */
    Ticks opBinary(string op, T)(T x)
        if ((op == "*" || op == "/") && isNumeric!(T))
    {
        auto lhs = this;
        lhs.opOpAssign!op(x);
        return lhs;
    }


    unittest
    {
        auto t = systime();
        auto t2 = t*2;
        assert(t < t2);
        assert(t*3.5 > t2);
    }


    /***************************************************************************
     * operator overroading "/"
     */
    const
    real opBinary(string op)(Ticks x) if (op == "/")
    {
        return value / cast(real)x.value;
    }


    unittest
    {
        auto t = systime();
        assert(t/systime() <= 1);
    }
}

/***************************************************************************
 * Special type for constructor
 */
enum AutoStart
{
    ///
    no,
    ///
    yes
}



/*******************************************************************************
 * StopWatch's AutoStart flag
 */
enum autoStart = AutoStart.yes;


/*******************************************************************************
 * StopWatch measures time highly precise as possible.
 *
 * This class uses performance counter.
 * On Windows, This uses QueryPerformanceCounter.
 * For Posix, This uses clock_gettime if available, gettimeofday otherwise.
 *
 * But this has dispersion in accuracy by environment.
 * It is impossible to remove this dispersion. This depends on multi task
 * system for example overhead from change of the context switch of the thread.
 *
 * Usage is here:
 * Example:
 *------------------------------------------------------------------------------
 *void foo() {
 *    StopWatch sw;
 *    static immutable N = 100;
 *    Ticks[N] times;
 *    Ticks last = Ticks.fromSeconds(0);
 *    foreach (i; 0..N) {
 *        sw.start(); // start/resume mesuring.
 *        foreach (Unused; 0..1000000) bar();
 *        sw.stop();  // stop/pause mesuring.
 *        // Return value of peek() after having stopped are the always same.
 *        writeln((i+1)*1000000, " times done, lap time: ",
 *                sw.peek().msec, "[ms]");
 *        times[i] = sw.peek() - last;
 *        last = sw.peek();
 *    }
 *    real sum = 0;
 *    // When you want to know the number of seconds of the fact,
 *    // you can use properties of Ticks.
 *    // (seconds, mseconds, useconds, interval)
 *    foreach (e; times) sum += e.interval;
 *    writeln("Average time: ", sum/N, "[s]");
 *}
 *------------------------------------------------------------------------------
 */
struct StopWatch
{
@safe:// @@@BUG@@@ workaround for bug 4211
private:


    // true if observing.
    bool m_FlagStarted = false;


    // Ticks at the time of StopWatch starting mesurement.
    Ticks m_TimeStart;


    // Ticks as total time of measurement.
    Ticks m_TimeMeasured;


public:


    /***************************************************************************
     * auto start with constructor
     */
    this(AutoStart autostart)
    {
        if (autostart)
        {
            start();
        }
    }


    unittest
    {
        auto sw = StopWatch(autoStart);
        sw.stop();
    }


    /***************************************************************************
     * Reset the time measurement.
     */
    @safe
    void reset()
    {
        if (m_FlagStarted)
        {
            // Set current systime if StopWatch is measuring.
            m_TimeStart = systime();
        }
        else
        {
            // Set zero if StopWatch is not measuring.
            m_TimeStart.value = 0;
        }
        m_TimeMeasured.value = 0;
    }


    unittest
    {
        StopWatch sw;
        sw.start();
        sw.stop();
        sw.reset();
        assert(sw.peek().seconds == 0);
    }


    /***************************************************************************
     * Start the time measurement.
     */
    @safe
    void start()
    {
        assert(!m_FlagStarted);
        StopWatch sw;
        m_FlagStarted = true;
        m_TimeStart = systime();
    }


    unittest
    {
        StopWatch sw;
        sw.start();
        auto t1 = sw.peek();
        bool doublestart = true;
        try sw.start();
        catch (Error e) doublestart = false;
        assert(!doublestart);
        sw.stop();
        assert((t1 - sw.peek()).seconds <= 0);
    }


    /***************************************************************************
     * Stop the time measurement.
     */
    @safe
    void stop()
    {
        assert(m_FlagStarted);
        m_FlagStarted = false;
        m_TimeMeasured += systime() - m_TimeStart;
    }


    unittest
    {
        StopWatch sw;
        sw.start();
        sw.stop();
        auto t1 = sw.peek();
        bool doublestop = true;
        try sw.stop();
        catch (Error e) doublestop = false;
        assert(!doublestop);
        assert((t1 - sw.peek()).seconds == 0);
    }


    /***************************************************************************
     * Peek Ticks of measured time.
     */
    @safe const
    Ticks peek()
    {
        if(m_FlagStarted)
        {
            return systime() - m_TimeStart + m_TimeMeasured;
        }
        return m_TimeMeasured;
    }


    unittest
    {
        StopWatch sw;
        sw.start();
        auto t1 = sw.peek();
        sw.stop();
        auto t2 = sw.peek();
        auto t3 = sw.peek();
        assert(t1 <= t2);
        assert(t2 == t3);
    }
}


/*******************************************************************************
 * Ticks of system time.
 */
@trusted
Ticks systime()
{
    version (Windows)
    {
        ulong ticks;
        if (QueryPerformanceCounter(cast(long*)&ticks) == 0)
        {
            throw new Exception(sysErrorString(GetLastError()));
        }
        return Ticks(ticks);
    }
    else version (Posix)
    {
        static if (is(typeof({auto f = &clock_gettime;})))
        {
            timespec ts;
            errnoEnforce(clock_gettime(CLOCK_REALTIME, &ts) == 0,
                "Failed in gettimeofday");
            return Ticks(ts.tv_sec * Ticks.ticksPerSec +
                ts.tv_nsec * Ticks.ticksPerSec / 1000 / 1000 / 1000);
        }
        else
        {
            timeval tv;
            errnoEnforce(gettimeofday(&tv, null) == 0,
                "Failed in gettimeofday");
            return Ticks(tv.tv_sec * Ticks.ticksPerSec +
                tv.tv_usec * Ticks.ticksPerSec / 1000 / 1000);
        }
    }
}


unittest
{
    auto t = systime();
    assert(t.value);
}


/*******************************************************************************
 * Ticks when application begin running.
 */
@safe
Ticks apptime()
{
    return systime() - Ticks.appOrigin;
}


unittest
{
    auto a = systime();
    auto b = apptime();
    assert(a.value);
    assert(a != b);
}


//##############################################################################
//##############################################################################
//###
//###   Benchmarks
//###
//##############################################################################
//##############################################################################
// workaround for bug4886
@safe pure nothrow
size_t lengthof(aliases...)()
{
    return aliases.length;
}


/*******************************************************************************
 * Benchmarks code for speed assessment and comparison.
 * 
 * Params:
 * 
 * fun = aliases of callable objects (e.g. function names). Each should
 * take no arguments.
 * 
 * times = The number of times each function is to be executed.
 * 
 * Returns:
 * 
 * An array of $(D n) $(D uint)s. Element at slot $(D i) contains the
 * number of milliseconds spent in calling the $(D i)th function $(D
 * times) times.
 * 
 * Examples:
 *------------------------------------------------------------------------------
 *int a;
 *void f0() { }
 *void f1() { auto b = a; }
 *void f2() { auto b = to!(string)(a); }
 *auto r = benchmark!(f0, f1, f2)(10_000_000);
 *------------------------------------------------------------------------------
 */
@safe
Ticks[lengthof!(fun)()] benchmark(fun...)(uint times)
    if(areAllSafe!fun)
{
    Ticks[lengthof!(fun)()] result;
    StopWatch sw;
    sw.start();
    foreach (i, Unused; fun)
    {
        sw.reset();
        foreach (j; 0 .. times)
        {
            fun[i]();
        }
        result[i] = sw.peek();
    }
    return result;
}


@system
Ticks[lengthof!(fun)()] benchmark(fun...)(uint times)
    if(!areAllSafe!fun)
{
    Ticks[lengthof!(fun)()] result;
    StopWatch sw;
    sw.start();
    foreach (i, Unused; fun)
    {
        sw.reset();
        foreach (j; 0 .. times)
        {
            fun[i]();
        }
        result[i] = sw.peek();
    }
    return result;
}


unittest
{
    int a;
    void f0() { }
    //void f1() { auto b = to!(string)(a); }
    void f2() { auto b = (a); }
    auto r = benchmark!(f0, f2)(100);
}


/*******************************************************************************
 * Return value of benchmark with two functions comparing.
 */
immutable struct ComparingBenchmarkResult
{
@safe:
    private Ticks m_tmBase;
    private Ticks m_tmTarget;


    /***************************************************************************
     * Evaluation value
     *
     * This return the evaluation value of performance as the ratio that is
     * compared between BaseFunc's time and TargetFunc's time.
     * If performance is high, this returns a high value.
     */
    @property immutable
    real point()
    {
        // @@@BUG@@@ workaround for bug 4689
        long t = m_tmTarget.value;
        return m_tmBase.value / cast(real)t;
    }


    /***************************************************************************
     * The time required of the target function
     */
    @property immutable
    public Ticks targetTime()
    {
        return m_tmTarget;
    }


    /***************************************************************************
     * The time required of the base function
     */
    @property immutable
    public Ticks baseTime()
    {
        return m_tmBase;
    }
}


/*******************************************************************************
 * Benchmark with two functions comparing.
 * 
 * Params:
 * baseFunc   = The function to become the base of the speed.
 * targetFunc = The function that wants to measure speed.
 * times      = The number of times each function is to be executed.
 * Examples:
 *------------------------------------------------------------------------------
 *void f1() {
 *    // ...
 *}
 *void f2() {
 *    // ...
 *}
 *
 *void main() {
 *    auto b = comparingBenchmark!(f1, f2, 0x80);
 *    writeln(b.point);
 *}
 *------------------------------------------------------------------------------
 */
@safe
ComparingBenchmarkResult comparingBenchmark(
    alias baseFunc, alias targetFunc, int times = 0xfff)()
    if (isSafe!baseFunc && isSafe!targetFunc)
{
    auto t = benchmark!(baseFunc, targetFunc)(times);
    return ComparingBenchmarkResult(t[0], t[1]);
}


/// ditto
@system
ComparingBenchmarkResult comparingBenchmark(
    alias baseFunc, alias targetFunc, int times = 0xfff)()
    if (!(isSafe!baseFunc && isSafe!targetFunc))
{
    auto t = benchmark!(baseFunc, targetFunc)(times);
    return ComparingBenchmarkResult(t[0], t[1]);
}


@safe
unittest
{
    @system void f1x() { }
    @system void f2x() { }
    @safe void f1o() { }
    @safe void f2o() { }
    auto b1 = comparingBenchmark!(f1o, f2o, 1); // OK
    //static auto b2 = comparingBenchmark!(f1x, f2x, 1); // NG
}


@system
unittest
{
    @system void f1x() { }
    @system void f2x() { }
    @safe void f1o() { }
    @safe void f2o() { }
    auto b1 = comparingBenchmark!(f1o, f2o, 1); // OK
    auto b2 = comparingBenchmark!(f1x, f2x, 1); // OK
}

//##############################################################################
//##############################################################################
//###
//###   Helper functions
//###
//##############################################################################
//##############################################################################


version (D_Ddoc)
{
    /***************************************************************************
     * Scope base measuring time.
     *
     * When a value that is returned by this function is destroyed,
     * func will run.
     * func is unaly function that requires Ticks.
     *
     * Examples:
     *--------------------------------------------------------------------------
     *writeln("benchmark start!");
     *{
     *    auto mt = measureTime!((a){assert(a.seconds);});
     *    doSomething();
     *}
     *writeln("benchmark end!");
     *--------------------------------------------------------------------------
     */
    TemporaryValue measureTime(alias func)();
}
else
{
    @safe
    {
        auto measureTime(alias func)()
            if (isSafe!func)
        {
            struct TMP
            {
                private StopWatch sw = void;
                this(StopWatch.AutoStart as)
                {
                    sw = StopWatch(as);
                }
                ~this()
                {
                    unaryFun!(func)(sw.peek());
                }
            }
            return TMP(autoStart);
        }
    }
    
    @system
    {
        auto measureTime(alias func)()
            if (!isSafe!func)
        {
            struct TMP
            {
                private StopWatch sw = void;
                this(AutoStart as)
                {
                    sw = StopWatch(as);
                }
                ~this()
                {
                    unaryFun!(func)(sw.peek());
                }
            }
            return TMP(autoStart);
        }
    }
}

@system
unittest
{
    {
        auto mt = measureTime!((a){assert(a.seconds <>= 0);});
    }

    /+
    with (measureTime!((a){assert(a.seconds);}))
    {
        // doSomething();
        // @@@BUG@@@ doesn't work yet.
    }
    +/
}
