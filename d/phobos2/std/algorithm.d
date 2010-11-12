// Written in the D programming language.

/**
Implements algorithms oriented mainly towards processing of
sequences. Some functions are semantic equivalents or supersets of
those found in the $(D $(LESS)_algorithm$(GREATER)) header in $(WEB
sgi.com/tech/stl/, Alexander Stepanov's Standard Template Library) for
C++.

Note:

Many functions in this module are parameterized with a function or a
$(GLOSSARY predicate). The predicate may be passed either as a
function name, a delegate name, a $(GLOSSARY functor) name, or a
compile-time string. The string may consist of $(B any) legal D
expression that uses the symbol $(D a) (for unary functions) or the
symbols $(D a) and $(D b) (for binary functions). These names will NOT
interfere with other homonym symbols in user code because they are
evaluated in a different context. The default for all binary
comparison predicates is $(D "a == b") for unordered operations and
$(D "a < b") for ordered operations.

Example:

----
int[] a = ...;
static bool greater(int a, int b)
{
    return a > b;
}
sort!(greater)(a);  // predicate as alias
sort!("a > b")(a);  // predicate as string
                    // (no ambiguity with array name)
sort(a);            // no predicate, "a < b" is implicit
----

Macros:
WIKI = Phobos/StdAlgorithm

Copyright: Andrei Alexandrescu 2008-.

License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors:   $(WEB erdani.com, Andrei Alexandrescu)
 */
module std.algorithm;

import std.c.string;
import std.array, std.container, std.conv, std.date, std.exception,
    std.functional, std.math, std.metastrings, std.range, std.string,
    std.traits, std.typecons, std.typetuple, std.stdio;

version(unittest)
{
    import std.random, std.stdio, std.string;
    mixin(dummyRanges);
}

/**
Implements the homonym function (also known as $(D transform)) present
in many languages of functional flavor. The call $(D map!(fun)(range))
returns a range of which elements are obtained by applying $(D fun(x))
left to right for all $(D x) in $(D range). The original ranges are
not changed. Evaluation is done lazily. The range returned by $(D map)
caches the last value such that evaluating $(D front) multiple times
does not result in multiple calls to $(D fun).

Example:
----
int[] arr1 = [ 1, 2, 3, 4 ];
int[] arr2 = [ 5, 6 ];
auto squares = map!("a * a")(chain(arr1, arr2));
assert(equal(squares, [ 1, 4, 9, 16, 25, 36 ]));
----

Multiple functions can be passed to $(D map). In that case, the
element type of $(D map) is a tuple containing one element for each
function.

Example:

----
auto arr1 = [ 1, 2, 3, 4 ];
foreach (e; map!("a + a", "a * a")(arr1))
{
    writeln(e.field[0], " ", e.field[1]);
}
----

You may alias $(D map) with some function(s) to a symbol and use it
separately:

----
alias map!(to!string) stringize;
assert(equal(stringize([ 1, 2, 3, 4 ]), [ "1", "2", "3", "4" ]));
----
 */
template map(fun...)
{
    auto map(Range)(Range r)
    {
        static if (fun.length > 1)
        {
            return Map!(adjoin!(staticMap!(unaryFun, fun)), Range)(r);
        }
        else
        {
            return Map!(unaryFun!fun, Range)(r);
        }
    }
}

struct Map(alias fun, Range) if (isInputRange!(Range))
{
    alias fun _fun;
    alias typeof({ return _fun(.ElementType!(Range).init); }()) ElementType;
    Range _input;
    ElementType _cache;

    static if (isBidirectionalRange!(Range))
    {
    // Using a second cache would lead to at least 1 extra function evaluation
    // and wasted space when 99% of the time this range will only be iterated
    // over in the forward direction.  Use a bool to determine whether cache
    // is front or back instead.
        bool cacheIsBack_;

        private void fillCacheBack()
        {
            if (!_input.empty) _cache = _fun(_input.back);
            cacheIsBack_ = true;
        }

        @property ElementType back()
        {
            if (!cacheIsBack_)
            {
                fillCacheBack();
            }
            return _cache;
        }

        void popBack()
        {
            _input.popBack;
            fillCacheBack();
        }
    }

    private void fillCache()
    {
        if (!_input.empty) _cache = _fun(_input.front);

        static if(isBidirectionalRange!(Range))
        {
            cacheIsBack_ = false;
        }
    }

    this(Range input)
    {
        _input = input;
        fillCache;
    }

	static if (isInfinite!Range)
    {
		// Propagate infinite-ness.
		enum bool empty = false;
	}
    else
    {
		@property bool empty()
        {
			return _input.empty;
		}
	}

    void popFront()
    {
        _input.popFront;
        fillCache();
    }

    @property ElementType front()
    {
        static if (isBidirectionalRange!(Range))
        {
            if (cacheIsBack_)
            {
                fillCache();
            }
        }
        return _cache;
    }

    static if (isRandomAccessRange!Range)
    {
        ElementType opIndex(size_t index)
        {
            return _fun(_input[index]);
        }
    }

    // hasLength is busted, Bug 2873
    static if (is(typeof(_input.length) : size_t)
        || is(typeof(_input.length()) : size_t))
    {
        @property size_t length()
        {
            return _input.length;
        }
    }

    static if (hasSlicing!(Range))
    {
        typeof(this) opSlice(size_t lowerBound, size_t upperBound)
        {
            return typeof(this)(_input[lowerBound..upperBound]);
        }
    }

	static if (isForwardRange!Range)
        @property Map save()
        {
            auto result = this;
            result._input = result._input.save;
            return result;
        }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    alias map!(to!string) stringize;
    assert(equal(stringize([ 1, 2, 3, 4 ]), [ "1", "2", "3", "4" ]));
    uint counter;
    alias map!((a) { return counter++; }) count;
    assert(equal(count([ 10, 2, 30, 4 ]), [ 0, 1, 2, 3 ]));
    counter = 0;
    adjoin!((a) { return counter++; }, (a) { return counter++; })(1);
    alias map!((a) { return counter++; }, (a) { return counter++; }) countAndSquare;
    //assert(equal(countAndSquare([ 10, 2 ]), [ tuple(0u, 100), tuple(1u, 4) ]));
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] arr1 = [ 1, 2, 3, 4 ];
    int[] arr2 = [ 5, 6 ];
    auto squares = map!("a * a")(arr1);
    assert(equal(squares, [ 1, 4, 9, 16 ][]));
    assert(equal(map!("a * a")(chain(arr1, arr2)), [ 1, 4, 9, 16, 25, 36 ][]));

    // Test the caching stuff.
    assert(squares.back == 16);
    auto squares2 = squares.save;
    assert(squares2.back == 16);

    assert(squares2.front == 1);
    squares2.popFront;
    assert(squares2.front == 4);
    squares2.popBack;
    assert(squares2.front == 4);
    assert(squares2.back == 9);

    assert(equal(map!("a * a")(chain(arr1, arr2)), [ 1, 4, 9, 16, 25, 36 ][]));

    uint i;
    foreach (e; map!("a", "a * a")(arr1))
    {
        assert(e.field[0] == ++i);
        assert(e.field[1] == i * i);
    }

    // Test length.
    assert(squares.length == 4);
    assert(map!"a * a"(chain(arr1, arr2)).length == 6);

    // Test indexing.
    assert(squares[0] == 1);
    assert(squares[1] == 4);
    assert(squares[2] == 9);
    assert(squares[3] == 16);

    // Test slicing.
    auto squareSlice = squares[1..squares.length - 1];
    assert(equal(squareSlice, [4, 9][]));
    assert(squareSlice.back == 9);
    assert(squareSlice[1] == 9);

    // Test on a forward range to make sure it compiles when all the fancy
    // stuff is disabled.
    auto fibsSquares = map!"a * a"(recurrence!("a[n-1] + a[n-2]")(1, 1));
    assert(fibsSquares.front == 1);
    fibsSquares.popFront;
    fibsSquares.popFront;
    assert(fibsSquares.front == 4);
    fibsSquares.popFront;
    assert(fibsSquares.front == 9);

	auto repeatMap = map!"a"(repeat(1));
	static assert(isInfinite!(typeof(repeatMap)));

	auto intRange = map!"a"([1,2,3]);
	static assert(isRandomAccessRange!(typeof(intRange)));

    foreach(DummyType; AllDummyRanges) {
	    DummyType d;
	    auto m = map!"a * a"(d);

	    static assert(propagatesRangeType!(typeof(m), DummyType));
	    assert(equal(m, [1,4,9,16,25,36,49,64,81,100]));
	}
}

// reduce
/**
Implements the homonym function (also known as $(D accumulate), $(D
compress), $(D inject), or $(D foldl)) present in various programming
languages of functional flavor. The call $(D reduce!(fun)(seed,
range)) first assigns $(D seed) to an internal variable $(D result),
also called the accumulator. Then, for each element $(D x) in $(D
range), $(D result = fun(result, x)) gets evaluated. Finally, $(D
result) is returned. The one-argument version $(D reduce!(fun)(range))
works similarly, but it uses the first element of the range as the
seed (the range must be non-empty).

Many aggregate range operations turn out to be solved with $(D reduce)
quickly and easily. The example below illustrates $(D reduce)'s
remarkable power and flexibility.

Example:
----
int[] arr = [ 1, 2, 3, 4, 5 ];
// Sum all elements
auto sum = reduce!("a + b")(0, arr);
assert(sum == 15);

// Compute the maximum of all elements
auto largest = reduce!(max)(arr);
assert(largest == 5);

// Compute the number of odd elements
auto odds = reduce!("a + (b & 1)")(0, arr);
assert(odds == 3);

// Compute the sum of squares
auto ssquares = reduce!("a + b * b")(0, arr);
assert(ssquares == 55);

// Chain multiple ranges into seed
int[] a = [ 3, 4 ];
int[] b = [ 100 ];
auto r = reduce!("a + b")(chain(a, b));
assert(r == 107);

// Mixing convertible types is fair game, too
double[] c = [ 2.5, 3.0 ];
auto r1 = reduce!("a + b")(chain(a, b, c));
assert(r1 == 112.5);
----

$(DDOC_SECTION_H Multiple functions:) Sometimes it is very useful to
compute multiple aggregates in one pass. One advantage is that the
computation is faster because the looping overhead is shared. That's
why $(D reduce) accepts multiple functions. If two or more functions
are passed, $(D reduce) returns a $(XREF typecons, Tuple) object with
one member per passed-in function. The number of seeds must be
correspondingly increased.

Example:
----
double[] a = [ 3.0, 4, 7, 11, 3, 2, 5 ];
// Compute minimum and maximum in one pass
auto r = reduce!(min, max)(a);
// The type of r is Tuple!(double, double)
assert(r.field[0] == 2);  // minimum
assert(r.field[1] == 11); // maximum

// Compute sum and sum of squares in one pass
r = reduce!("a + b", "a + b * b")(tuple(0.0, 0.0), a);
assert(r.field[0] == 35);  // sum
assert(r.field[1] == 233); // sum of squares
// Compute average and standard deviation from the above
auto avg = r.field[0] / a.length;
auto stdev = sqrt(r.field[1] / a.length - avg * avg);
----
 */

template reduce(fun...)
{
    auto reduce(Args...)(Args args)
    if (Args.length > 0 && Args.length <= 2 && isInputRange!(Args[$ - 1]))
    {
        static if (Args.length == 2)
        {
            alias args[0] seed;
            alias args[1] r;
            Unqual!(Args[0]) result = seed;
            for (; !r.empty; r.popFront)
            {
                static if (fun.length == 1)
                {
                    result = binaryFun!(fun[0])(result, r.front);
                }
                else
                {
                    foreach (i, Unused; Args[0].Types)
                    {
                        result.field[i] = binaryFun!(fun[i])(result.field[i],
                                r.front);
                    }
                }
            }
            return result;
        }
        else
        {
            alias args[0] r;
            static if (fun.length == 1)
            {
                return reduce(r.front, (r.popFront(), r));
            }
            else
            {
                static assert(fun.length > 1);
                typeof(adjoin!(staticMap!(binaryFun, fun))(r.front, r.front))
                    result = void;
                foreach (i, T; result.Types)
                {
                    auto p = (cast(void*) &result.field[i])
                        [0 .. result.field[i].sizeof];
                    emplace!T(p, r.front);
                }
                r.popFront();
                return reduce(result, r);
            }
        }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    double[] a = [ 3, 4 ];
    auto r = reduce!("a + b")(0.0, a);
    assert(r == 7);
    r = reduce!("a + b")(a);
    assert(r == 7);
    r = reduce!(min)(a);
    assert(r == 3);
    double[] b = [ 100 ];
    auto r1 = reduce!("a + b")(chain(a, b));
    assert(r1 == 107);

    // two funs
    auto r2 = reduce!("a + b", "a - b")(tuple(0., 0.), a);
    assert(r2.field[0] == 7 && r2.field[1] == -7);
    auto r3 = reduce!("a + b", "a - b")(a);
    assert(r3.field[0] == 7 && r3.field[1] == -1);

    a = [ 1, 2, 3, 4, 5 ];
    // Stringize with commas
    string rep = reduce!("a ~ `, ` ~ to!(string)(b)")("", a);
    assert(rep[2 .. $] == "1, 2, 3, 4, 5", "["~rep[2 .. $]~"]");
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    const float a = 0.0;
    const float[] b = [ 1.2, 3, 3.3 ];
    float[] c = [ 1.2, 3, 3.3 ];
    auto r = reduce!"a + b"(a, b);
    r = reduce!"a + b"(a, c);
}

/**
Fills a range with a value.

Example:
----
int[] a = [ 1, 2, 3, 4 ];
fill(a, 5);
assert(a == [ 5, 5, 5, 5 ]);
----
 */
void fill(Range, Value)(Range range, Value filler)
if (isForwardRange!Range && is(typeof(range.front = filler)))
{
    alias ElementType!Range T;
    static if (hasElaborateCopyConstructor!T || !isDynamicArray!Range)
    {
        for (; !range.empty; range.popFront)
        {
            range.front = filler;
        }
    }
    else
    {
        if (range.empty) return;
        // Range is a dynamic array of bald values, just fill memory
        // Can't use memcpy or memmove coz ranges overlap
        range.front = filler;
        auto bytesToFill = T.sizeof * (range.length - 1);
        auto bytesFilled = T.sizeof;
        while (bytesToFill)
        {
            auto fillNow = min(bytesToFill, bytesFilled);
            memcpy(cast(void*) range.ptr + bytesFilled,
                    cast(void*) range.ptr,
                  fillNow);
            bytesToFill -= fillNow;
            bytesFilled += fillNow;
        }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    fill(a, 6);
    assert(a == [ 6, 6, 6 ], text(a));
    void fun0()
    {
        foreach (i; 0 .. 1000)
        {
            foreach (ref e; a) e = 6;
        }
    }
    void fun1() { foreach (i; 0 .. 1000) fill(a, 6); }
    //void fun2() { foreach (i; 0 .. 1000) fill2(a, 6); }
    //writeln(benchmark!(fun0, fun1, fun2)(10000));
}

/**
Fills $(D range) with a pattern copied from $(D filler). The length of
$(D range) does not have to be a multiple of the length of $(D
filler). If $(D filler) is empty, an exception is thrown.

Example:
----
int[] a = [ 1, 2, 3, 4, 5 ];
int[] b = [ 8, 9 ];
fill(a, b);
assert(a == [ 8, 9, 8, 9, 8 ]);
----
 */

void fill(Range1, Range2)(Range1 range, Range2 filler)
if (isForwardRange!Range1 && isForwardRange!Range2
        && is(typeof(Range1.init.front = Range2.init.front)))
{
    enforce(!filler.empty);
    auto t = filler.save;
    for (; !range.empty; range.popFront, t.popFront)
    {
        if (t.empty) t = filler;
        range.front = t.front;
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 4, 5 ];
    int[] b = [1, 2];
    fill(a, b);
    assert(a == [ 1, 2, 1, 2, 1 ]);
}

/**
Fills a range with a value. Assumes that the range does not currently
contain meaningful content. This is of interest for structs that
define copy constructors (for all other types, fill and
uninitializedFill are equivalent).

Example:
----
struct S { ... }
S[] s = (cast(S*) malloc(5 * S.sizeof))[0 .. 5];
uninitializedFill(s, 42);
assert(s == [ 42, 42, 42, 42, 42 ]);
----
 */
void uninitializedFill(Range, Value)(Range range, Value filler)
if (isForwardRange!Range && is(typeof(range.front = filler)))
{
    alias ElementType!Range T;
    static if (hasElaborateCopyConstructor!T)
    {
        // Must construct stuff by the book
        for (; !range.empty; range.popFront)
        {
            emplace!T((cast(void*) &range.front)[0 .. T.sizeof], filler);
        }
    }
    else
    {
        // Doesn't matter whether fill is initialized or not
        return fill(range, filler);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    uninitializedFill(a, 6);
    assert(a == [ 6, 6, 6 ]);
    void fun0()
    {
        foreach (i; 0 .. 1000)
        {
            foreach (ref e; a) e = 6;
        }
    }
    void fun1() { foreach (i; 0 .. 1000) fill(a, 6); }
    //void fun2() { foreach (i; 0 .. 1000) fill2(a, 6); }
    //writeln(benchmark!(fun0, fun1, fun2)(10000));
}

/**
Initializes all elements of a range with their $(D .init)
value. Assumes that the range does not currently contain meaningful
content.

Example:
----
struct S { ... }
S[] s = (cast(S*) malloc(5 * S.sizeof))[0 .. 5];
initialize(s);
assert(s == [ 0, 0, 0, 0, 0 ]);
----
 */
void initializeAll(Range)(Range range)
if (isForwardRange!Range && is(typeof(range.front = range.front)))
{
    alias ElementType!Range T;
    static assert(is(typeof(&(range.front()))) || !hasElaborateAssign!T,
            "Cannot initialize a range that does not expose"
            " references to its elements");
    static if (!isDynamicArray!Range)
    {
        static if (is(typeof(&(range.front()))))
        {
            // Range exposes references
            for (; !range.empty; range.popFront)
            {
                memcpy(&(range.front()), &T.init, T.sizeof);
            }
        }
        else
        {
            // Go the slow route
            for (; !range.empty; range.popFront)
            {
                range.front = filler;
            }
        }
    }
    else
    {
        fill(range, T.init);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    uninitializedFill(a, 6);
    assert(a == [ 6, 6, 6 ]);
    initializeAll(a);
    assert(a == [ 0, 0, 0 ]);
    void fun0()
    {
        foreach (i; 0 .. 1000)
        {
            foreach (ref e; a) e = 6;
        }
    }
    void fun1() { foreach (i; 0 .. 1000) fill(a, 6); }
    //void fun2() { foreach (i; 0 .. 1000) fill2(a, 6); }
    //writeln(benchmark!(fun0, fun1, fun2)(10000));
}

// filter
/**
Implements the homonym function present in various programming
languages of functional flavor. The call $(D filter!(fun)(range))
returns a new range only containing elements $(D x) in $(D r) for
which $(D predicate(x)) is $(D true).

Example:
----
int[] arr = [ 1, 2, 3, 4, 5 ];
// Sum all elements
auto small = filter!("a < 3")(arr);
assert(small == [ 1, 2 ]);
// In combination with chain() to span multiple ranges
int[] a = [ 3, -2, 400 ];
int[] b = [ 100, -101, 102 ];
auto r = filter!("a > 0")(chain(a, b));
assert(equals(r, [ 3, 400, 100, 102 ]));
// Mixing convertible types is fair game, too
double[] c = [ 2.5, 3.0 ];
auto r1 = filter!("cast(int) a != a")(chain(c, a, b));
assert(r1 == [ 2.5 ]);
----
 */

version (all)
{
/* This is the older version. Too many problems with the newer one.
 */
Filter!(unaryFun!(pred), Range)
filter(alias pred, Range)(Range rs)
{
    return typeof(return)(rs);
}

struct Filter(alias pred, Range) if (isInputRange!(Range))
{
    Range _input;

    this(Range r)
    {
        _input = r;
        while (!_input.empty && !pred(_input.front)) _input.popFront;
    }

    ref Filter opSlice()
    {
        return this;
    }

    bool empty() { return _input.empty; }
    void popFront()
    {
        do
        {
            _input.popFront;
        } while (!_input.empty && !pred(_input.front));
    }

    ElementType!(Range) front()
    {
        return _input.front;
    }
}

unittest
{
    int[] a = [ 3, 4 ];
    auto r = filter!("a > 3")(a);
    assert(equal(r, [ 4 ][]));

    a = [ 1, 22, 3, 42, 5 ];
    auto under10 = filter!("a < 10")(a);
    assert(equal(under10, [1, 3, 5][]));

    // With copying of inner struct Filter to Map
    auto arr = [1,2,3,4,5];
    auto m = map!"a + 1"(filter!"a < 4"(arr));
}

}
else
{
template filter(alias predicate)
{
    auto filter(Range)(Range rs) if (isInputRange!(Range))
    {
        alias unaryFun!predicate pred;

        struct Filter
        {
            Range _input;

            this(Range r)
            {
                _input = r;
                while (!_input.empty && !pred(_input.front)) _input.popFront;
                static if (isBidirectionalRange!Range) {
                    while (!_input.empty && !pred(_input.back)) _input.popBack;
                }

            }

            ref Filter opSlice()
            {
                return this;
            }

            static if (isInfinite!Range) {
                enum bool empty = false;  // Propagate infiniteness.
            } else {
                bool empty() { return _input.empty; }
            }

            void popFront()
            {
                do
                {
                    _input.popFront;
                } while (!_input.empty && !pred(_input.front));
            }

            ElementType!(Range) front()
            {
                return _input.front;
            }

            static if (isBidirectionalRange!Range) {
                void popBack()
                {
                    do
                    {
                        _input.popBack;
                    } while (!_input.empty && !pred(_input.back));
                }

                ElementType!(Range) back() { return _input.back;}
            }


            static if (isForwardRange!Range)
            {
                @property typeof(this) save()
                {
                    return typeof(this)(_input.save);
                }
            }
        }

        return Filter(rs);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 3, 4, 2 ];
    auto r = filter!("a > 3")(a);
    static assert(isForwardRange!(typeof(r)));
    assert(equal(r, [ 4 ][]));

    a = [ 1, 22, 3, 42, 5 ];
    auto under10 = filter!("a < 10")(a);
    assert(equal(under10, [1, 3, 5][]));
    static assert(isForwardRange!(typeof(under10)));

	auto infinite = filter!"a > 2"(repeat(3));
	static assert(isInfinite!(typeof(infinite)));
	static assert(isForwardRange!(typeof(infinite)));

    auto nums = [0,1,2,3,4];
    auto forward = filter!"a % 2 == 0"(nums);
    assert(equal(retro(forward), [4,2,0][])); // f is a bidirectional range

	foreach(DummyType; AllDummyRanges) {
	    DummyType d;
	    auto f = filter!"a & 1"(d);
	    assert(equal(f, [1,3,5,7,9]));

	    static if (isForwardRange!DummyType) {
	        static assert(isForwardRange!(typeof(f)));
	    }

	    static if (isBidirectionalRange!DummyType) {
	        static assert(isBidirectionalRange!(typeof(f)));
	        assert(equal(retro(f), [9,7,5,3,1]));
	    }
	}

    // With delegates
    int x = 10;
    int overX(int a) { return a > x; }
    typeof(filter!overX(a)) getFilter()
    {
        return filter!overX(a);
    }
    auto r1 = getFilter();
    assert(equal(r1, [22, 42]));

    // With chain
    assert(equal(filter!overX(chain(a, nums)), [22, 42]));

    // With copying of inner struct Filter to Map
    auto arr = [1,2,3,4,5];
    auto m = map!"a + 1"(filter!"a < 4"(arr));
}
}

// move
/**
Moves $(D source) into $(D target) via a destructive
copy. Specifically: $(UL $(LI If $(D hasAliasing!T) is true (see
$(XREF traits, hasAliasing)), then the representation of $(D source)
is bitwise copied into $(D target) and then $(D source = T.init) is
evaluated.)  $(LI Otherwise, $(D target = source) is evaluated.)) See
also $(XREF contracts, pointsTo).

Preconditions:
$(D &source == &target || !pointsTo(source, source))
*/
void move(T)(ref T source, ref T target)
{
    if (&source == &target) return;
    assert(!pointsTo(source, source));
    static if (is(T == struct))
    {
        // Most complicated case. Destroy whatever target had in it
        // and bitblast source over it
        static if (is(typeof(target.__dtor()))) target.__dtor();
        memcpy(&target, &source, T.sizeof);
        // If the source defines a destructor, we must obliterate the
        // object in order to avoid double freeing
        static if (is(typeof(source.__dtor())))
        {
            static T empty;
            memcpy(&source, &empty, T.sizeof);
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        target = source;
        // static if (is(typeof(source = null)))
        // {
        //     // Nullify the source to help the garbage collector
        //     source = null;
        // }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    Object obj1 = new Object;
    Object obj2 = obj1;
    Object obj3;
    move(obj2, obj3);
    assert(obj3 is obj1);

    struct S1 { int a = 1, b = 2; }
    S1 s11 = { 10, 11 };
    S1 s12;
    move(s11, s12);
    assert(s11.a == 10 && s11.b == 11 && s12.a == 10 && s12.b == 11);

    struct S2 { int a = 1; int * b; }
    S2 s21 = { 10, new int };
    S2 s22;
    move(s21, s22);
    assert(s21 == s22);
}

/// Ditto
T move(T)(ref T src)
{
    T result;
    move(src, result);
    return result;
}

// moveAll
/**
For each element $(D a) in $(D src) and each element $(D b) in $(D
tgt) in lockstep in increasing order, calls $(D move(a, b)). Returns
the leftover portion of $(D tgt). Throws an exeption if there is not
enough room in $(D tgt) to acommodate all of $(D src).

Preconditions:
$(D walkLength(src) >= walkLength(tgt))
 */
Range2 moveAll(Range1, Range2)(Range1 src, Range2 tgt)
{
    for (; !src.empty; src.popFront, tgt.popFront)
    {
        enforce(!tgt.empty);
        move(src.front, tgt.front);
    }
    return tgt;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    int[] b = new int[5];
    assert(moveAll(a, b) is b[3 .. $]);
    assert(a == b[0 .. 3]);
    assert(a == [ 1, 2, 3 ]);
}

// moveSome
/**
For each element $(D a) in $(D src) and each element $(D b) in $(D
tgt) in lockstep in increasing order, calls $(D move(a, b)). Stops
when either $(D src) or $(D tgt) have been exhausted. Returns the
leftover portions of the two ranges.
 */
Tuple!(Range1, Range2) moveSome(Range1, Range2)(Range1 src, Range2 tgt)
{
    for (; !src.empty && !tgt.empty; src.popFront, tgt.popFront)
    {
        enforce(!tgt.empty);
        move(src.front, tgt.front);
    }
    return tuple(src, tgt);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 4, 5 ];
    int[] b = new int[3];
    assert(moveSome(a, b).field[0] is a[3 .. $]);
    assert(a[0 .. 3] == b);
    assert(a == [ 1, 2, 3, 4, 5 ]);
}

// swap
/**
Swaps $(D lhs) and $(D rhs). See also $(XREF exception, pointsTo).

Preconditions:

$(D !pointsTo(lhs, lhs) && !pointsTo(lhs, rhs) && !pointsTo(rhs, lhs)
&& !pointsTo(rhs, rhs))
 */
void swap(T)(ref T a, ref T b) if (!is(typeof(T.init.proxySwap(T.init))))
{
   static if (is(T == struct))
   {
      // For structs, move memory directly
      // First check for undue aliasing
      assert(!pointsTo(a, b) && !pointsTo(b, a)
         && !pointsTo(a, a) && !pointsTo(b, b));
      // Swap bits
      ubyte[T.sizeof] t = void;
      memcpy(&t, &a, T.sizeof);
      memcpy(&a, &b, T.sizeof);
      memcpy(&b, &t, T.sizeof);
   }
   else
   {
      // For non-struct types, suffice to do the classic swap
      auto t = a;
      a = b;
      b = t;
   }
}

// Not yet documented
void swap(T)(T lhs, T rhs) if (is(typeof(T.init.proxySwap(T.init))))
{
    lhs.proxySwap(rhs);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int a = 42, b = 34;
    swap(a, b);
    assert(a == 34 && b == 42);

    struct S { int x; char c; int[] y; }
    S s1 = { 0, 'z', [ 1, 2 ] };
    S s2 = { 42, 'a', [ 4, 6 ] };
    //writeln(s2.tupleof.stringof);
    swap(s1, s2);
    assert(s1.x == 42);
    assert(s1.c == 'a');
    assert(s1.y == [ 4, 6 ]);

    assert(s2.x == 0);
    assert(s2.c == 'z');
    assert(s2.y == [ 1, 2 ]);
}

// splitter
/**
Splits a range using an element as a separator. This can be used with
any range type, but is most popular with string types.

Two adjacent separators are considered to surround an empty element in
the split range.

If the empty range is given, the result is a range with one empty
element. If a range with one separator is given, the result is a range
with two empty elements.

Example:
---
assert(equal(splitter("hello  world", ' ') == [ "hello", "", "world" ]));
int[] a = [ 1, 2, 0, 0, 3, 0, 4, 5, 0 ];
int[][] w = [ [1, 2], [], [3], [4, 5] ];
assert(equal(splitter(a, 0), w));
a = null;
assert(equal(splitter(a, 0), [ (int[]).init ]));
a = [ 0 ];
assert(equal(splitter(a, 0), [ (int[]).init, (int[]).init ]));
a = [ 0, 1 ];
assert(equal(splitter(a, 0), [ [], [1] ]));
----
*/
struct Splitter(Range, Separator)
    if (is(typeof(ElementType!Range.init == Separator.init)) && hasSlicing!Range)
{
private:
    Range _input;
    Separator _separator;
    enum size_t _unComputed = size_t.max - 1, _atEnd = size_t.max;
    size_t _frontLength = _unComputed;

public:
    this(Range input, Separator separator)
    {
        _input = input;
        _separator = separator;
        // computeFront();
        // computeBack();
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;
    }
    else
    {
        @property bool empty()
        {
            return _frontLength == _atEnd;
        }
    }

    @property Range front()
    {
        assert(!empty);
        if (_frontLength == _unComputed)
        {
            _frontLength = _input.indexOf(_separator);
            if (_frontLength == -1) _frontLength = _input.length;
        }
        return _input[0 .. _frontLength];
    }

    void popFront()
    {
        assert(!empty);
        if (_frontLength == _unComputed)
        {
            front;
        }
        assert(_frontLength <= _input.length);
        if (_frontLength == _input.length)
        {
            // no more input and need to fetch => done
            _frontLength = _atEnd;
        }
        else
        {
            _input = _input[_frontLength .. $];
            skipOver(_input, _separator) || assert(false);
            _frontLength = _unComputed;
        }
    }
}

/// Ditto
Splitter!(Range, Separator)
splitter(Range, Separator)(Range r, Separator s)
if (is(typeof(ElementType!(Range).init == ElementType!(Separator).init))
       ||
    is(typeof(ElementType!(Range).init == Separator.init))
    )
{
    return typeof(return)(r, s);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(equal(splitter("hello  world", ' '), [ "hello", "", "world" ]));
    int[] a = [ 1, 2, 0, 0, 3, 0, 4, 5, 0 ];
    int[][] w = [ [1, 2], [], [3], [4, 5], [] ];
    // foreach (x; splitter(a, 0)) {
    //     writeln("[", x, "]");
    // }
    assert(equal(splitter(a, 0), w));
    a = null;
    assert(equal(splitter(a, 0), [ (int[]).init ][]));
    a = [ 0 ];
    assert(equal(splitter(a, 0), [ (int[]).init, (int[]).init ][]));
    a = [ 0, 1 ];
    assert(equal(splitter(a, 0), [ [], [1] ][]));

//    foreach(DummyType; AllDummyRanges) {  // Bug 4408
//        DummyType d;
//        auto s = splitter(d, 5);
//        assert(equal(s, [[1,2,3,4], [6,7,8,9,10]]));
//
//        auto s2 = splitter(d, [4, 5]);
//        assert(equal(s2, [[1,2,3], [6,7,8,9,10]]));
//    }
}

/**
Splits a range using another range as a separator. This can be used
with any range type, but is most popular with string types.
 */
struct Splitter(Range, Separator)
    if (is(typeof(Range.init.front == Separator.init.front)))
{
private:
    Range _input;
    Separator _separator;
    // _frontLength == size_t.max means empty
    size_t _frontLength = size_t.max;
    static if (isBidirectionalRange!Range)
        size_t _backLength = size_t.max;

    size_t separatorLength() { return _separator.length; }

    void ensureFrontLength()
    {
        if (_frontLength != _frontLength.max) return;
        assert(!_input.empty);
        // compute front length
        _frontLength = _input.length - find(_input, _separator).length;
        static if (isBidirectionalRange!Range)
            if (_frontLength == _input.length) _backLength = _frontLength;
    }

    void ensureBackLength()
    {
        static if (isBidirectionalRange!Range)
            if (_backLength != _backLength.max) return;
        assert(!_input.empty);
        // compute back length
        static if (isBidirectionalRange!Range)
        {
            _backLength = _input.length -
                find(retro(_input), retro(_separator)).length;
        }
    }

public:
    this(Range input, Separator separator)
    {
        _input = input;
        _separator = separator;
    }

    @property Range front()
    {
        assert(!empty);
        ensureFrontLength();
        return _input[0 .. _frontLength];
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;  // Propagate infiniteness
    }
    else
    {
        @property bool empty()
        {
            return _frontLength == size_t.max && _input.empty;
        }
    }

    void popFront()
    {
        assert(!empty);
        ensureFrontLength;
        if (_frontLength == _input.length)
        {
            // done, there's no separator in sight
            _input = _input[_frontLength .. _frontLength];
            _frontLength = _frontLength.max;
            static if (isBidirectionalRange!Range)
                _backLength = _backLength.max;
            return;
        }
        if (_frontLength + separatorLength == _input.length)
        {
            // Special case: popping the first-to-last item; there is
            // an empty item right after this.
            _input = _input[_input.length .. _input.length];
            _frontLength = 0;
            static if (isBidirectionalRange!Range)
                _backLength = 0;
            return;
        }
        // Normal case, pop one item and the separator, get ready for
        // reading the next item
        _input = _input[_frontLength + separatorLength .. _input.length];
        // mark _frontLength as uninitialized
        _frontLength = _frontLength.max;
    }

// Bidirectional functionality as suggested by Brad Roberts.
    static if (isBidirectionalRange!Range)
    {
        @property Range back()
        {
            ensureBackLength;
            return _input[_input.length - _backLength .. _input.length];
        }

        void popBack()
        {
            ensureBackLength;
            if (_backLength == _input.length)
            {
                // done
                _input = _input[0 .. 0];
                _frontLength = _frontLength.max;
                _backLength = _backLength.max;
                return;
            }
            if (_backLength + separatorLength == _input.length)
            {
                // Special case: popping the first-to-first item; there is
                // an empty item right before this. Leave the separator in.
                _input = _input[0 .. 0];
                _frontLength = 0;
                _backLength = 0;
                return;
            }
            // Normal case
            _input = _input[0 .. _input.length - _backLength - separatorLength];
            _backLength = _backLength.max;
        }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto s = ",abc, de, fg,hi,";
    auto sp0 = splitter(s, ',');
    // //foreach (e; sp0) writeln("[", e, "]");
    assert(equal(sp0, ["", "abc", " de", " fg", "hi", ""][]));

    auto s1 = ", abc, de,  fg, hi, ";
    auto sp1 = splitter(s1, ", ");
    //foreach (e; sp1) writeln("[", e, "]");
    assert(equal(sp1, ["", "abc", "de", " fg", "hi", ""][]));

    int[] a = [ 1, 2, 0, 3, 0, 4, 5, 0 ];
    int[][] w = [ [1, 2], [3], [4, 5], [] ];
    uint i;
    foreach (e; splitter(a, 0))
    {
        assert(i < w.length);
        assert(e == w[i++]);
    }
    assert(i == w.length);
    // // Now go back
    // auto s2 = splitter(a, 0);

    // foreach (e; retro(s2))
    // {
    //     assert(i > 0);
    //     assert(equal(e, w[--i]), text(e));
    // }
    // assert(i == 0);

    wstring names = ",peter,paul,jerry,";
    auto words = split(names, ",");
    assert(walkLength(words) == 5, text(walkLength(words)));
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto s6 = ",";
    auto sp6 = splitter(s6, ',');
    foreach (e; sp6)
    {
        //writeln("{", e, "}");
    }
    assert(equal(sp6, ["", ""][]));
}

struct Splitter(alias isTerminator, Range,
        Slice = Select!(is(typeof(Range.init[0 .. 1])),
                Range,
                ElementType!(Range)[]))
{
    private Range _input;
    private size_t _end;
    private alias unaryFun!isTerminator _isTerminator;

    this(Range input)
    {
        _input = input;
        if (_input.empty)
        {
            _end = _end.max;
        }
        else
        {
            // Chase first terminator
            while (_end < _input.length && !_isTerminator(_input[_end]))
            {
                ++_end;
            }
        }
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty()
        {
            return _end == _end.max;
        }
    }

    @property Range front()
    {
        assert(!empty);
        return _input[0 .. _end];
    }

    void popFront()
    {
        assert(!empty);
        if (_input.empty)
        {
            _end = _end.max;
            return;
        }
        // Skip over existing word
        _input = _input[_end .. $];
        // Skip terminator
        for (;;)
        {
            if (_input.empty)
            {
                // Nothing following the terminator - done
                _end = _end.max;
                return;
            }
            if (!_isTerminator(_input.front))
            {
                // Found a legit next field
                break;
            }
            _input.popFront();
        }
        assert(!_input.empty && !_isTerminator(_input.front));
        // Prime _end
        _end = 1;
        while (_end < _input.length && !_isTerminator(_input[_end]))
        {
            ++_end;
        }
    }
}

Splitter!(isTerminator, Range)
splitter(alias isTerminator, Range)(Range input)
if (is(typeof(unaryFun!(isTerminator)(ElementType!(Range).init))))
{
    return typeof(return)(input);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    void compare(string sentence, string[] witness)
    {
        foreach (word; splitter!"a == ' '"(sentence))
        {
            assert(word == witness.front, word);
            witness.popFront();
        }
        assert(witness.empty, witness[0]);
    }

    compare(" Mary    has a little lamb.   ",
            ["", "Mary", "has", "a", "little", "lamb."]);
    compare("Mary    has a little lamb.   ",
            ["Mary", "has", "a", "little", "lamb."]);
    compare("Mary    has a little lamb.",
            ["Mary", "has", "a", "little", "lamb."]);
    compare("", []);
    compare(" ", [""]);
}

// joiner
/**
Lazily joins a range of ranges with a separator. The range of ranges 

Example:
----
----
 */
auto joiner(Range, Separator)(Range r, Separator sep)
{
    struct Result
    {
    private:
        Range _items;
        Separator _sep, _currentSep;
    public:
        @property bool empty()
        {
            return _items.empty;
        }
        @property ElementType!(ElementType!Range) front()
        {
            assert(!empty);
            if (!_currentSep.empty) return _currentSep.front;
            if (!_items.front.empty) return _items.front.front;
            assert(false);
        }
        void popFront()
        {
            assert(!empty);
            // Using separator?
            if (!_currentSep.empty)
            {
                _currentSep.popFront();
                if (_currentSep.empty)
                {
                    // Explore the next item in the range
                    if (_items.front.empty)
                    {
                        // Null item, will write a new separator
                        _items.popFront();
                        if (!_items.empty)
                        {
                            _currentSep = _sep.save;
                        }
                    }
                }
            }
            else
            {
                // we're using the range
                assert(!_items.empty && !_items.front.empty);
                _items.front.popFront();
                if (_items.front.empty)
                {
                    _items.popFront();
                    if (!_items.empty)
                    {
                        _currentSep = _sep.save;
                    }
                }
            }
            assert(empty || !_currentSep.empty || !_items.front.empty);
        }
    }
    auto result = Result(r, sep);
    if (!r.empty && r.front.empty)
    {
        result._items.popFront();
        if (!result.empty)
        {
            result._currentSep = result._sep.save;
        }
    }
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    static assert(isInputRange!(typeof(joiner([""], ""))));
    static assert(!isForwardRange!(typeof(joiner([""], ""))));
    assert(equal(joiner([""], "xyz"), ""));
    assert(equal(joiner(["", ""], "xyz"), "xyz"));
    assert(equal(joiner(["", "abc"], "xyz"), "xyzabc"));
    assert(equal(joiner(["abc", ""], "xyz"), "abcxyz"));
    assert(equal(joiner(["abc", "def"], "xyz"), "abcxyzdef"));
    assert(equal(joiner(["Mary", "has", "a", "little", "lamb"], "..."),
                    "Mary...has...a...little...lamb"));
}

// uniq
/**
Iterates unique consecutive elements of the given range (functionality
akin to the $(WEB wikipedia.org/wiki/_Uniq, _uniq) system
utility). Equivalence of elements is assessed by using the predicate
$(D pred), by default $(D "a == b"). If the given range is
bidirectional, $(D uniq) also yields a bidirectional range.

Example:
----
int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
assert(equal(uniq(arr), [ 1, 2, 3, 4, 5 ][]));
----
*/
struct Uniq(alias pred, R)
{
    R _input;

    this(R input)
    {
        _input = input;
    }

    ref Uniq opSlice()
    {
        return this;
    }

    void popFront()
    {
        auto last = _input.front;
        do
        {
            _input.popFront;
        }
        while (!_input.empty && binaryFun!(pred)(last, _input.front));
    }

    @property ElementType!(R) front() { return _input.front; }

    static if (isBidirectionalRange!R)
    {
        void popBack()
        {
            auto last = _input.back;
            do
            {
                _input.popBack;
            }
            while (!_input.empty && binaryFun!(pred)(last, _input.back));
        }

        @property ElementType!(R) back() { return _input.back; }
    }

    static if (isInfinite!R)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty() { return _input.empty; }
    }


    static if (isForwardRange!R) {
        @property typeof(this) save() {
            return typeof(this)(_input.save);
        }
    }
}

/// Ditto
Uniq!(pred, Range) uniq(alias pred = "a == b", Range)(Range r)
{
    return typeof(return)(r);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
    auto r = uniq(arr);
    assert(equal(r, [ 1, 2, 3, 4, 5 ][]));
    assert(equal(retro(r), retro([ 1, 2, 3, 4, 5 ][])));

    foreach(DummyType; AllDummyRanges) {
        DummyType d;
        auto u = uniq(d);
        assert(equal(u, [1,2,3,4,5,6,7,8,9,10]));

        static assert(d.rt == RangeType.Input || isForwardRange!(typeof(u)));

        static if (d.rt >= RangeType.Bidirectional) {
            assert(equal(retro(u), [10,9,8,7,6,5,4,3,2,1]));
        }
    }
}

// group
/**
Similarly to $(D uniq), $(D group) iterates unique consecutive
elements of the given range. The element type is $(D
Tuple!(ElementType!R, uint)) because it includes the count of
equivalent elements seen. Equivalence of elements is assessed by using
the predicate $(D pred), by default $(D "a == b").

$(D Group) is an input range if $(D R) is an input range, and a
forward range in all other cases.

Example:
----
int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
assert(equal(group(arr), [ tuple(1, 1u), tuple(2, 4u), tuple(3, 1u),
    tuple(4, 3u), tuple(5, 1u) ][]));
----
*/
struct Group(alias pred, R) if (isInputRange!R)
{
    private R _input;
    private Tuple!(ElementType!R, uint) _current;
    private alias binaryFun!pred comp;

    this(R input)
    {
        _input = input;
        if (!_input.empty) popFront;
    }

    void popFront()
    {
        if (_input.empty)
        {
            _current.field[1] = 0;
        }
        else
        {
            _current = tuple(_input.front, 1u);
            _input.popFront;
            while (!_input.empty && comp(_current.field[0], _input.front))
            {
                ++_current.field[1];
                _input.popFront;
            }
        }
    }

    static if (isInfinite!R)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty()
        {
            return _current.field[1] == 0;
        }
    }

    @property ref Tuple!(ElementType!R, uint) front()
    {
        assert(!empty);
        return _current;
    }

    static if (isForwardRange!R) {
        @property typeof(this) save() {
            typeof(this) ret;
            ret._input = this._input.save;
            ret._current = this._current;

            return ret;
        }
    }
}

/// Ditto
Group!(pred, Range) group(alias pred = "a == b", Range)(Range r)
{
    return typeof(return)(r);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
    assert(equal(group(arr), [ tuple(1, 1u), tuple(2, 4u), tuple(3, 1u),
                            tuple(4, 3u), tuple(5, 1u) ][]));

    foreach(DummyType; AllDummyRanges) {
        DummyType d;
        auto g = group(d);

        static assert(d.rt == RangeType.Input || isForwardRange!(typeof(g)));

        assert(equal(g, [tuple(1, 1u), tuple(2, 1u), tuple(3, 1u), tuple(4, 1u),
            tuple(5, 1u), tuple(6, 1u), tuple(7, 1u), tuple(8, 1u),
            tuple(9, 1u), tuple(10, 1u)]));
    }
}

// overwriteAdjacent
/*
Reduces $(D r) by shifting it to the left until no adjacent elements
$(D a), $(D b) remain in $(D r) such that $(D pred(a, b)). Shifting is
performed by evaluating $(D move(source, target)) as a primitive. The
algorithm is stable and runs in $(BIGOH r.length) time. Returns the
reduced range.

The default $(XREF _algorithm, move) performs a potentially
destructive assignment of $(D source) to $(D target), so the objects
beyond the returned range should be considered "empty". By default $(D
pred) compares for equality, in which case $(D overwriteAdjacent)
collapses adjacent duplicate elements to one (functionality akin to
the $(WEB wikipedia.org/wiki/Uniq, uniq) system utility).

Example:
----
int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
auto r = overwriteAdjacent(arr);
assert(r == [ 1, 2, 3, 4, 5 ]);
----
*/
// Range overwriteAdjacent(alias pred, alias move, Range)(Range r)
// {
//     if (r.empty) return r;
//     //auto target = begin(r), e = end(r);
//     auto target = r;
//     auto source = r;
//     source.popFront;
//     while (!source.empty)
//     {
//         if (!pred(target.front, source.front))
//         {
//             target.popFront;
//             continue;
//         }
//         // found an equal *source and *target
//         for (;;)
//         {
//             //@@@
//             //move(source.front, target.front);
//             target[0] = source[0];
//             source.popFront;
//             if (source.empty) break;
//             if (!pred(target.front, source.front)) target.popFront;
//         }
//         break;
//     }
//     return range(begin(r), target + 1);
// }

// /// Ditto
// Range overwriteAdjacent(
//     string fun = "a == b",
//     alias move = .move,
//     Range)(Range r)
// {
//     return .overwriteAdjacent!(binaryFun!(fun), move, Range)(r);
// }

// unittest
// {
//     int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
//     auto r = overwriteAdjacent(arr);
//     assert(r == [ 1, 2, 3, 4, 5 ]);
//     assert(arr == [ 1, 2, 3, 4, 5, 3, 4, 4, 4, 5 ]);

// }

// find
/**
Finds an individual element in an input range. Elements of $(D
haystack) are compared with $(D needle) by using predicate $(D
pred). Performs $(BIGOH n) evaluations of $(D pred), where $(D n) is
the length of $(D haystack). See also $(WEB
sgi.com/tech/stl/_find.html, STL's _find).

To find the last occurence of $(D needle) in $(D haystack), call $(D
find(retro(haystack), needle)). See also $(XREF range, retro).

Params:

haystack = The target of the search.

needle = The range searched for.

Constraints:

$(D isInputRange!R && is(typeof(binaryFun!pred(haystack.front, needle)
: bool)))

Returns:

$(D haystack) advanced such that $(D binaryFun!pred(haystack.front,
needle)) is $(D true) (if no such position exists, returns $(D
haystack) after exhaustion).

Example:

----
assert(find("hello, world", ',') == ", world");
assert(find([1, 2, 3, 5], 4) == []);
assert(find(SList!int(1, 2, 3, 4, 5)[], 4) == SList!int(4, 5)[]);
assert(find!"a > b"([1, 2, 3, 5], 2) == [3, 5]);

auto a = [ 1, 2, 3 ];
assert(find(a, 5).empty);       // not found
assert(!find(a, 2).empty);      // found

// Case-insensitive find of a string
string[] s = [ "Hello", "world", "!" ];
assert(!find!("tolower(a) == b")(s, "hello").empty);
----
 */
R find(alias pred = "a == b", R, E)(R haystack, E needle)
if (isInputRange!R &&
        is(typeof(binaryFun!pred(haystack.front, needle)) : bool))
{
    for (; !haystack.empty; haystack.popFront())
    {
        if (binaryFun!pred(haystack.front, needle)) break;
    }
    return haystack;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto lst = SList!int(1, 2, 5, 7, 3);
    assert(lst.front == 1);
    auto r = find(lst[], 5);
    assert(equal(r, SList!int(5, 7, 3)[]));
    assert(find([1, 2, 3, 5], 4).empty);
}

/**
Finds a forward range in another. Elements are compared for
equality. Performs $(BIGOH walkLength(haystack) * walkLength(needle))
comparisons in the worst case. Specializations taking advantage of
bidirectional or random access (where present) may accelerate search
depending on the statistics of the two ranges' content.

Params:

haystack = The target of the search.

needle = The range searched for.

Constraints:

$(D isForwardRange!R1 && isForwardRange!R2 && is(typeof(haystack.front
== needle.front) : bool))

Returns:

$(D haystack) advanced such that $(D needle) is a prefix of it (if no
such position exists, returns $(D haystack) advanced to termination).

----
assert(find("hello, world", "World").empty);
assert(find("hello, world", "wo") == "world");
assert(find([1, 2, 3, 4], SList!(2, 3)[]) == [2, 3, 4]);
----
 */
R1 find(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && isForwardRange!R2
        && is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool)
        && !isRandomAccessRange!R1)
{
    static if (pred == "a == b" && isSomeString!R1 && isSomeString!R2
            && haystack[0].sizeof == needle[0].sizeof)
    {
        alias Select!(haystack[0].sizeof == 1, ubyte[],
                Select!((ElementType!R1).sizeof == 2, ushort[], uint[]))
            Representation1;
        alias Select!(needle[0].sizeof == 1, ubyte[],
                Select!((ElementType!R2).sizeof == 2, ushort[], uint[]))
            Representation2;
        return cast(R1) .find!(pred, Representation1, Representation2)
            (cast(Representation1) haystack, cast(Representation2) needle);
    }
    else
    {
      searching:
        for (; !haystack.empty; haystack.popFront())
        {
            for (auto h = haystack.save, n = needle.save; !n.empty;
                 n.popFront())
            {
                if (!binaryFun!pred(h.front, needle.front)) continue searching;
            }
            break;
        }
        return haystack;
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto lst = SList!int(1, 2, 5, 7, 3);
    static assert(isForwardRange!(int[]));
    static assert(isForwardRange!(typeof(lst[])));
    auto r = find(lst[], [2, 5]);
    assert(equal(r, SList!int(2, 5, 7, 3)[]));
}

// Specialization for searching a random-access range for a
// bidirectional range
R1 find(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isRandomAccessRange!R1 && isBidirectionalRange!R2
        && is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool))
{
    if (needle.empty) return haystack;
    const needleLength = walkLength(needle);
    if (needleLength > haystack.length)
    {
        // @@@BUG@@@
        //return haystack[$ .. $];
        return haystack[haystack.length .. haystack.length];
    }
    // @@@BUG@@@
    // auto needleBack = moveBack(needle);
    // Stage 1: find the step
    size_t step = 1;
    auto needleBack = needle.back;
    needle.popBack();
    for (auto i = needle.save; !i.empty && !binaryFun!pred(i.back, needleBack);
         i.popBack(), ++step)
    {
    }
    // Stage 2: linear find
    size_t scout = needleLength - 1;
    for (;;)
    {
        if (scout >= haystack.length)
        {
            return haystack[haystack.length .. haystack.length];
        }
        if (!binaryFun!pred(haystack[scout], needleBack))
        {
            ++scout;
            continue;
        }
        // Found a match with the last element in the needle
        auto cand = haystack[scout + 1 - needleLength .. haystack.length];
        if (startsWith!pred(cand, needle))
        {
            // found
            return cand;
        }
        // Continue with the stride
        scout += step;
    }
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // @@@BUG@@@ removing static below makes unittest fail
    static struct BiRange
    {
        int[] payload;
        @property bool empty() { return payload.empty; }
        @property BiRange save() { return this; }
        @property ref int front() { return payload[0]; }
        @property ref int back() { return payload[$ - 1]; }
        void popFront() { return payload.popFront(); }
        void popBack() { return payload.popBack(); }
    }
    //static assert(isBidirectionalRange!BiRange);
    auto r = BiRange([1, 2, 3, 10, 11, 4]);
    //assert(equal(find(r, [3, 10]), BiRange([3, 10, 11, 4])));
    //assert(find("abc", "bc").length == 2);
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    //assert(find!"a == b"("abc", "bc").length == 2);
}

/+
// Binary search
    static if (is(Range.AssumeSorted)
            // @@@ BUG static if can't do alias parms - this shouldn't
            // be here
            && pred == "a == b")
    {
        auto lhs = haystack.assumeSorted;
        foreach (i, Unused; Ranges)
        {
            alias needles[i] rhs;
            static if (is(typeof(binaryFun!(pred)(lhs.front, rhs))))
            {
                // Single-element lookup
                auto r = lowerBound!(Range.assumeSortedBy)(lhs, rhs);
                // found?
                if (r.length < lhs.length
                        && binaryFun!(pred)(lhs[r.length], rhs))
                    return select!(Ranges.length == 1)(
                        lhs[r.length .. lhs.length],
                        tuple(lhs[r.length .. lhs.length], i + 1));
                // not found, march on
            }
            else
            {
                // Subrange lookup
                if (rhs.empty) continue;
                auto lb = lowerBound!(Range.assumeSortedBy)(lhs, rhs.front);
                if (lb.length == lhs.length) continue; // not found
                auto eq = equalRange!(Range.assumeSortedBy)(lb, rhs.front);
                foreach (j; lb.length .. lb.length + eq.length)
                {
                    if (startsWith!(pred)(lhs[j .. $], rhs[]))
                        return select!(Ranges.length == 1)(
                            lhs[j .. $], tuple(lhs[j .. $], i + 1));
                }
            }
        }
        // not found
        return select!(Ranges.length == 1)(lhs.init, tuple(lhs.init, 0u));
    }
+/

/* *
Generalized routine for finding one or more $(D needles) into a $(D
haystack). Some or all of $(D haystack) and $(D needles) may be
structured in various ways, which translates in the speed of $(D
find). The predicate $(D pred) is used throughout to compare
elements. By default, elements are compared for equality.

Params:

haystack = The target of the search. Must be an $(GLOSSARY input
range). If any of $(D needles) is a range with elements comparable to
elements in $(D haystack), then $(D haystack) must be a $(GLOSSARY
forward range) such that the search can backtrack.

needles = One or more items to search for. Each of $(D needles) must
be either comparable to one element in $(D haystack), or be itself a
$(GLOSSARY forward range) with elements comparable with elements in
$(D haystack).

Returns:

$(UL $(LI If $(D needles.length == 1), returns $(D haystack) advanced
such that $(D needles[0]) is a prefix of it (if no such position
exists, returns an empty range).)  $(LI If $(D needles.length > 1),
returns a tuple containing $(D haystack) positioned as above and also
the 1-based index of the matching element in $(D needles) (0 if none
of $(D needles) matched, 1 if $(D needles[0]) matched, 2 if $(D
needles[1]) matched...).))

The relationship between $(D haystack) and $(D needles) simply means
that one can e.g. search for individual $(D int)s, or arrays of $(D
int)s, in an array of $(D int)s. In addition, if elements are
individually comparable, searches of heterogeneous types are allowed
as well: a $(D double[]) can be searched for an $(D int) or a $(D
short[]), and conversely a $(D long) can be searched for a $(D float)
or a $(D double[]). This makes for efficient searches without the need
to coerce one side of the comparison into the other's side type.

Example:
----
int[] a = [ 1, 4, 2, 3 ];
assert(find(a, 4) == [ 4, 2, 3 ]);
assert(find(a, [ 1, 4 ]) == [ 1, 4, 2, 3 ]);
assert(find(a, [ 1, 3 ], 4) == tuple([ 4, 2, 3 ], 2));
// Mixed types allowed if comparable
assert(find(a, 5, [ 1.2, 3.5 ], 2.0, [ 1 ]) == tuple([ 2, 3 ], 3));
----

The complexity of the search is $(BIGOH haystack.length *
max(needles.length)). (For needles that are individual items, length
is considered to be 1.) The strategy used in searching several
subranges at once maximizes cache usage by moving in $(D haystack) as
few times as possible.

BoyerMoore:

If one or more of the $(D needles) has type $(D BoyerMooreFinder), the
search for those particular needles is performed by using the $(WEB
www-igm.univ-mlv.fr/~lecroq/string/node14.html, Boyer-Moore
algorithm). In this case $(D haystack) must offer random access. The
algorithm has an upfront cost but scales sublinearly, so it is most
suitable for large sequences. Performs $(BIGOH haystack.length)
evaluations of $(D pred) in the worst case and $(BIGOH haystack.length
/ needle.length) evaluations in the best case.

The $(D BoyerMooreFinder)-structured $(D needles), if any, must be
placed at the front of the searched items. This is because they will
be searched separately, not in lockstep with any other $(D
needles). To add Boyer-Moore structure to any of $(D needles), simply
wrap it in a $(D boyerMooreFinder) call as shown below.

Example:
----
int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
int[] b = [ 1, 2, 3 ];
assert(find(a, boyerMooreFinder(b), 1) == tuple([ 1, 2, 3, 4, 5 ], 1));
assert(find(b, boyerMooreFinder(a)).empty);
----

Sorted:

Searching can be sped up considerably if $(D haystack) is already
sorted by an ordering predicate $(D less). The speedup can only occur
if the following relation between $(D pred) and $(D less) holds:

$(D pred(a, b) == (!less(a, b) && !less(b, a)))

The default predicate for $(D find), which is $(D "a == b"), and the
default predicate for $(D assumeSorted), which is $(D "a < b"),
already satisfy the relation.

If the above condition is satisfied, only $(BIGOH
log(haystack.length)) steps are needed to position $(D haystack) at
the beginning of the search. Also, once positioned, the search will
continue only as long as haystack and the needle start with equal
elements. To inform $(D find) that you want to perform a binary
search, wrap $(D haystack) with a call to $(XREF exception,
assumeSorted). Then $(D find) will assume that $(D pred) and $(D less)
are in the right relation and also that $(D haystack) is already
sorted by $(D less).

Example:
----
int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
assert(find(assumeSorted(a), 3) == [ 3, 4, 5 ]);
assert(find(assumeSorted(a), [3, 4]) == [ 3, 4, 5 ]);
assert(find(assumeSorted(a), [3, 5], [1, 3], 8).empty);
----
 */
/+
FindResult!(Range, Ranges)
find(alias pred = "a == b", Range, Ranges...)
(Range haystack, Ranges needles)
if (!isArray!Range && !isArray!(Ranges[0]))
//if (allSatisfy!(isInputRange, Ranges))
//if (!is(typeof(Ranges[0].init.findReflect(Range.init))))
{
    static if (is(typeof(needles[0].findReflect(haystack))))
    {
        // The first needle is organized for fast finding
        auto result = needles[0].findReflect(haystack);
        static if (Ranges.length == 1)
        {
            return result; // found or not, that's all we could do
        }
        else
        {
            auto r = find!(pred)(lhs, rhs[1 .. $]);
            if (r.field[1]) ++r.field[1];
            return r;
        }
    }
    else
    {
        // Bona fide find
        static if (Ranges.length == 1 && allSatisfy!(hasLength, Ranges, Range)
                && is(typeof(binaryFun!(pred)(haystack[1], needles[0][1]))))
        {
            alias needles[0] needle;
            if (haystack.length < needle.length) return haystack[$ .. $];
            foreach (i; 0 .. haystack.length - needle.length + 1)
            {
                auto h = haystack[i .. $];
                auto r = startsWith!(pred)(h, needle);
                if (r) return h;
            }
            return haystack[$ .. $];
        }
        else
        {
            for (;; haystack.popFront)
            {
                auto r = startsWith!(pred)(haystack, needles);
                if (r || haystack.empty)
                {
                    static if (Ranges.length == 1) return haystack;
                    else return tuple(haystack, r);
                }
            }
        }
    }
}
+/

version(none) unittest
{
    scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    assert(find(assumeSorted(a), 3) == [3, 4, 5][]);
    assert(find(assumeSorted(a), 9).empty);
    assert(find(assumeSorted(a), 5) == [5]);
    assert(find(assumeSorted(a), -2).empty);
    assert(find(assumeSorted(a), [3, 5]).empty);
    assert(find(assumeSorted(a), [3, 5], [1, 3], 8).field[1] == 0);
}

version(none) unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto s1 = "Mary has a little lamb";
    //writeln(find(s1, "has a", "has an"));
    assert(find(s1, "has a", "has an") == tuple("has a little lamb", 1));
    assert(find("abc", "bc").length == 2);
}

version(none) unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    assert(find(a, 5).empty);
    assert(find(a, 2) == [2, 3]);

    foreach (T; TypeTuple!(int, double))
    {
        auto b = rndstuff!(T)();
        if (!b.length) continue;
        b[$ / 2] = 200;
        b[$ / 4] = 200;
        assert(find(b, 200).length == b.length - b.length / 4);
    }

// Case-insensitive find of a string
    string[] s = [ "Hello", "world", "!" ];
    //writeln(find!("toupper(a) == toupper(b)")(s, "hello"));
    assert(find!("toupper(a) == toupper(b)")(s, "hello").length == 3);

    static bool f(string a, string b) { return toupper(a) == toupper(b); }
    assert(find!(f)(s, "hello").length == 3);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 2, 6 ];
    assert(find(std.range.retro(a), 5).empty);
    assert(equal(find(std.range.retro(a), 2), [ 2, 3, 2, 1 ][]));

    foreach (T; TypeTuple!(int, double))
    {
        auto b = rndstuff!(T)();
        if (!b.length) continue;
        b[$ / 2] = 200;
        b[$ / 4] = 200;
        assert(find(std.range.retro(b), 200).length ==
                b.length - (b.length - 1) / 2);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    assert(find(a, b) == [ 1, 2, 3, 4, 5 ]);
    assert(find(b, a).empty);

    foreach(DummyType; AllDummyRanges) {
        DummyType d;
        auto findRes = find(d, 5);
        assert(equal(findRes, [5,6,7,8,9,10]));
    }
}

/// Ditto
struct BoyerMooreFinder(alias pred, Range)
{
private:
    size_t skip[];
    int[ElementType!(Range)] occ;
    Range needle;

    int occurrence(ElementType!(Range) c)
    {
        auto p = c in occ;
        return p ? *p : -1;
    }

/*
This helper function checks whether the last "portion" bytes of
"needle" (which is "nlen" bytes long) exist within the "needle" at
offset "offset" (counted from the end of the string), and whether the
character preceding "offset" is not a match.  Notice that the range
being checked may reach beyond the beginning of the string. Such range
is ignored.
 */
    static bool needlematch(R)(R needle,
                              size_t portion, size_t offset)
    {
        int virtual_begin = needle.length - offset - portion;
        int ignore = 0;
        if (virtual_begin < 0) {
            ignore = -virtual_begin;
            virtual_begin = 0;
        }
        if (virtual_begin > 0
            && needle[virtual_begin - 1] == needle[$ - portion - 1])
            return 0;

        immutable delta = portion - ignore;
        return equal(needle[needle.length - delta .. needle.length],
                needle[virtual_begin .. virtual_begin + delta]);
    }

public:
    this(Range needle)
    {
        if (!needle.length) return;
        this.needle = needle;
        /* Populate table with the analysis of the needle */
        /* But ignoring the last letter */
        foreach (i, n ; needle[0 .. $ - 1])
        {
            this.occ[n] = i;
        }
        /* Preprocess #2: init skip[] */
        /* Note: This step could be made a lot faster.
         * A simple implementation is shown here. */
        this.skip = new size_t[needle.length];
        foreach (a; 0 .. needle.length)
        {
            size_t value = 0;
            while (value < needle.length
                   && !needlematch(needle, a, value))
            {
                ++value;
            }
            this.skip[needle.length - a - 1] = value;
        }
    }

    Range findReflect(Range haystack)
    {
        if (!needle.length) return haystack;
        if (needle.length > haystack.length) return haystack[$ .. $];
        /* Search: */
        auto limit = haystack.length - needle.length;
        for (size_t hpos = 0; hpos <= limit; )
        {
            size_t npos = needle.length - 1;
            while (pred(needle[npos], haystack[npos+hpos]))
            {
                if (npos == 0) return haystack[hpos .. $];
                --npos;
            }
            hpos += max(skip[npos], npos - occurrence(haystack[npos+hpos]));
        }
        return haystack[$ .. $];
    }

    @property size_t length()
    {
        return needle.length;
    }
}

/// Ditto
BoyerMooreFinder!(binaryFun!(pred), Range) boyerMooreFinder
(alias pred = "a == b", Range)
(Range needle) if (isRandomAccessRange!(Range) || isSomeString!Range)
{
    return typeof(return)(needle);
}

version(none) unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    string h = "/homes/aalexand/d/dmd/bin/../lib/libphobos.a(dmain2.o)"
        "(.gnu.linkonce.tmain+0x74): In function `main' undefined reference"
        " to `_Dmain':";
    string[] ns = ["libphobos", "function", " undefined", "`", ":"];
    foreach (n ; ns) {
        auto p = find(h, boyerMooreFinder(n));
        assert(!p.empty);
    }

    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    //writeln(find(a, boyerMooreFinder(b)));
    assert(find(a, boyerMooreFinder(b)) == [ 1, 2, 3, 4, 5 ]);
    assert(find(b, boyerMooreFinder(a)).empty);
}

/**
Advances the input range $(D haystack) by calling $(D haystack.popFront)
until either $(D pred(haystack.front)), or $(D
haystack.empty). Performs $(BIGOH haystack.length) evaluations of $(D
pred). See also $(WEB sgi.com/tech/stl/find_if.html, STL's find_if).

To find the last element of a bidirectional $(D haystack) satisfying
$(D pred), call $(D find!(pred)(retro(haystack))). See also $(XREF
range, retro).

Example:
----
auto arr = [ 1, 2, 3, 4, 1 ];
assert(find!("a > 2")(arr) == [ 3, 4, 1 ]);

// with predicate alias
bool pred(int x) { return x + 1 > 1.5; }
assert(find!(pred)(arr) == arr);
----
*/
Range find(alias pred, Range)(Range haystack) if (isInputRange!(Range))
{
    alias unaryFun!(pred) predFun;
    for (; !haystack.empty && !predFun(haystack.front); haystack.popFront)
    {
    }
    return haystack;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    assert(find!("a > 2")(a) == [3]);
    bool pred(int x) { return x + 1 > 1.5; }
    assert(find!(pred)(a) == a);
}

/**
If $(D haystack) supports slicing, returns the smallest number $(D n)
such that $(D haystack[n .. $].startsWith!pred(needle)). Oherwise,
returns the smallest $(D n) such that after $(D n) calls to $(D
haystack.popFront), $(D haystack.startsWith!pred(needle)). If no such
number could be found, return $(D -1).
 */
int indexOf(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (is(typeof(startsWith!pred(haystack, needle))))
{
    static if (isNarrowString!R1)
    {
        // Narrow strings are handled a bit differently
        auto length = haystack.length;
        for (; !haystack.empty; haystack.popFront)
        {
            if (startsWith!pred(haystack, needle))
            {
                return length - haystack.length;
            }
        }
    }
    else
    {
        typeof(return) result;
        for (; !haystack.empty; ++result, haystack.popFront())
        {
            if (startsWith!pred(haystack, needle)) return result;
        }
    }
    return -1;
}

/**
Interval option specifier for $(D until) (below) and others.
 */
enum OpenRight
{
    no, /// Interval is closed to the right (last element included)
    yes /// Interval is open to the right (last element is not included)
}

/**
Lazily iterates $(D range) until value $(D sentinel) is found, at
which point it stops.

Example:
----
int[] a = [ 1, 2, 4, 7, 7, 2, 4, 7, 3, 5];
assert(equal(a.until(7), [1, 2, 4][]));
assert(equal(a.until(7, OpenRight.no), [1, 2, 4, 7][]));
----
 */
struct Until(alias pred, Range, Sentinel) if (isInputRange!Range)
{
    private Range _input;
    static if (!is(Sentinel == void))
        private Sentinel _sentinel;
    // mixin(bitfields!(
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    //             uint, "", 6));
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    OpenRight _openRight;
    bool _done;

    static if (!is(Sentinel == void))
        this(Range input, Sentinel sentinel,
                OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _sentinel = sentinel;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }
    else
        this(Range input, OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }

    @property bool empty()
    {
        return _done;
    }

    @property ElementType!Range front()
    {
        assert(!empty);
        return _input.front;
    }

    bool predSatisfied()
    {
        static if (is(Sentinel == void))
            return unaryFun!pred(_input.front);
        else
            return binaryFun!pred(_input.front, _sentinel);
    }

    void popFront()
    {
        assert(!empty);
        if (!_openRight)
        {
            if (predSatisfied())
            {
                _done = true;
                return;
            }
            _input.popFront;
            _done = _input.empty;
        }
        else
        {
            _input.popFront;
            _done = _input.empty || predSatisfied;
        }
    }

    static if (!is(Sentinel == void))
        @property Until save()
        {
            Until result;

            result._input     = _input.save;
            result._sentinel  = _sentinel;
            result._openRight = _openRight;
            result._done      = _done;

            return result;
        }
    else
        @property Until save()
        {
            Until result;

            result._input     = _input.save;
            result._openRight = _openRight;
            result._done      = _done;

            return result;
        }
}

/// Ditto
Until!(pred, Range, Sentinel)
until(alias pred = "a == b", Range, Sentinel)
(Range range, Sentinel sentinel, OpenRight openRight = OpenRight.yes)
if (!is(Sentinel == OpenRight))
{
    return typeof(return)(range, sentinel, openRight);
}

/// Ditto
Until!(pred, Range, void)
until(alias pred, Range)
(Range range, OpenRight openRight = OpenRight.yes)
{
    return typeof(return)(range, openRight);
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 7, 7, 2, 4, 7, 3, 5];

    assert(isForwardRange!(typeof(a.until(7))));
    assert(isForwardRange!(typeof(until!"a == 2"(a, OpenRight.no))));

    assert(equal(a.until(7), [1, 2, 4][]));
    assert(equal(a.until(7, OpenRight.no), [1, 2, 4, 7][]));
    assert(equal(until!"a == 2"(a, OpenRight.no), [1, 2][]));
}

/**
If the range $(D doesThisStart) starts with $(I any) of the $(D
withOneOfThese) ranges or elements, returns 1 if it starts with $(D
withOneOfThese[0]), 2 if it starts with $(D withOneOfThese[1]), and so
on. If no match, returns 0.

Example:
----
assert(startsWith("abc", ""));
assert(startsWith("abc", "a"));
assert(!startsWith("abc", "b"));
assert(startsWith("abc", 'a', "b") == 1);
assert(startsWith("abc", "b", "a") == 2);
assert(startsWith("abc", "a", "a") == 1);
assert(startsWith("abc", "x", "a", "b") == 2);
assert(startsWith("abc", "x", "aa", "ab") == 3);
assert(startsWith("abc", "x", "aaa", "sab") == 0);
assert(startsWith("abc", "x", "aaa", "a", "sab") == 3);
----
 */
Select!(Ranges.length == 1, bool, uint)
startsWith(alias pred = "a == b", Range, Ranges...)
(Range doesThisStart, Ranges withOneOfThese)
if (isInputRange!Range && Ranges.length > 0
        // TODO: the condition below is incomplete
        && is(typeof(binaryFun!pred(doesThisStart.front,
                                withOneOfThese[0].front))))
{
    alias doesThisStart lhs;
    alias withOneOfThese rhs;
    // Special  case for two arrays
    static if (Ranges.length == 1 && isArray!(Range) && isArray!(Ranges[0])
            && is(typeof(binaryFun!(pred)(lhs[0], rhs[0][0]))))
    {
        alias doesThisStart haystack;
        alias withOneOfThese[0] needle;
        //writeln("Matching: ", haystack, " with ", needle);
        if (haystack.length < needle.length) return 0;
        foreach (j; 0 .. needle.length)
        {
            if (!binaryFun!(pred)(needle[j], haystack[j]))
                // not found
                return 0u;
        }
        // found!
        return 1u;
    }
    else
    {
        // Make one pass looking for empty ranges
        foreach (i, Unused; Ranges)
        {
            // Empty range matches everything
            if (rhs[i].empty) return i + 1;
        }
        bool mismatch[Ranges.length];
        uint mismatched;
        for (; !lhs.empty; lhs.popFront)
        {
            foreach (i, Unused; Ranges)
            {
                if (mismatch[i]) continue;
                if (binaryFun!pred(lhs.front, rhs[i].front))
                {
                    // Stay in the game
                    rhs[i].popFront();
                    // Done with success if exhausted
                    if (rhs[i].empty) return i + 1;
                }
                else
                {
                    // Out with this guy, or maybe everyone
                    if (++mismatched == Ranges.length)
                    {
                        return 0;
                    }
                    mismatch[i] = true;
                }
            }
        }
        return 0;
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    bool x = startsWith("ab", "a");
    assert(startsWith("abc", ""));
    assert(startsWith("abc", "a"));
    assert(!startsWith("abc", "b"));
    assert(!startsWith("abc", "b", "bc", "abcd", "xyz"));
    assert(startsWith("abc", "a", "b") == 1);
    assert(startsWith("abc", "b", "a") == 2);
    assert(startsWith("abc", "a", "a") == 1);
    assert(startsWith("abc", "x", "a", "b") == 2);
    assert(startsWith("abc", "x", "aa", "ab") == 3);
    assert(startsWith("abc", "x", "aaa", "sab") == 0);
    assert(startsWith("abc", "x", "aaa", "a", "sab") == 3);
}

/**
Checks whether $(D doesThisStart) starts with one of the individual
elements $(D withOneOfThese) according to $(D pred).

Example:
----
assert(startsWith("abc", 'x', 'n', 'a') == 3);
----
 */
uint startsWith(alias pred = "a == b", Range, Elements...)
(Range doesThisStart, Elements withOneOfThese)
if (isInputRange!Range && Elements.length > 0
        && is(typeof(binaryFun!pred(doesThisStart.front, withOneOfThese[0]))))
{
    if (doesThisStart.empty) return 0;
    auto front = doesThisStart.front;
    foreach (i, Unused; Elements)
    {
        if (binaryFun!pred(front, withOneOfThese[i])) return i + 1;
    }
    return 0;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(!startsWith("abc", 'x', 'n', 'b'));
    assert(startsWith("abc", 'x', 'n', 'a') == 3);
}

/**
If $(D startsWith(r1, r2)), consume the corresponding elements off $(D
r1) and return $(D true). Otherwise, leave $(D r1) unchanged and
return $(D false).
 */
bool skipOver(alias pred = "a == b", R1, R2)(ref R1 r1, R2 r2)
if (is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    auto r = r1.save;
    while (!r2.empty && !r.empty && binaryFun!pred(r.front, r2.front))
    {
        r.popFront();
        r2.popFront();
    }
    return r2.empty ? (r1 = r, true) : false;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto s1 = "Hello world";
    assert(!skipOver(s1, "Ha"));
    assert(s1 == "Hello world");
    assert(skipOver(s1, "Hell") && s1 == "o world");
}

/**
Checks whether a range starts with an element, and if so, consume that
element off $(D r) and return $(D true). Otherwise, leave $(D r)
unchanged and return $(D false).
 */
bool skipOver(alias pred = "a == b", R, E)(ref R r, E e)
if (is(typeof(binaryFun!pred(r.front, e))))
{
    return binaryFun!pred(r.front, e)
        ? (r.popFront(), true)
        : false;
}

unittest {
    auto s1 = "Hello world";
    assert(!skipOver(s1, "Ha"));
    assert(s1 == "Hello world");
    assert(skipOver(s1, "Hell") && s1 == "o world");
}

/**
The reciprocal of $(D startsWith).

Example:
----
assert(endsWith("abc", ""));
assert(!endsWith("abc", "b"));
assert(endsWith("abc", "a", 'c') == 2);
assert(endsWith("abc", "c", "a") == 1);
assert(endsWith("abc", "c", "c") == 1);
assert(endsWith("abc", "x", "c", "b") == 2);
assert(endsWith("abc", "x", "aa", "bc") == 3);
assert(endsWith("abc", "x", "aaa", "sab") == 0);
assert(endsWith("abc", "x", "aaa", 'c', "sab") == 3);
----
 */
uint
endsWith(alias pred = "a == b", Range, Ranges...)
(Range doesThisEnd, Ranges withOneOfThese)
if (isInputRange!(Range) && Ranges.length > 0
        && is(typeof(binaryFun!pred(doesThisEnd.back, withOneOfThese[0].back))))
{
    alias doesThisEnd lhs;
    alias withOneOfThese rhs;
    // Special  case for two arrays
    static if (Ranges.length == 1 && isArray!(Range) && isArray!(Ranges[0])
            && is(typeof(binaryFun!(pred)(lhs[0], rhs[0][0]))))
    {
        if (lhs.length < rhs[0].length) return 0;
        auto k = lhs.length - rhs[0].length;
        foreach (j; 0 .. rhs[0].length)
        {
            if (!binaryFun!(pred)(rhs[0][j], lhs[j + k]))
                // not found
                return 0u;
        }
        // found!
        return 1u;
    }
    else
    {
        // Make one pass looking for empty ranges
        foreach (i, Unused; Ranges)
        {
            // Empty range matches everything
            if (rhs[i].empty) return i + 1;
        }
        bool mismatch[Ranges.length];
        for (; !lhs.empty; lhs.popBack)
        {
            foreach (i, Unused; Ranges)
            {
                if (mismatch[i]) continue;
                if (binaryFun!pred(lhs.back, rhs[i].back))
                {
                    // Stay in the game
                    rhs[i].popBack();
                    // Done with success if exhausted
                    if (rhs[i].empty) return i + 1;
                }
                else
                {
                    // Out
                    mismatch[i] = true;
                }
            }
        }
        return 0;
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(endsWith("abc", ""));
    assert(!endsWith("abc", "a"));
    assert(!endsWith("abc", 'a'));
    assert(!endsWith("abc", "b"));
    assert(endsWith("abc", "a", "c") == 2);
    assert(endsWith("abc", 'a', 'c') == 2);
    assert(endsWith("abc", "c", "a") == 1);
    assert(endsWith("abc", "c", "c") == 1);
    assert(endsWith("abc", "x", "c", "b") == 2);
    assert(endsWith("abc", "x", "aa", "bc") == 3);
    assert(endsWith("abc", "x", "aaa", "sab") == 0);
    assert(endsWith("abc", "x", "aaa", "c", "sab") == 3);
    // string a = "abc";
    // immutable(char[1]) b = "c";
    // assert(wyda(a, b));
}

/**
Checks whether $(D doesThisEnd) starts with one of the individual
elements $(D withOneOfThese) according to $(D pred).

Example:
----
assert(endsWith("abc", 'x', 'c', 'a') == 2);
----
 */
uint endsWith(alias pred = "a == b", Range, Elements...)
(Range doesThisEnd, Elements withOneOfThese)
if (isInputRange!Range && Elements.length > 0
        && is(typeof(binaryFun!pred(doesThisEnd.front, withOneOfThese[0]))))
{
    if (doesThisEnd.empty) return 0;
    auto back = doesThisEnd.back;
    foreach (i, Unused; Elements)
    {
        if (binaryFun!pred(back, withOneOfThese[i])) return i + 1;
    }
    return 0;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(!startsWith("abc", 'x', 'n', 'b'));
    assert(startsWith("abc", 'x', 'n', 'a') == 3);
}

// findAdjacent
/**
Advances $(D r) until it finds the first two adjacent elements $(D a),
$(D b) that satisfy $(D pred(a, b)). Performs $(BIGOH r.length)
evaluations of $(D pred). See also $(WEB
sgi.com/tech/stl/adjacent_find.html, STL's adjacent_find).

Example:
----
int[] a = [ 11, 10, 10, 9, 8, 8, 7, 8, 9 ];
auto r = findAdjacent(a);
assert(r == [ 10, 10, 9, 8, 8, 7, 8, 9 ]);
p = findAdjacent!("a < b")(a);
assert(p == [ 7, 8, 9 ]);
----
*/
Range findAdjacent(alias pred = "a == b", Range)(Range r)
    if (isForwardRange!(Range))
{
    auto ahead = r;
    if (!ahead.empty)
    {
        for (ahead.popFront; !ahead.empty; r.popFront, ahead.popFront)
        {
            if (binaryFun!(pred)(r.front, ahead.front)) break;
        }
    }
    return r;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 11, 10, 10, 9, 8, 8, 7, 8, 9 ];
    auto p = findAdjacent(a);
    assert(p == [10, 10, 9, 8, 8, 7, 8, 9 ]);
    p = findAdjacent!("a < b")(a);
    assert(p == [7, 8, 9]);
}

// findAmong
/**
Advances $(D seq) by calling $(D seq.popFront) until either $(D
find!(pred)(choices, seq.front)) is $(D true), or $(D seq) becomes
empty. Performs $(BIGOH seq.length * choices.length) evaluations of
$(D pred). See also $(WEB sgi.com/tech/stl/find_first_of.html, STL's
find_first_of).

Example:
----
int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
int[] b = [ 3, 1, 2 ];
assert(findAmong(a, b) == begin(a) + 2);
assert(findAmong(b, a) == begin(b));
----
*/
Range1 findAmong(alias pred = "a == b", Range1, Range2)(
    Range1 seq, Range2 choices)
    if (isInputRange!(Range1) && isForwardRange!(Range2))
{
    for (; !seq.empty && find!(pred)(choices, seq.front).empty; seq.popFront)
    {
    }
    return seq;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 2, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    assert(findAmong(a, b) == [2, 1, 2, 3, 4, 5 ]);
    assert(findAmong(b, [ 4, 6, 7 ][]).empty);
    assert(findAmong!("a==b")(a, b).length == a.length - 2);
    assert(findAmong!("a==b")(b, [ 4, 6, 7 ][]).empty);
}

// findAmongSorted
/**
Finds the first element $(D x) in $(D seq) that compares equal with
some element $(D y) in $(D choices) (meaning $(D !less(x, y) &&
!less(y, x))). The $(D choices) range is sought by binary
search. Consequently $(D choices) is assumed to be sorted according to
$(D pred), which by default is $(D "a < b"). Performs $(BIGOH
seq.length * log(choices.length)) evaluations of $(D less).

To find the last element of $(D seq) instead of the first, call $(D
findAmongSorted(retro(seq), choices)) and compare the result against
$(D rEnd(seq)). See also $(XREF range, retro).

Example:
----
int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
int[] b = [ 1, 2, 3 ];
assert(findAmongSorted(a, b) == begin(a) + 2);
assert(findAmongSorted(b, a) == end(b));
----
*/
Range1 findAmongSorted(alias less = "a < b", Range1, Range2)(
    Range1 seq, in Range2 choices)
    if (isInputRange!(Range1) && isRandomAccessRange!(Range2))
{
    alias binaryFun!(less) lessFun; // pun not intended
    assert(isSorted!(lessFun)(choices));
    for (; !seq.empty; seq.popFront)
    {
        if (canFindSorted!(lessFun)(choices, seq.front)) break;
    }
    return seq;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 2, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    assert(findAmongSorted(a, b) == [2, 1, 2, 3, 4, 5]);
    assert(findAmongSorted(b, [ 4, 6, 7 ][]).empty);
}

// count
/**
Counts the number of elements $(D x) in $(D r) for which $(D pred(x,
value)) is $(D true). $(D pred) defaults to equality. Performs $(BIGOH
r.length) evaluations of $(D pred).

Example:
----
int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
assert(count(a, 2) == 3);
assert(count!("a > b")(a, 2) == 5);
----
*/

size_t count(alias pred = "a == b", Range, E)(Range r, E value)
    if (isInputRange!(Range))
{
    bool pred2(ElementType!(Range) a) { return binaryFun!(pred)(a, value); }
    return count!(pred2)(r);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count(a, 2) == 3, text(count(a, 2)));
    assert(count!("a > b")(a, 2) == 5, text(count!("a > b")(a, 2)));
}

/**
Counts the number of elements $(D x) in $(D r) for which $(D pred(x))
is $(D true). Performs $(BIGOH r.length) evaluations of $(D pred).

Example:
----
int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
assert(count!("a > 1")(a) == 8);
----
*/
size_t count(alias pred, Range)(Range r) if (isInputRange!(Range))
{
    size_t result;
    foreach (e; r)
    {
        if (unaryFun!(pred)(e)) ++result;
    }
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count!("a == 3")(a) == 2);
}

// equal
/**
Returns $(D true) if and only if the two ranges compare equal element
for element, according to binary predicate $(D pred). The ranges may
have different element types, as long as $(D pred(a, b)) evaluates to
$(D bool) for $(D a) in $(D r1) and $(D b) in $(D r2). Performs
$(BIGOH min(r1.length, r2.length)) evaluations of $(D pred). See also
$(WEB sgi.com/tech/stl/_equal.html, STL's equal).

Example:
----
int[] a = [ 1, 2, 4, 3 ];
assert(!equal(a, a[1..$]));
assert(equal(a, a));

// different types
double[] b = [ 1., 2, 4, 3];
assert(!equal(a, b[1..$]));
assert(equal(a, b));

// predicated: ensure that two vectors are approximately equal
double[] c = [ 1.005, 2, 4, 3];
assert(equal!(approxEqual)(b, c));
----
*/
bool equal(alias pred = "a == b", Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!(Range1) && isInputRange!(Range2)
        && is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    foreach (e1; r1)
    {
        if (r2.empty) return false;
        if (!binaryFun!(pred)(e1, r2.front)) return false;
        r2.popFront;
    }
    return r2.empty;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 3];
    assert(!equal(a, a[1..$]));
    assert(equal(a, a));
    // test with different types
    double[] b = [ 1., 2, 4, 3];
    assert(!equal(a, b[1..$]));
    assert(equal(a, b));

    // predicated
    double[] c = [ 1.005, 2, 4, 3];
    assert(equal!(approxEqual)(b, c));
}

// MinType
template MinType(T...)
{
    static assert(T.length >= 2);
    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
            alias CommonType!(T[0 .. 2]) MinType;
        else static if (mostNegative!(T[1]) < mostNegative!(T[0]))
            alias T[1] MinType;
        else static if (mostNegative!(T[1]) > mostNegative!(T[0]))
            alias T[0] MinType;
        else static if (T[1].max < T[0].max)
            alias T[1] MinType;
        else
            alias T[0] MinType;
    }
    else
    {
        alias MinType!(MinType!(T[0 .. 2]), T[2 .. $]) MinType;
    }
}

// min
/**
Returns the minimum of the passed-in values. The type of the result is
computed by using $(XREF traits, CommonType).
*/
MinType!(T1, T2, T) min(T1, T2, T...)(T1 a, T2 b, T xs)
{
    static if (T.length == 0)
    {
        static if (isIntegral!(T1) && isIntegral!(T2)
                   && (mostNegative!(T1) < 0) != (mostNegative!(T2) < 0))
            static if (mostNegative!(T1) < 0)
                immutable chooseB = b < a && a > 0;
            else
                immutable chooseB = b < a || b < 0;
        else
                immutable chooseB = b < a;
        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return min(min(a, b), xs);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = min(a, b);
    assert(is(typeof(d) == int));
    assert(d == 5);
    auto e = min(a, b, c);
    assert(is(typeof(e) == double));
    assert(e == 2);
    // mixed signedness test
    a = -10;
    uint f = 10;
    static assert(is(typeof(min(a, f)) == int));
    assert(min(a, f) == -10);
}

// MaxType
template MaxType(T...)
{
    static assert(T.length >= 2);
    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
            alias CommonType!(T[0 .. 2]) MaxType;
        else static if (T[1].max > T[0].max)
            alias T[1] MaxType;
        else
            alias T[0] MaxType;
    }
    else
    {
        alias MaxType!(MaxType!(T[0], T[1]), T[2 .. $]) MaxType;
    }
}

// max
/**
Returns the maximum of the passed-in values. The type of the result is
computed by using $(XREF traits, CommonType).

Example:
----
int a = 5;
short b = 6;
double c = 2;
auto d = max(a, b);
assert(is(typeof(d) == int));
assert(d == 6);
auto e = min(a, b, c);
assert(is(typeof(e) == double));
assert(e == 2);
----
*/
MaxType!(T1, T2, T) max(T1, T2, T...)(T1 a, T2 b, T xs)
{
    static if (T.length == 0)
    {
        static if (isIntegral!(T1) && isIntegral!(T2)
                   && (mostNegative!(T1) < 0) != (mostNegative!(T2) < 0))
            static if (mostNegative!(T1) < 0)
                immutable chooseB = b > a || a < 0;
            else
                immutable chooseB = b > a && b > 0;
        else
            immutable chooseB = b > a;
        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return max(max(a, b), xs);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = max(a, b);
    assert(is(typeof(d) == int));
    assert(d == 6);
    auto e = max(a, b, c);
    assert(is(typeof(e) == double));
    assert(e == 6);
    // mixed sign
    a = -5;
    uint f = 5;
    static assert(is(typeof(max(a, f)) == uint));
    assert(max(a, f) == 5);
}

/**
Returns the minimum element of a range together with the number of
occurrences. The function can actually be used for counting the
maximum or any other ordering predicate (that's why $(D maxCount) is
not provided).

Example:
----
int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
// Minimum is 1 and occurs 3 times
assert(minCount(a) == tuple(1, 3));
// Maximum is 4 and occurs 2 times
assert(minCount!("a > b")(a) == tuple(4, 2));
----
 */
Tuple!(ElementType!(Range), size_t)
minCount(alias pred = "a < b", Range)(Range range)
{
    if (range.empty) return typeof(return)();
    auto p = &(range.front());
    size_t occurrences = 1;
    for (range.popFront; !range.empty; range.popFront)
    {
        if (binaryFun!(pred)(*p, range.front)) continue;
        if (binaryFun!(pred)(range.front, *p))
        {
            // change the min
            p = &(range.front());
            occurrences = 1;
        }
        else
        {
            ++occurrences;
        }
    }
    return tuple(*p, occurrences);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
    assert(minCount(a) == tuple(1, 3));
    assert(minCount!("a > b")(a) == tuple(4, 2));
    int[][] b = [ [4], [2, 4], [4], [4] ];
    auto c = minCount!("a[0] < b[0]")(b);
    assert(c == tuple([2, 4], 1), text(c.field[0]));
}

// minPos
/**
Returns the position of the minimum element of forward range $(D
range), i.e. a subrange of $(D range) starting at the position of its
smallest element and with the same ending as $(D range). The function
can actually be used for counting the maximum or any other ordering
predicate (that's why $(D maxPos) is not provided).

Example:
----
int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
// Minimum is 1 and first occurs in position 3
assert(minPos(a) == [ 1, 2, 4, 1, 1, 2 ]);
// Maximum is 4 and first occurs in position 2
assert(minPos!("a > b")(a) == [ 4, 1, 2, 4, 1, 1, 2 ]);
----
 */
Range minPos(alias pred = "a < b", Range)(Range range)
{
    if (range.empty) return range;
    auto result = range;
    for (range.popFront; !range.empty; range.popFront)
    {
        if (binaryFun!(pred)(result.front, range.front)
                || !binaryFun!(pred)(range.front, result.front)) continue;
        // change the min
        result = range;
    }
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
// Minimum is 1 and first occurs in position 3
    assert(minPos(a) == [ 1, 2, 4, 1, 1, 2 ]);
// Maximum is 4 and first occurs in position 5
    assert(minPos!("a > b")(a) == [ 4, 1, 2, 4, 1, 1, 2 ]);
}

// mismatch
/**
Sequentially compares elements in $(D r1) and $(D r2) in lockstep, and
stops at the first mismatch (according to $(D pred), by default
equality). Returns a tuple with the reduced ranges that start with the
two mismatched values. Performs $(BIGOH min(r1.length, r2.length))
evaluations of $(D pred). See also $(WEB
sgi.com/tech/stl/_mismatch.html, STL's mismatch).

Example:
----
int[]    x = [ 1,  5, 2, 7,   4, 3 ];
double[] y = [ 1., 5, 2, 7.3, 4, 8 ];
auto m = mismatch(x, y);
assert(m.field[0] == begin(x) + 3);
assert(m.field[1] == begin(y) + 3);
----
*/

Tuple!(Range1, Range2)
mismatch(alias pred = "a == b", Range1, Range2)(Range1 r1, Range2 r2)
    if (isInputRange!(Range1) && isInputRange!(Range2))
{
    for (; !r1.empty && !r2.empty; r1.popFront(), r2.popFront())
    {
        if (!binaryFun!(pred)(r1.front, r2.front)) break;
    }
    return tuple(r1, r2);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // doc example
    int[]    x = [ 1,  5, 2, 7,   4, 3 ];
    double[] y = [ 1., 5, 2, 7.3, 4, 8 ];
    auto m = mismatch(x, y);
    assert(m.field[0] == [ 7, 4, 3 ]);
    assert(m.field[1] == [ 7.3, 4, 8 ]);

    int[] a = [ 1, 2, 3 ];
    int[] b = [ 1, 2, 4, 5 ];
    auto mm = mismatch(a, b);
    assert(mm.field[0] == [3]);
    assert(mm.field[1] == [4, 5]);
}

// levenshteinDistance
/**
Encodes $(WEB realityinteractive.com/rgrzywinski/archives/000249.html,
edit operations) necessary to transform one sequence into
another. Given sequences $(D s) (source) and $(D t) (target), a
sequence of $(D EditOp) encodes the steps that need to be taken to
convert $(D s) into $(D t). For example, if $(D s = "cat") and $(D
"cars"), the minimal sequence that transforms $(D s) into $(D t) is:
skip two characters, replace 't' with 'r', and insert an 's'. Working
with edit operations is useful in applications such as spell-checkers
(to find the closest word to a given misspelled word), approximate
searches, diff-style programs that compute the difference between
files, efficient encoding of patches, DNA sequence analysis, and
plagiarism detection.
*/

enum EditOp : char
{
    /** Current items are equal; no editing is necessary. */
    none = 'n',
    /** Substitute current item in target with current item in source. */
    substitute = 's',
    /** Insert current item from the source into the target. */
    insert = 'i',
    /** Remove current item from the target. */
    remove = 'r'
}

struct Levenshtein(Range, alias equals, CostType = size_t)
{
    void deletionIncrement(CostType n)
    {
        _deletionIncrement = n;
        InitMatrix();
    }

    void insertionIncrement(CostType n)
    {
        _insertionIncrement = n;
        InitMatrix();
    }

    CostType distance(Range s, Range t)
    {
        auto slen = walkLength(s), tlen = walkLength(t);
        AllocMatrix(slen + 1, tlen + 1);
        foreach (i; 1 .. rows)
        {
            auto sfront = s.front;
            s.popFront();
            auto tt = t;
            foreach (j; 1 .. cols)
            {
                auto cSub = _matrix[i - 1][j - 1]
                    + (equals(sfront, tt.front) ? 0 : _substitutionIncrement);
                tt.popFront();
                auto cIns = _matrix[i][j - 1] + _insertionIncrement;
                auto cDel = _matrix[i - 1][j] + _deletionIncrement;
                switch (min_index(cSub, cIns, cDel)) {
                case 0:
                    _matrix[i][j] = cSub;
                    break;
                case 1:
                    _matrix[i][j] = cIns;
                    break;
                default:
                    _matrix[i][j] = cDel;
                    break;
                }
            }
        }
        return _matrix[slen][tlen];
    }

    EditOp[] path(Range s, Range t)
    {
        distance(s, t);
        return path();
    }

    EditOp[] path()
    {
        EditOp[] result;
        uint i = rows - 1, j = cols - 1;
        // restore the path
        while (i || j) {
            auto cIns = j == 0 ? CostType.max : _matrix[i][j - 1];
            auto cDel = i == 0 ? CostType.max : _matrix[i - 1][j];
            auto cSub = i == 0 || j == 0
                ? CostType.max
                : _matrix[i - 1][j - 1];
            switch (min_index(cSub, cIns, cDel)) {
            case 0:
                result ~= _matrix[i - 1][j - 1] == _matrix[i][j]
                    ? EditOp.none
                    : EditOp.substitute;
                --i;
                --j;
                break;
            case 1:
                result ~= EditOp.insert;
                --j;
                break;
            default:
                result ~= EditOp.remove;
                --i;
                break;
            }
        }
        reverse(result);
        return result;
    }

private:
    CostType _deletionIncrement = 1,
        _insertionIncrement = 1,
        _substitutionIncrement = 1;
    CostType[][] _matrix;
    uint rows, cols;

    void AllocMatrix(uint r, uint c) {
        rows = r;
        cols = c;
        if (!_matrix || _matrix.length < r || _matrix[0].length < c) {
            delete _matrix;
            _matrix = new CostType[][](r, c);
            InitMatrix();
        }
    }

    void InitMatrix() {
        foreach (i, row; _matrix) {
            row[0] = i * _deletionIncrement;
        }
        if (!_matrix) return;
        for (auto i = 0u; i != _matrix[0].length; ++i) {
            _matrix[0][i] = i * _insertionIncrement;
        }
    }

    static uint min_index(CostType i0, CostType i1, CostType i2)
    {
        if (i0 <= i1)
        {
            return i0 <= i2 ? 0 : 2;
        }
        else
        {
            return i1 <= i2 ? 1 : 2;
        }
    }
}

/**
Returns the $(WEB wikipedia.org/wiki/Levenshtein_distance, Levenshtein
distance) between $(D s) and $(D t). The Levenshtein distance computes
the minimal amount of edit operations necessary to transform $(D s)
into $(D t).  Performs $(BIGOH s.length * t.length) evaluations of $(D
equals) and occupies $(BIGOH s.length * t.length) storage.

Example:
----
assert(levenshteinDistance("cat", "rat") == 1);
assert(levenshteinDistance("parks", "spark") == 2);
assert(levenshteinDistance("kitten", "sitting") == 3);
// ignore case
assert(levenshteinDistance!("toupper(a) == toupper(b)")
    ("parks", "SPARK") == 2);
----
*/
size_t levenshteinDistance(alias equals = "a == b", Range1, Range2)
    (Range1 s, Range2 t)
    if (isForwardRange!(Range1) && isForwardRange!(Range2))
{
    Levenshtein!(Range1, binaryFun!(equals), uint) lev;
    return lev.distance(s, t);
}

/**
Returns the Levenshtein distance and the edit path between $(D s) and
$(D t).

Example:
---
string a = "Saturday", b = "Sunday";
auto p = levenshteinDistanceAndPath(a, b);
assert(p.field[0], 3);
assert(equals(p.field[1], "nrrnsnnn"));
---
*/
Tuple!(size_t, EditOp[])
levenshteinDistanceAndPath(alias equals = "a == b", Range1, Range2)
    (Range1 s, Range2 t)
    if (isForwardRange!(Range1) && isForwardRange!(Range2))
{
    Levenshtein!(Range, binaryFun!(equals)) lev;
    auto d = lev.distance(s, t);
    return tuple(d, lev.path);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(levenshteinDistance("a", "a") == 0);
    assert(levenshteinDistance("a", "b") == 1);
    assert(levenshteinDistance("aa", "ab") == 1);
    assert(levenshteinDistance("aa", "abc") == 2);
    assert(levenshteinDistance("Saturday", "Sunday") == 3);
    assert(levenshteinDistance("kitten", "sitting") == 3);
    //lev.deletionIncrement = 2;
    //lev.insertionIncrement = 100;
    string a = "Saturday", b = "Sunday";
    // @@@BUG@@@
    //auto p = levenshteinDistanceAndPath(a, b);
    //writefln(p);
    //assert(cast(string) p.field[1] == "nrrnsnnn", cast(string) p);
}

// copy
/**
Copies the content of $(D source) into $(D target) and returns the
remaining (unfilled) part of $(D target). See also $(WEB
sgi.com/tech/stl/_copy.html, STL's copy). If a behavior similar to
$(WEB sgi.com/tech/stl/copy_backward.html, STL's copy_backward) is
needed, use $(D copy(retro(source), retro(target))). See also $(XREF
range, retro).

Example:
----
int[] a = [ 1, 5 ];
int[] b = [ 9, 8 ];
int[] c = new int[a.length + b.length + 10];
auto d = copy(b, copy(a, c));
assert(c[0 .. a.length + b.length] == a ~ b);
assert(d.length == 10);
----

As long as the target range elements support assignment from source
range elements, different types of ranges are accepted.

Example:
----
float[] a = [ 1.0f, 5 ];
double[] b = new double[a.length];
auto d = copy(a, b);
----

To copy at most $(D n) elements from range $(D a) to range $(D b), you
may want to use $(D copy(take(a, n), b)). To copy those elements from
range $(D a) that satisfy predicate $(D pred) to range $(D b), you may
want to use $(D copy(filter!(pred)(a), b)).

Example:
----
int[] a = [ 1, 5, 8, 9, 10, 1, 2, 0 ];
auto b = new int[a.length];
auto c = copy(filter!("(a & 1) == 1")(a), b);
assert(b[0 .. $ - c.length] == [ 1, 5, 9, 1 ]);
----

 */
Range2 copy(Range1, Range2)(Range1 source, Range2 target)
if (isInputRange!Range1 && isOutputRange!(Range2, ElementType!Range1))
{
    for (; !source.empty; source.popFront())
    {
        put(target, source.front);
    }
    return target;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    {
        int[] a = [ 1, 5 ];
        int[] b = [ 9, 8 ];
        int[] c = new int[a.length + b.length + 10];
        auto d = copy(b, copy(a, c));
        assert(c[0 .. a.length + b.length] == a ~ b);
        assert(d.length == 10);
    }
    {
        int[] a = [ 1, 5 ];
        int[] b = [ 9, 8 ];
        auto e = copy(filter!("a > 1")(a), b);
        assert(b[0] == 5 && e.length == 1);
    }
}

// swapRanges
/**
Swaps all elements of $(D r1) with successive elements in $(D r2).
Returns a tuple containing the remainder portions of $(D r1) and $(D
r2) that were not swapped (one of them will be empty). The ranges may
be of different types but must have the same element type and support
swapping.

Example:
----
int[] a = [ 100, 101, 102, 103 ];
int[] b = [ 0, 1, 2, 3 ];
auto c = swapRanges(a[1 .. 3], b[2 .. 4]);
assert(c.at!(0).empty && c.at!(1).empty);
assert(a == [ 100, 2, 3, 103 ]);
assert(b == [ 0, 1, 101, 102 ]);
----
*/
Tuple!(Range1, Range2)
swapRanges(Range1, Range2)(Range1 r1, Range2 r2)
    if (isInputRange!(Range1) && isInputRange!(Range2)
            && hasSwappableElements!(Range1) && hasSwappableElements!(Range2)
            && is(ElementType!(Range1) == ElementType!(Range2)))
{
    for (; !r1.empty && !r2.empty; r1.popFront, r2.popFront)
    {
        swap(r1.front, r2.front);
    }
    return tuple(r1, r2);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 100, 101, 102, 103 ];
    int[] b = [ 0, 1, 2, 3 ];
    auto c = swapRanges(a[1 .. 3], b[2 .. 4]);
    assert(c.field[0].empty && c.field[1].empty);
    assert(a == [ 100, 2, 3, 103 ]);
    assert(b == [ 0, 1, 101, 102 ]);
}

// reverse
/**
Reverses $(D r) in-place.  Performs $(D r.length) evaluations of $(D
swap). See also $(WEB sgi.com/tech/stl/_reverse.html, STL's reverse).

Example:
----
int[] arr = [ 1, 2, 3 ];
reverse(arr);
assert(arr == [ 3, 2, 1 ]);
----
*/
void reverse(Range)(Range r)
if (isBidirectionalRange!(Range) && hasSwappableElements!(Range))
{
    while (!r.empty)
    {
        swap(r.front, r.back);
        r.popFront;
        if (r.empty) break;
        r.popBack;
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] range = null;
    reverse(range);
    range = [ 1 ];
    reverse(range);
    assert(range == [1]);
    range = [1, 2];
    reverse(range);
    assert(range == [2, 1]);
    range = [1, 2, 3];
    reverse(range);
    assert(range == [3, 2, 1]);
}

// bringToFront
/**
The $(D bringToFront) function has considerable flexibility and
usefulness. It can rotate elements in one buffer left or right, swap
buffers of equal length, and even move elements across disjoint
buffers of different types and different lengths.

$(D bringToFront) takes two ranges $(D front) and $(D back), which may
be of different types. Considering the concatenation of $(D front) and
$(D back) one unified range, $(D bringToFront) rotates that unified
range such that all elements in $(D back) are brought to the beginning
of the unified range. The relative ordering of elements in $(D front)
and $(D back), respectively, remains unchanged.

The simplest use of $(D bringToFront) is for rotating elements in a
buffer. For example:

----
auto arr = [4, 5, 6, 7, 1, 2, 3];
bringToFront(arr[0 .. 4], arr[4 .. $]);
assert(arr == [ 1, 2, 3, 4, 5, 6, 7 ]);
----

The $(D front) range may actually "step over" the $(D back)
range. This is very useful with forward ranges that cannot compute
comfortably right-bounded subranges like $(D arr[0 .. 4]) above. In
the example below, $(D list1) is a right subrange of $(D list).

----
auto list = SList!(int)(4, 5, 6, 7, 1, 2, 3);
auto list1 = list.drop(4);
assert(equal(list1, [ 1, 2, 3 ][]));
bringToFront(list, list1);
assert(equal(list, [ 1, 2, 3, 4, 5, 6, 7 ][]));
----

Elements can be swapped across ranges of different types:

----
auto list = SList!(int)(4, 5, 6, 7);
auto vec = [ 1, 2, 3 ];
bringToFront(list, vec);
assert(equal(list, [ 1, 2, 3, 4 ][]));
assert(equal(vec, [ 5, 6, 7 ][]));
----

Performs $(BIGOH max(front.length, back.length)) evaluations of $(D
swap). See also $(WEB sgi.com/tech/stl/_rotate.html, STL's rotate).

Preconditions:

Either $(D front) and $(D back) are disjoint, or $(D back) is
reachable from $(D front) and $(D front) is not reachable from $(D
back).

Returns:

The number of elements brought to the front, i.e., the length of $(D
back).

Example:

----
auto arr = [4, 5, 6, 7, 1, 2, 3];
auto p = rotate(arr, begin(arr) + 4);
assert(p - begin(arr) == 3);
assert(arr == [ 1, 2, 3, 4, 5, 6, 7 ]);
----
*/
size_t bringToFront(Range1, Range2)(Range1 front, Range2 back)
    if (isForwardRange!Range1 && isForwardRange!Range2)
{
    enum bool sameHeadExists = is(typeof(front.sameHead(back)));
    size_t result;
    for (;;)
    {
        if (back.empty || front.empty) return result;
        static if (sameHeadExists)
            if (front.sameHead(back)) return result;

        auto front2 = front.save;
        auto back2 = back.save;

        for (;;)
        {
            // make progress for this pass through the loop
            auto t1 = moveFront(front2), t2 = moveFront(back2);
            front2.front = move(t2);
            back2.front = move(t1);

            front2.popFront;
            back2.popFront;
            ++result;
            bool leftShorter = front2.empty;
            static if (sameHeadExists)
                if (!leftShorter)
                    leftShorter = front2.sameHead(back);
            if (leftShorter)
            {
                // Left side was shorter than the right one
                static if (is(Range1 == Range2))
                {
                    front = back;
                    back = back2;
                    break;
                }
                else
                {
                    return result + bringToFront(back, back2);
                }
            }
            if (back2.empty)
            {
                // Right side was shorter than the left one
                front = front2;
                break;
                ///*return*/ bringToFront(front2, back);
                //return front2;
            }
        }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // // doc example
    int[] arr = [4, 5, 6, 7, 1, 2, 3];
    // auto p = rotate(arr, arr.ptr + 4);
    auto p = bringToFront(arr[0 .. 4], arr[4 .. $]);
    //assert(p - arr.ptr == 3);
    assert(arr == [ 1, 2, 3, 4, 5, 6, 7 ], text(arr));
    //assert(p is arr[3 .. $], text(p));

    // // The signature taking range and mid
    arr[] = [4, 5, 6, 7, 1, 2, 3];
    // p = rotate(arr, arr.ptr + 4);
    p = bringToFront(arr[0 .. 4], arr[4 .. $]);
    //assert(p - arr.ptr == 3);
    //assert(p is arr[3 .. $]);
    assert(arr == [ 1, 2, 3, 4, 5, 6, 7 ]);

    // // a more elaborate test
    auto rnd = Random(unpredictableSeed);
    int[] a = new int[uniform(100, 200, rnd)];
    int[] b = new int[uniform(100, 200, rnd)];
    foreach (ref e; a) e = uniform(-100, 100, rnd);
    foreach (ref e; b) e = uniform(-100, 100, rnd);
    int[] c = a ~ b;
    // writeln("a= ", a);
    // writeln("b= ", b);
    auto n = bringToFront(c[0 .. a.length], c[a.length .. $]);
    //writeln("c= ", c);
    // assert(n == c.ptr + b.length);
    //assert(n is c[b.length .. $]);
    assert(c == b ~ a, text(c));
}

// SwapStrategy
/**
Defines the swapping strategy for algorithms that need to swap
elements in a range (such as partition and sort). The strategy
concerns the swapping of elements that are not the core concern of the
algorithm. For example, consider an algorithm that sorts $(D [ "abc",
"b", "aBc" ]) according to $(D toupper(a) < toupper(b)). That
algorithm might choose to swap the two equivalent strings $(D "abc")
and $(D "aBc"). That does not affect the sorting since both $(D [
"abc", "aBc", "b" ]) and $(D [ "aBc", "abc", "b" ]) are valid
outcomes.

Some situations require that the algorithm must NOT ever change the
relative ordering of equivalent elements (in the example above, only
$(D [ "abc", "aBc", "b" ]) would be the correct result). Such
algorithms are called $(B stable). If the ordering algorithm may swap
equivalent elements discretionarily, the ordering is called $(B
unstable).

Yet another class of algorithms may choose an intermediate tradeoff by
being stable only on a well-defined subrange of the range. There is no
established terminology for such behavior; this library calls it $(B
semistable).

Generally, the $(D stable) ordering strategy may be more costly in
time and/or space than the other two because it imposes additional
constraints. Similarly, $(D semistable) may be costlier than $(D
unstable). As (semi-)stability is not needed very often, the ordering
algorithms in this module parameterized by $(D SwapStrategy) all
choose $(D SwapStrategy.unstable) as the default.
*/

enum SwapStrategy
{
    /**
       Allows freely swapping of elements as long as the output
       satisfies the algorithm's requirements.
    */
    unstable,
    /**
       In algorithms partitioning ranges in two, preserve relative
       ordering of elements only to the left of the partition point.
    */
    semistable,
    /**
       Preserve the relative ordering of elements to the largest
       extent allowed by the algorithm's requirements.
    */
    stable,
}

/**
Eliminates elements at given offsets from $(D range) and returns the
shortened range. In the simplest call, one element is removed.

----
int[] a = [ 3, 5, 7, 8 ];
assert(remove(a, 1) == [ 3, 7, 8 ]);
assert(a == [ 3, 7, 8, 8 ]);
----

In the case above the element at offset $(D 1) is removed and $(D
remove) returns the range smaller by one element. The original array
has remained of the same length because all functions in $(D
std.algorithm) only change $(I content), not $(I topology). The value
$(D 8) is repeated because $(XREF algorithm, move) was invoked to move
elements around and on integers $(D move) simply copies the source to
the destination. To replace $(D a) with the effect of the removal,
simply assign $(D a = remove(a, 1)). The slice will be rebound to the
shorter array and the operation completes with maximal efficiency.

Multiple indices can be passed into $(D remove). In that case,
elements at the respective indices are all removed. The indices must
be passed in increasing order, otherwise an exception occurs.

----
int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
assert(remove(a, 1, 3, 5) ==
    [ 0, 2, 4, 6, 7, 8, 9, 10 ]);
----

(Note how all indices refer to slots in the $(I original) array, not
in the array as it is being progressively shortened.) Finally, any
combination of integral offsets and tuples composed of two integral
offsets can be passed in.

----
int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
assert(remove(a, 1, tuple(3, 5), 9) == [ 0, 2, 6, 7, 8, 10 ]);
----

In this case, the slots at positions 1, 3, 4, and 9 are removed from
the array. The tuple passes in a range closed to the left and open to
the right (consistent with built-in slices), e.g. $(D tuple(3, 5))
means indices $(D 3) and $(D 4) but not $(D 5).

If the need is to remove some elements in the range but the order of
the remaining elements does not have to be preserved, you may want to
pass $(D SwapStrategy.unstable) to $(D remove).

----
int[] a = [ 0, 1, 2, 3 ];
assert(remove!(SwapStrategy.unstable)(a, 1) == [ 0, 3, 2 ]);
----

In the case above, the element at slot $(D 1) is removed, but replaced
with the last element of the range. Taking advantage of the relaxation
of the stability requirement, $(D remove) moved elements from the end
of the array over the slots to be removed. This way there is less data
movement to be done which improves the execution time of the function.

The function $(D remove) works on any forward range. The moving
strategy is (listed from fastest to slowest): $(UL $(LI If $(D s ==
SwapStrategy.unstable && isRandomAccessRange!Range &&
hasLength!Range), then elements are moved from the end of the range
into the slots to be filled. In this case, the absolute minimum of
moves is performed.)  $(LI Otherwise, if $(D s ==
SwapStrategy.unstable && isBidirectionalRange!Range &&
hasLength!Range), then elements are still moved from the end of the
range, but time is spent on advancing between slots by repeated calls
to $(D range.popFront).)  $(LI Otherwise, elements are moved incrementally
towards the front of $(D range); a given element is never moved
several times, but more elements are moved than in the previous
cases.))
 */
Range remove
(SwapStrategy s = SwapStrategy.stable, Range, Offset...)
(Range range, Offset offset)
if (isBidirectionalRange!Range && hasLength!Range && s != SwapStrategy.stable)
{
    enum bool tupleLeft = is(typeof(offset[0].field[0]))
        && is(typeof(offset[0].field[1]));
    enum bool tupleRight = is(typeof(offset[$ - 1].field[0]))
        && is(typeof(offset[$ - 1].field[1]));
    static if (!tupleLeft)
    {
        alias offset[0] lStart;
        auto lEnd = lStart + 1;
    }
    else
    {
        auto lStart = offset[0].field[0];
        auto lEnd = offset[0].field[1];
    }
    static if (!tupleRight)
    {
        alias offset[$ - 1] rStart;
        auto rEnd = rStart + 1;
    }
    else
    {
        auto rStart = offset[$ - 1].field[0];
        auto rEnd = offset[$ - 1].field[1];
    }
    // Begin. Test first to see if we need to remove the rightmost
    // element(s) in the range. In that case, life is simple - chop
    // and recurse.
    if (rEnd == range.length)
    {
        // must remove the last elements of the range
        range.popBackN(rEnd - rStart);
        static if (Offset.length > 1)
        {
            return .remove!(s, Range, Offset[0 .. $ - 1])
                (range, offset[0 .. $ - 1]);
        }
        else
        {
            return range;
        }
    }

    // Ok, there are "live" elements at the end of the range
    auto t = range;
    auto lDelta = lEnd - lStart, rDelta = rEnd - rStart;
    auto rid = min(lDelta, rDelta);
    foreach (i; 0 .. rid)
    {
        move(range.back, t.front);
        range.popBack;
        t.popFront;
    }
    if (rEnd - rStart == lEnd - lStart)
    {
        // We got rid of both left and right
        static if (Offset.length > 2)
        {
            return .remove!(s, Range, Offset[1 .. $ - 1])
                (range, offset[1 .. $ - 1]);
        }
        else
        {
            return range;
        }
    }
    else if (rEnd - rStart < lEnd - lStart)
    {
        // We got rid of the entire right subrange
        static if (Offset.length > 2)
        {
            return .remove!(s, Range)
                (range, tuple(lStart + rid, lEnd),
                        offset[1 .. $ - 1]);
        }
        else
        {
            auto tmp = tuple(lStart + rid, lEnd);
            return .remove!(s, Range, typeof(tmp))
                (range, tmp);
        }
    }
    else
    {
        // We got rid of the entire left subrange
        static if (Offset.length > 2)
        {
            return .remove!(s, Range)
                (range, offset[1 .. $ - 1],
                        tuple(rStart, lEnd - rid));
        }
        else
        {
            auto tmp = tuple(rStart, lEnd - rid);
            return .remove!(s, Range, typeof(tmp))
                (range, tmp);
        }
    }
}

// Ditto
Range remove
(SwapStrategy s = SwapStrategy.stable, Range, Offset...)
(Range range, Offset offset)
if (isForwardRange!Range && !isBidirectionalRange!Range
        || !hasLength!Range || s == SwapStrategy.stable)
{
    auto result = range;
    auto src = range, tgt = range;
    size_t pos;
    foreach (i; offset)
    {
        static if (is(typeof(i.field[0])) && is(typeof(i.field[1])))
        {
            auto from = i.field[0], delta = i.field[1] - i.field[0];
        }
        else
        {
            auto from = i;
            enum delta = 1;
        }
        assert(pos <= from);
        for (; pos < from; ++pos, src.popFront, tgt.popFront)
        {
            move(src.front, tgt.front);
        }
        // now skip source to the "to" position
        src.popFrontN(delta);
        pos += delta;
        foreach (j; 0 .. delta) result.popBack;
    }
    // leftover move
    moveAll(src, tgt);
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1) ==
        [ 0, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.unstable)(a, 0, 10) ==
            [ 9, 1, 2, 3, 4, 5, 6, 7, 8 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.unstable)(a, 0, tuple(9, 11)) ==
            [ 8, 1, 2, 3, 4, 5, 6, 7 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, 5));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, 5) ==
        [ 0, 2, 3, 4, 6, 7, 8, 9, 10 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, 3, 5));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, 3, 5)
            == [ 0, 2, 4, 6, 7, 8, 9, 10]);
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, tuple(3, 5)));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, tuple(3, 5))
            == [ 0, 2, 5, 6, 7, 8, 9, 10]);
}

/**
Reduces the length of the bidirectional range $(D range) by only
keeping elements that satisfy $(D pred). If $(s =
SwapStrategy.unstable), elements are moved from the right end of the
range over the elements to eliminate. If $(D s = SwapStrategy.stable)
(the default), elements are moved progressively to front such that
their relative order is preserved. Returns the tail portion of the
range that was moved.

Example:
----
int[] a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
assert(a[0 .. $ - remove!("a == 2")(a).length] == [ 1, 3, 3, 4, 5, 5, 6 ]);
----
 */
Range remove(alias pred, SwapStrategy s = SwapStrategy.stable, Range)
(Range range)
if (isBidirectionalRange!Range)
{
    auto result = range;
    static if (s != SwapStrategy.stable)
    {
        for (;!range.empty;)
        {
            if (!unaryFun!(pred)(range.front))
            {
                range.popFront;
                continue;
            }
            move(range.back, range.front);
            range.popBack;
            result.popBack;
        }
    }
    else
    {
        auto tgt = range;
        for (; !range.empty; range.popFront)
        {
            if (unaryFun!(pred)(range.front))
            {
                // yank this guy
                result.popBack;
                continue;
            }
            // keep this guy
            move(range.front, tgt.front);
            tgt.popFront;
        }
    }
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
    assert(remove!("a == 2", SwapStrategy.unstable)(a) ==
            [ 1, 6, 3, 5, 3, 4, 5 ]);
    a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
    //writeln(remove!("a != 2", SwapStrategy.stable)(a));
    assert(remove!("a == 2", SwapStrategy.stable)(a) ==
            [ 1, 3, 3, 4, 5, 5, 6 ]);
}

// eliminate
/* *
Reduces $(D r) by overwriting all elements $(D x) that satisfy $(D
pred(x)). Returns the reduced range.

Example:
----
int[] arr = [ 1, 2, 3, 4, 5 ];
// eliminate even elements
auto r = eliminate!("(a & 1) == 0")(arr);
assert(r == [ 1, 3, 5 ]);
assert(arr == [ 1, 3, 5, 4, 5 ]);
----
*/
// Range eliminate(alias pred,
//                 SwapStrategy ss = SwapStrategy.unstable,
//                 alias move = .move,
//                 Range)(Range r)
// {
//     alias Iterator!(Range) It;
//     static void assignIter(It a, It b) { move(*b, *a); }
//     return range(begin(r), partitionold!(not!(pred), ss, assignIter, Range)(r));
// }

// unittest
// {
//     int[] arr = [ 1, 2, 3, 4, 5 ];
// // eliminate even elements
//     auto r = eliminate!("(a & 1) == 0")(arr);
//     assert(find!("(a & 1) == 0")(r).empty);
// }

/* *
Reduces $(D r) by overwriting all elements $(D x) that satisfy $(D
pred(x, v)). Returns the reduced range.

Example:
----
int[] arr = [ 1, 2, 3, 2, 4, 5, 2 ];
// keep elements different from 2
auto r = eliminate(arr, 2);
assert(r == [ 1, 3, 4, 5 ]);
assert(arr == [ 1, 3, 4, 5, 4, 5, 2  ]);
----
*/
// Range eliminate(alias pred = "a == b",
//                 SwapStrategy ss = SwapStrategy.semistable,
//                 Range, Value)(Range r, Value v)
// {
//     alias Iterator!(Range) It;
//     bool comp(typeof(*It) a) { return !binaryFun!(pred)(a, v); }
//     static void assignIterB(It a, It b) { *a = *b; }
//     return range(begin(r),
//             partitionold!(comp,
//                     ss, assignIterB, Range)(r));
// }

// unittest
// {
//     int[] arr = [ 1, 2, 3, 2, 4, 5, 2 ];
// // keep elements different from 2
//     auto r = eliminate(arr, 2);
//     assert(r == [ 1, 3, 4, 5 ]);
//     assert(arr == [ 1, 3, 4, 5, 4, 5, 2  ]);
// }

// partition
/**
Partitions a range in two using $(D pred) as a
predicate. Specifically, reorders the range $(D r = [left,
right$(RPAREN)) using $(D swap) such that all elements $(D i) for
which $(D pred(i)) is $(D true) come before all elements $(D j) for
which $(D pred(j)) returns $(D false).

Performs $(BIGOH r.length) (if unstable or semistable) or $(BIGOH
r.length * log(r.length)) (if stable) evaluations of $(D less) and $(D
swap). The unstable version computes the minimum possible evaluations
of $(D swap) (roughly half of those performed by the semistable
version).

See also STL's $(WEB sgi.com/tech/stl/_partition.html, partition) and
$(WEB sgi.com/tech/stl/stable_partition.html, stable_partition).

Returns:

The right part of $(D r) after partitioning.

If $(D ss == SwapStrategy.stable), $(D partition) preserves the
relative ordering of all elements $(D a), $(D b) in $(D r) for which
$(D pred(a) == pred(b)). If $(D ss == SwapStrategy.semistable), $(D
partition) preserves the relative ordering of all elements $(D a), $(D
b) in $(D begin(r) .. p) for which $(D pred(a) == pred(b)).

Example:

----
auto Arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
auto arr = Arr.dup;
static bool even(int a) { return (a & 1) == 0; }
// Partition a such that even numbers come first
auto p = partition!(even)(arr);
// Now arr is separated in evens and odds.
// Numbers may have become shuffled due to instability
assert(p == arr.ptr + 5);
assert(count!(even)(range(begin(arr), p)) == p - begin(arr));
assert(find!(even)(range(p, end(arr))) == end(arr));

// Can also specify the predicate as a string.
// Use 'a' as the predicate argument name
arr[] = Arr[];
p = partition!(q{(a & 1) == 0})(arr);
assert(p == arr.ptr + 5);

// Now for a stable partition:
arr[] = Arr[];
p = partition!(q{(a & 1) == 0}, SwapStrategy.stable)(arr);
// Now arr is [2 4 6 8 10 1 3 5 7 9], and p points to 1
assert(arr == [2, 4, 6, 8, 10, 1, 3, 5, 7, 9] && p == arr.ptr + 5);

// In case the predicate needs to hold its own state, use a delegate:
arr[] = Arr[];
int x = 3;
// Put stuff greater than 3 on the left
bool fun(int a) { return a > x; }
p = partition!(fun, SwapStrategy.semistable)(arr);
// Now arr is [4 5 6 7 8 9 10 2 3 1] and p points to 2
assert(arr == [4, 5, 6, 7, 8, 9, 10, 2, 3, 1] && p == arr.ptr + 7);
----
*/
Range partition(alias predicate,
        SwapStrategy ss = SwapStrategy.unstable, Range)(Range r)
    if ((ss == SwapStrategy.stable && isRandomAccessRange!(Range))
            || (ss != SwapStrategy.stable && isForwardRange!(Range)))
{
    alias unaryFun!(predicate) pred;
    if (r.empty) return r;
    static if (ss == SwapStrategy.stable)
    {
        if (r.length == 1)
        {
            if (pred(r.front)) r.popFront;
            return r;
        }
        const middle = r.length / 2;
        alias .partition!(pred, ss, Range) recurse;
        auto lower = recurse(r[0 .. middle]);
        auto upper = recurse(r[middle .. $]);
        bringToFront(lower, r[middle .. r.length - upper.length]);
        return r[r.length - lower.length - upper.length .. r.length];
    }
    else static if (ss == SwapStrategy.semistable)
    {
        for (; !r.empty; r.popFront)
        {
            // skip the initial portion of "correct" elements
            if (pred(r.front)) continue;
            // hit the first "bad" element
            auto result = r;
            for (r.popFront; !r.empty; r.popFront)
            {
                if (!pred(r.front)) continue;
                swap(result.front, r.front);
                result.popFront;
            }
            return result;
        }
        return r;
    }
    else // ss == SwapStrategy.unstable
    {
        // Inspired from www.stepanovpapers.com/PAM3-partition_notes.pdf,
        // section "Bidirectional Partition Algorithm (Hoare)"
        auto result = r;
        for (;;)
        {
            for (;;)
            {
                if (r.empty) return result;
                if (!pred(r.front)) break;
                r.popFront;
                result.popFront;
            }
            // found the left bound
            assert(!r.empty);
            for (;;)
            {
                if (pred(r.back)) break;
                r.popBack;
                if (r.empty) return result;
            }
            // found the right bound, swap & make progress
            swap(r.front, r.back);
            r.popFront;
            result.popFront;
            r.popBack;
        }
    }
}

unittest // partitionold
{
    auto Arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    auto arr = Arr.dup;
    static bool even(int a) { return (a & 1) == 0; }
// Partitionold a such that even numbers come first
    //auto p = partitionold!(even)(arr);
    auto p1 = partition!(even)(arr);
// Now arr is separated in evens and odds.
    //assert(p == arr.ptr + 5);
    assert(p1 == arr[5 .. $], text(p1));
    //assert(count!(even)(range(begin(arr), p)) == p - begin(arr));
    assert(count!(even)(arr[0 .. $ - p1.length]) == p1.length);
    assert(find!(even)(p1).empty);
// Notice that numbers have become shuffled due to instability
    arr[] = Arr[];
// Can also specify the predicate as a string.
// Use 'a' as the predicate argument name
    p1 = partition!(q{(a & 1) == 0})(arr);
    assert(p1 == arr[5 .. $]);
// Same result as above. Now for a stable partitionold:
    arr[] = Arr[];
    p1 = partition!(q{(a & 1) == 0}, SwapStrategy.stable)(arr);
// Now arr is [2 4 6 8 10 1 3 5 7 9], and p points to 1
    assert(arr == [2, 4, 6, 8, 10, 1, 3, 5, 7, 9], text(arr));
    assert(p1 == arr[5 .. $], text(p1));
// In case the predicate needs to hold its own state, use a delegate:
    arr[] = Arr[];
    int x = 3;
// Put stuff greater than 3 on the left
    bool fun(int a) { return a > x; }
    p1 = partition!(fun, SwapStrategy.semistable)(arr);
// Now arr is [4 5 6 7 8 9 10 2 3 1] and p points to 2
    assert(arr == [4, 5, 6, 7, 8, 9, 10, 2, 3, 1] && p1 == arr[7 .. $]);

    // test with random data
    auto a = rndstuff!(int)();
    partition!(even)(a);
    assert(isPartitioned!(even)(a));
    auto b = rndstuff!(string);
    partition!(`a.length < 5`)(b);
    assert(isPartitioned!(`a.length < 5`)(b));
}

/**
Returns $(D true) if $(D r) is partitioned according to predicate $(D
pred).

Example:
----
int[] r = [ 1, 3, 5, 7, 8, 2, 4, ];
assert(isPartitioned!("a & 1")(r));
----
 */
bool isPartitioned(alias pred, Range)(Range r)
    if (isForwardRange!(Range))
{
    for (; !r.empty; r.popFront)
    {
        if (unaryFun!(pred)(r.front)) continue;
        for (r.popFront; !r.empty; r.popFront)
        {
            if (unaryFun!(pred)(r.front)) return false;
        }
        break;
    }
    return true;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] r = [ 1, 3, 5, 7, 8, 2, 4, ];
    assert(isPartitioned!("a & 1")(r));
}

// topN
/**
Reorders the range $(D r) using $(D swap) such that $(D r[nth]) refers
to the element that would fall there if the range were fully
sorted. In addition, it also partitions $(D r) such that all elements
$(D e1) from $(D r[0]) to $(D r[nth]) satisfy $(D !less(r[nth], e1)),
and all elements $(D e2) from $(D r[nth]) to $(D r[r.length]) satisfy
$(D !less(e2, r[nth])). Effectively, it finds the nth smallest
(according to $(D less)) elements in $(D r). Performs $(BIGOH
r.length) (if unstable) or $(BIGOH r.length * log(r.length)) (if
stable) evaluations of $(D less) and $(D swap). See also $(WEB
sgi.com/tech/stl/nth_element.html, STL's nth_element).

Example:

----
int[] v = [ 25, 7, 9, 2, 0, 5, 21 ];
auto n = 4;
topN!(less)(v, n);
assert(v[n] == 9);
// Equivalent form:
topN!("a < b")(v, n);
assert(v[n] == 9);
----

BUGS:

Stable topN has not been implemented yet.
*/
void topN(alias less = "a < b",
        SwapStrategy ss = SwapStrategy.unstable,
        Range)(Range r, size_t nth)
    if (isRandomAccessRange!(Range) && hasLength!Range)
{
    static assert(ss == SwapStrategy.unstable,
            "Stable topN not yet implemented");
    while (r.length > nth)
    {
        auto pivot = r.length / 2;
        swap(r[pivot], r.back);
        assert(!binaryFun!(less)(r.back, r.back));
        bool pred(ElementType!(Range) a)
        {
            return binaryFun!(less)(a, r.back);
        }
        auto right = partition!(pred, ss)(r);
        assert(right.length >= 1);
        swap(right.front, r.back);
        pivot = r.length - right.length;
        if (pivot == nth)
        {
            return;
        }
        if (pivot < nth)
        {
            ++pivot;
            r = r[pivot .. $];
            nth -= pivot;
        }
        else
        {
            assert(pivot < r.length);
            r = r[0 .. pivot];
        }
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    //scope(failure) writeln(stderr, "Failure testing algorithm");
    //auto v = ([ 25, 7, 9, 2, 0, 5, 21 ]).dup;
    int[] v = [ 7, 6, 5, 4, 3, 2, 1, 0 ];
    auto n = 3;
    topN!("a < b")(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 3;
    topN(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 1;
    topN(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = v.length - 1;
    topN(v, n);
    assert(v[n] == 7);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 0;
    topN(v, n);
    assert(v[n] == 1);

    double[][] v1 = [[-10, -5], [-10, -3], [-10, -5], [-10, -4],
            [-10, -5], [-9, -5], [-9, -3], [-9, -5],];

    // double[][] v1 = [ [-10, -5], [-10, -4], [-9, -5], [-9, -5],
    //         [-10, -5], [-10, -3], [-10, -5], [-9, -3],];
    double[]*[] idx = [ &v1[0], &v1[1], &v1[2], &v1[3], &v1[4], &v1[5], &v1[6],
            &v1[7], ];

    auto mid = v1.length / 2;
    topN!((a, b){ return (*a)[1] < (*b)[1]; })(idx, mid);
    foreach (e; idx[0 .. mid]) assert((*e)[1] <= (*idx[mid])[1]);
    foreach (e; idx[mid .. $]) assert((*e)[1] >= (*idx[mid])[1]);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = new int[uniform(1, 10000)];
        foreach (ref e; a) e = uniform(-1000, 1000);
    auto k = uniform(0, a.length);
    topN(a, k);
    if (k > 0)
    {
        auto left = reduce!max(a[0 .. k]);
        assert(left <= a[k]);
    }
    if (k + 1 < a.length)
    {
        auto right = reduce!min(a[k + 1 .. $]);
        assert(right >= a[k]);
    }
}

/**
Stores the smallest elements of the two ranges in the left-hand range.
 */
void topN(alias less = "a < b",
        SwapStrategy ss = SwapStrategy.unstable,
        Range1, Range2)(Range1 r1, Range2 r2)
    if (isRandomAccessRange!(Range1) && hasLength!Range1 &&
            isInputRange!Range2 && is(ElementType!Range1 == ElementType!Range2))
{
    static assert(ss == SwapStrategy.unstable,
            "Stable topN not yet implemented");
    auto heap = BinaryHeap!Range1(r1);
    for (; !r2.empty; r2.popFront)
    {
        heap.conditionalInsert(r2.front);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 5, 7, 2, 6, 7 ];
    int[] b = [ 2, 1, 5, 6, 7, 3, 0 ];
    topN(a, b);
    sort(a);
    sort(b);
    assert(a == [0, 1, 2, 2, 3]);
}

// sort
/**
Sorts a random-access range according to predicate $(D less). Performs
$(BIGOH r.length * log(r.length)) (if unstable) or $(BIGOH r.length *
log(r.length) * log(r.length)) (if stable) evaluations of $(D less)
and $(D swap). See also STL's $(WEB sgi.com/tech/stl/_sort.html, sort)
and $(WEB sgi.com/tech/stl/stable_sort.html, stable_sort).

Example:

----
int[] array = [ 1, 2, 3, 4 ];
// sort in descending order
sort!("a > b")(array);
assert(array == [ 4, 3, 2, 1 ]);
// sort in ascending order
sort(array);
assert(array == [ 1, 2, 3, 4 ]);
// sort with a delegate
bool myComp(int x, int y) { return x > y; }
sort!(myComp)(array);
assert(array == [ 4, 3, 2, 1 ]);
// Showcase stable sorting
string[] words = [ "aBc", "a", "abc", "b", "ABC", "c" ];
sort!("toupper(a) < toupper(b)", SwapStrategy.stable)(words);
assert(words == [ "a", "aBc", "abc", "ABC", "b", "c" ]);
----
*/

void sort(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable,
        Range)(Range r)
{
    alias binaryFun!(less) lessFun;
    static if (is(typeof(lessFun(r.front, r.front)) == bool))
    {
        sortImpl!(lessFun, ss)(r);
        assert(isSorted!(lessFun)(r));
    }
    else
    {
        static assert(false, "Invalid predicate passed to sort: "~less);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // sort using delegate
    int a[] = new int[100];
    auto rnd = Random(unpredictableSeed);
    foreach (ref e; a) {
        e = uniform(-100, 100, rnd);
    }

    int i = 0;
    bool greater2(int a, int b) { return a + i > b + i; }
    bool delegate(int, int) greater = &greater2;
    sort!(greater)(a);
    assert(isSorted!(greater)(a));

    // sort using string
    sort!("a < b")(a);
    assert(isSorted!("a < b")(a));

    // sort using function; all elements equal
    foreach (ref e; a) {
        e = 5;
    }
    static bool less(int a, int b) { return a < b; }
    sort!(less)(a);
    assert(isSorted!(less)(a));

    string[] words = [ "aBc", "a", "abc", "b", "ABC", "c" ];
    bool lessi(string a, string b) { return toupper(a) < toupper(b); }
    sort!(lessi, SwapStrategy.stable)(words);
    assert(words == [ "a", "aBc", "abc", "ABC", "b", "c" ]);

    // sort using ternary predicate
    //sort!("b - a")(a);
    //assert(isSorted!(less)(a));

    a = rndstuff!(int);
    sort(a);
    assert(isSorted(a));
    auto b = rndstuff!(string);
    sort!("tolower(a) < tolower(b)")(b);
    assert(isSorted!("toupper(a) < toupper(b)")(b));
}

// @@@BUG1904
/*private*/
size_t getPivot(alias less, Range)(Range r)
{
    return r.length / 2;
}

// @@@BUG1904
/*private*/
void optimisticInsertionSort(alias less, Range)(Range r)
{
    if (r.length <= 1) return;
    for (auto i = 1; i != r.length; )
    {
        // move to the left to find the insertion point
        auto p = i - 1;
        for (;;)
        {
            if (!less(r[i], r[p]))
            {
                ++p;
                break;
            }
            if (p == 0) break;
            --p;
        }
        if (i == p)
        {
            // already in place
            ++i;
            continue;
        }
        assert(less(r[i], r[p]));
        // move up to see how many we can insert
        auto iOld = i, iPrev = i;
        ++i;
        // The code commented below has a darn bug in it.
        // while (i != r.length && less(r[i], r[p]) && !less(r[i], r[iPrev]))
        // {
        //     ++i;
        //     ++iPrev;
        // }
        // do the insertion
        //assert(isSorted!(less)(r[0 .. iOld]));
        //assert(isSorted!(less)(r[iOld .. i]));
        //assert(less(r[i - 1], r[p]));
        //assert(p == 0 || !less(r[i - 1], r[p - 1]));
        bringToFront(r[p .. iOld], r[iOld .. i]);
        //assert(isSorted!(less)(r[0 .. i]));
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto rnd = Random(1);
    int a[] = new int[uniform(100, 200, rnd)];
    foreach (ref e; a) {
        e = uniform(-100, 100, rnd);
    }

    optimisticInsertionSort!(binaryFun!("a < b"), int[])(a);
    assert(isSorted(a));
}

// @@@BUG1904
/*private*/
void sortImpl(alias less, SwapStrategy ss, Range)(Range r)
{
    alias ElementType!(Range) Elem;
    enum uint optimisticInsertionSortGetsBetter = 1;
    static assert(optimisticInsertionSortGetsBetter >= 1);

    while (r.length > optimisticInsertionSortGetsBetter)
    {
        const pivotIdx = getPivot!(less)(r);
        // partition
        static if (ss == SwapStrategy.unstable)
        {
            // partition
            swap(r[pivotIdx], r.back);
            bool pred(ElementType!(Range) a)
            {
                return less(a, r.back);
            }
            auto right = partition!(pred, ss)(r);
            swap(right.front, r.back);
            // done with partitioning
            if (r.length == right.length)
            {
                // worst case: *b <= everything (also pivot <= everything)
                // avoid quadratic behavior
                do r.popFront; while (!r.empty && !less(right.front, r.front));
            }
            else
            {
                auto left = r[0 .. r.length - right.length];
                right.popFront; // no need to consider right.front,
                                // it's in the proper place already
                if (right.length > left.length)
                {
                    swap(left, right);
                }
                .sortImpl!(less, ss, Range)(right);
                r = left;
            }
        }
        else // handle semistable and stable the same
        {
            auto pivot = r[pivotIdx];
            static assert(ss != SwapStrategy.semistable);
            bool pred(Elem a) { return less(a, pivot); }
            auto right = partition!(pred, ss)(r);
            if (r.length == right.length)
            {
                // bad, bad pivot. pivot <= everything
                // find the first occurrence of the pivot
                bool pred1(Elem a) { return !less(pivot, a); }
                //auto firstPivotPos = find!(pred1)(r).ptr;
                auto pivotSpan = find!(pred1)(r);
                assert(!pivotSpan.empty);
                assert(!less(pivotSpan.front, pivot)
                       && !less(pivot, pivotSpan.front));
                // find the last occurrence of the pivot
                bool pred2(Elem a) { return less(pivot, a); }
                //auto lastPivotPos = find!(pred2)(pivotsRight[1 .. $]).ptr;
                auto pivotRunLen = find!(pred2)(pivotSpan[1 .. $]).length;
                pivotSpan = pivotSpan[0 .. pivotRunLen + 1];
                // now rotate firstPivotPos..lastPivotPos to the front
                bringToFront(r, pivotSpan);
                r = r[pivotSpan.length .. $];
            }
            else
            {
                .sortImpl!(less, ss, Range)(r[0 .. r.length - right.length]);
                r = right;
            }
        }
    }
    // residual sort
    static if (optimisticInsertionSortGetsBetter > 1)
    {
        optimisticInsertionSort!(less, Range)(r);
    }
}

// schwartzSort
/**
Sorts a range using an algorithm akin to the $(WEB
wikipedia.org/wiki/Schwartzian_transform, Schwartzian transform), also
known as the decorate-sort-undecorate pattern in Python and Lisp. (Not
to be confused with $(WEB youtube.com/watch?v=S25Zf8svHZQ, the other
Schwartz).) This function is helpful when the sort comparison includes
an expensive computation. The complexity is the same as that of the
corresponding $(D sort), but $(D schwartzSort) evaluates $(D
transform) only $(D r.length) times (less than half when compared to
regular sorting). The usage can be best illustrated with an example.

Example:

----
uint hashFun(string) { ... expensive computation ... }
string[] array = ...;
// Sort strings by hash, slow
sort!("hashFun(a) < hashFun(b)")(array);
// Sort strings by hash, fast (only computes arr.length hashes):
schwartzSort!(hashFun, "a < b")(array);
----

The $(D schwartzSort) function might require less temporary data and
be faster than the Perl idiom or the decorate-sort-undecorate idiom
present in Python and Lisp. This is because sorting is done in-place
and only minimal extra data (one array of transformed elements) is
created.

To check whether an array was sorted and benefit of the speedup of
Schwartz sorting, a function $(D schwartzIsSorted) is not provided
because the effect can be achieved by calling $(D
isSorted!(less)(map!(transform)(r))).
 */
void schwartzSort(alias transform, alias less = "a < b",
        SwapStrategy ss = SwapStrategy.unstable, Range)(Range r)
    if (isRandomAccessRange!(Range) && hasLength!(Range))
{
    alias typeof(transform(r.front)) XformType;
    auto xform = new XformType[r.length];
    foreach (i, e; r)
    {
        xform[i] = transform(e);
    }
    auto z = zip(xform, r);
    alias typeof(z.front()) ProxyType;
    bool myLess(ProxyType a, ProxyType b)
    {
        return binaryFun!(less)(a.at!(0), b.at!(0));
    }
    sort!(myLess)(z);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    static double entropy(double[] probs) {
        double result = 0;
        foreach (p; probs) {
            if (!p) continue;
            //enforce(p > 0 && p <= 1, "Wrong probability passed to entropy");
            result -= p * log2(p);
        }
        return result;
    }

    auto lowEnt = ([ 1.0, 0, 0 ]).dup,
        midEnt = ([ 0.1, 0.1, 0.8 ]).dup,
        highEnt = ([ 0.31, 0.29, 0.4 ]).dup;
    double arr[][] = new double[][3];
    arr[0] = midEnt;
    arr[1] = lowEnt;
    arr[2] = highEnt;

    schwartzSort!(entropy, q{a < b})(arr);
    assert(arr[0] == lowEnt);
    assert(arr[1] == midEnt);
    assert(arr[2] == highEnt);
    assert(isSorted!("a < b")(map!(entropy)(arr)));

    schwartzSort!(entropy, q{a > b})(arr);
    assert(arr[0] == highEnt);
    assert(arr[1] == midEnt);
    assert(arr[2] == lowEnt);
    assert(isSorted!("a > b")(map!(entropy)(arr)));

    // random data
    auto b = rndstuff!(string);
    schwartzSort!(tolower)(b);
    assert(isSorted!("toupper(a) < toupper(b)")(b));
    assert(isSorted(map!(toupper)(b)));
}

// partialSort
/**
Reorders the random-access range $(D r) such that the range $(D r[0
.. mid]) is the same as if the entire $(D r) were sorted, and leaves
the range $(D r[mid .. r.length]) in no particular order. Performs
$(BIGOH r.length * log(mid)) evaluations of $(D pred). The
implementation simply calls $(D topN!(less, ss)(r, n)) and then $(D
sort!(less, ss)(r[0 .. n])).

Example:
----
int[] a = [ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 ];
partialSort(a, 5);
assert(a[0 .. 5] == [ 0, 1, 2, 3, 4 ]);
----
*/
void partialSort(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable,
    Range)(Range r, size_t n)
    if (isRandomAccessRange!(Range) && hasLength!(Range) && hasSlicing!(Range))
{
    topN!(less, ss)(r, n);
    sort!(less, ss)(r[0 .. n]);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 ];
    partialSort(a, 5);
    assert(a[0 .. 5] == [ 0, 1, 2, 3, 4 ]);
}

// completeSort
/**
Sorts the random-access range $(D chain(lhs, rhs)) according to
predicate $(D less). The left-hand side of the range $(D lhs) is
assumed to be already sorted; $(D rhs) is assumed to be unsorted. The
exact strategy chosen depends on the relative sizes of $(D lhs) and
$(D rhs).  Performs $(BIGOH lhs.length + rhs.length * log(rhs.length))
(best case) to $(BIGOH (lhs.length + rhs.length) * log(lhs.length +
rhs.length)) (worst-case) evaluations of $(D swap).

Example:
----
int[] a = [ 1, 2, 3 ];
int[] b = [ 4, 0, 6, 5 ];
completeSort(a, b);
assert(a == [ 0, 1, 2 ]);
assert(b == [ 3, 4, 5, 6 ]);
----
*/
void completeSort(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable,
        Range1, Range2)(Range1 lhs, Range2 rhs)
    if (isRandomAccessRange!(Range1) && hasLength!(Range1) && hasSlicing!(Range1))
{
    foreach (i; 0 .. rhs.length)
    {
        auto ub = upperBound!(less)(chain(lhs, rhs[0 .. i]), rhs[i]);
        if (!ub.length) continue;
        bringToFront(ub, rhs[i .. i + 1]);
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    int[] b = [ 4, 0, 6, 5 ];
    completeSort(a, b);
    assert(a == [ 0, 1, 2 ]);
    assert(b == [ 3, 4, 5, 6 ]);
}

// isSorted
/**
Checks whether a forward range is sorted according to the comparison
operation $(D less). Performs $(BIGOH r.length) evaluations of $(D
less).

Example:
----
int[] arr = [4, 3, 2, 1];
assert(!isSorted(arr));
sort(arr);
assert(isSorted(arr));
sort!("a > b")(arr);
assert(isSorted!("a > b")(arr));
----
*/

bool isSorted(alias less = "a < b", Range)(Range r)
    if (isForwardRange!(Range))
{
    // @@@TODO: make this work with findAdjacent
    if (r.empty) return true;
    static if (is(ElementType!(Range) == const))
    {
        auto ahead = r;
        for (ahead.popFront; !ahead.empty; r.popFront, ahead.popFront)
        {
            if (binaryFun!(less)(ahead.front, r.front)) return false;
        }
    }
    else
    {
        // cache the last element so we avoid calling r.front twice
        auto last = r.front;
        for (r.popFront; !r.empty; r.popFront)
        {
            auto popFront = r.front;
            if (binaryFun!(less)(popFront, last)) return false;
            move(popFront, last);
        }
    }
    return true;
}

// makeIndex
/**
Computes an index for $(D r) based on the comparison $(D less). The
index is a sorted array of pointers or indices into the original
range. This technique is similar to sorting, but it is more flexible
because (1) it allows "sorting" of immutable collections, (2) allows
binary search even if the original collection does not offer random
access, (3) allows multiple indexes, each on a different predicate,
and (4) may be faster when dealing with large objects. However, using
an index may also be slower under certain circumstances due to the
extra indirection, and is always larger than a sorting-based solution
because it needs space for the index in addition to the original
collection. The complexity is the same as $(D sort)'s.

$(D makeIndex) overwrites its second argument with the result, but
never reallocates it. If the second argument's length is less than
that of the range indexed, an exception is thrown.

The first overload of $(D makeIndex) writes to a range containing
pointers, and the second writes to a range containing offsets. The
first overload requires $(D Range) to be a forward range, and the
latter requires it to be a random-access range.

Example:
----
immutable(int[]) arr = [ 2, 3, 1, 5, 0 ];
// index using pointers
auto index1 = new immutable(int)*[arr.length];
makeIndex!("a < b")(arr, index1);
assert(isSorted!("*a < *b")(index1));
// index using offsets
auto index2 = new size_t[arr.length];
makeIndex!("a < b")(arr, index2);
assert(isSorted!
    ((size_t a, size_t b){ return arr[a] < arr[b];})
    (index2));
----
*/
void makeIndex(
    alias less = "a < b",
    SwapStrategy ss = SwapStrategy.unstable,
    Range,
    RangeIndex)
(Range r, RangeIndex index)
    if (isForwardRange!(Range) && isRandomAccessRange!(RangeIndex)
            && is(ElementType!(RangeIndex) : ElementType!(Range)*))
{
    // assume collection already ordered
    size_t i;
    for (; !r.empty; r.popFront, ++i)
        index[i] = &(r.front);
    enforce(index.length == i);
    // sort the index
    static bool indirectLess(ElementType!(RangeIndex) a,
            ElementType!(RangeIndex) b)
    {
        return binaryFun!(less)(*a, *b);
    }
    sort!(indirectLess, ss)(index);
}

/// Ditto
void makeIndex(
    alias less = "a < b",
    SwapStrategy ss = SwapStrategy.unstable,
    Range,
    RangeIndex)
(Range r, RangeIndex index)
    if (isRandomAccessRange!(Range) && isRandomAccessRange!(RangeIndex)
            && isIntegral!(ElementType!(RangeIndex)))
{
    // assume collection already ordered
    size_t i;
    auto r1 = r;
    for (; !r1.empty; r1.popFront, ++i)
        index[i] = i;
    enforce(index.length == i);
    // sort the index
    bool indirectLess(ElementType!(RangeIndex) a, ElementType!(RangeIndex) b)
    {
        return binaryFun!(less)(r[a], r[b]);
    }
    sort!(indirectLess, ss)(index);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    immutable(int)[] arr = [ 2, 3, 1, 5, 0 ];
    // index using pointers
    auto index1 = new immutable(int)*[arr.length];
    alias typeof(arr) ImmRange;
    alias typeof(index1) ImmIndex;
    static assert(isForwardRange!(ImmRange));
    static assert(isRandomAccessRange!(ImmIndex));
    static assert(!isIntegral!(ElementType!(ImmIndex)));
    static assert(is(ElementType!(ImmIndex) : ElementType!(ImmRange)*));
    makeIndex!("a < b")(arr, index1);
    assert(isSorted!("*a < *b")(index1));

    // index using offsets
    auto index2 = new size_t[arr.length];
    makeIndex(arr, index2);
    assert(isSorted!
            ((size_t a, size_t b){ return arr[a] < arr[b];})
            (index2));

    // index strings using offsets
    string[] arr1 = ["I", "have", "no", "chocolate"];
    auto index3 = new size_t[arr1.length];
    makeIndex(arr1, index3);
    assert(isSorted!
            ((size_t a, size_t b){ return arr1[a] < arr1[b];})
            (index3));
}

/**
Specifies whether the output of certain algorithm is desired in sorted
format.
 */
enum SortOutput {
    no,  /// Don't sort output
    yes, /// Sort output
}

void topNIndex(
    alias less = "a < b",
    SwapStrategy ss = SwapStrategy.unstable,
    Range, RangeIndex)(Range r, RangeIndex index, SortOutput sorted = SortOutput.no)
if (isIntegral!(ElementType!(RangeIndex)))
{
    if (index.empty) return;
    enforce(ElementType!(RangeIndex).max >= index.length,
            "Index type too small");
    bool indirectLess(ElementType!(RangeIndex) a, ElementType!(RangeIndex) b)
    {
        return binaryFun!(less)(r[a], r[b]);
    }
    auto heap = BinaryHeap!(RangeIndex, indirectLess)(index, 0);
    foreach (i; 0 .. r.length)
    {
        heap.conditionalInsert(cast(ElementType!RangeIndex) i);
    }
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty) heap.removeFront();
    }
}

void topNIndex(
    alias less = "a < b",
    SwapStrategy ss = SwapStrategy.unstable,
    Range, RangeIndex)(Range r, RangeIndex index,
            SortOutput sorted = SortOutput.no)
if (is(ElementType!(RangeIndex) == ElementType!(Range)*))
{
    if (index.empty) return;
    static bool indirectLess(const ElementType!(RangeIndex) a,
            const ElementType!(RangeIndex) b)
    {
        return binaryFun!less(*a, *b);
    }
    auto heap = BinaryHeap!(RangeIndex, indirectLess)(index, 0);
    foreach (i; 0 .. r.length)
    {
        heap.conditionalInsert(&r[i]);
    }
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty) heap.removeFront();
    }
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    {
        int[] a = [ 10, 8, 9, 2, 4, 6, 7, 1, 3, 5 ];
        int*[] b = new int*[5];
        topNIndex!("a > b")(a, b, SortOutput.yes);
        //foreach (e; b) writeln(*e);
        assert(b == [ &a[0], &a[2], &a[1], &a[6], &a[5]]);
    }
    {
        int[] a = [ 10, 8, 9, 2, 4, 6, 7, 1, 3, 5 ];
        auto b = new ubyte[5];
        topNIndex!("a > b")(a, b, SortOutput.yes);
        //foreach (e; b) writeln(e, ":", a[e]);
        assert(b == [ cast(ubyte) 0, cast(ubyte)2, cast(ubyte)1, cast(ubyte)6, cast(ubyte)5], text(b));
    }
}
/+

// topNIndexImpl
// @@@BUG1904
/*private*/ void topNIndexImpl(
    alias less,
    bool sortAfter,
    SwapStrategy ss,
    SRange, TRange)(SRange source, TRange target)
{
    alias binaryFun!(less) lessFun;
    static assert(ss == SwapStrategy.unstable,
            "Stable indexing not yet implemented");
    alias Iterator!(SRange) SIter;
    alias std.iterator.ElementType!(TRange) TElem;
    enum usingInt = isIntegral!(TElem);

    static if (usingInt)
    {
        enforce(source.length <= TElem.max,
                "Numeric overflow at risk in computing topNIndexImpl");
    }

    // types and functions used within
    SIter index2iter(TElem a)
    {
        static if (!usingInt)
            return a;
        else
            return begin(source) + a;
    }
    bool indirectLess(TElem a, TElem b)
    {
        return lessFun(*index2iter(a), *index2iter(b));
    }
    void indirectCopy(SIter from, ref TElem to)
    {
        static if (!usingInt)
            to = from;
        else
            to = cast(TElem)(from - begin(source));
    }

    // copy beginning of collection into the target
    auto sb = begin(source), se = end(source),
        tb = begin(target), te = end(target);
    for (; sb != se; ++sb, ++tb)
    {
        if (tb == te) break;
        indirectCopy(sb, *tb);
    }

    // if the index's size is same as the source size, just quicksort it
    // otherwise, heap-insert stuff in it.
    if (sb == se)
    {
        // everything in source is now in target... just sort the thing
        static if (sortAfter) sort!(indirectLess, ss)(target);
    }
    else
    {
        // heap-insert
        te = tb;
        tb = begin(target);
        target = range(tb, te);
        makeHeap!(indirectLess)(target);
        // add stuff to heap
        for (; sb != se; ++sb)
        {
            if (!lessFun(*sb, *index2iter(*tb))) continue;
            // copy the source over the smallest
            indirectCopy(sb, *tb);
            heapify!(indirectLess)(target, tb);
        }
        static if (sortAfter) sortHeap!(indirectLess)(target);
    }
}

/**
topNIndex
*/
void topNIndex(
    alias less,
    SwapStrategy ss = SwapStrategy.unstable,
    SRange, TRange)(SRange source, TRange target)
{
    return .topNIndexImpl!(less, false, ss)(source, target);
}

/// Ditto
void topNIndex(
    string less,
    SwapStrategy ss = SwapStrategy.unstable,
    SRange, TRange)(SRange source, TRange target)
{
    return .topNIndexImpl!(binaryFun!(less), false, ss)(source, target);
}

// partialIndex
/**
Computes an index for $(D source) based on the comparison $(D less)
and deposits the result in $(D target). It is acceptable that $(D
target.length < source.length), in which case only the smallest $(D
target.length) elements in $(D source) get indexed. The target
provides a sorted "view" into $(D source). This technique is similar
to sorting and partial sorting, but it is more flexible because (1) it
allows "sorting" of immutable collections, (2) allows binary search
even if the original collection does not offer random access, (3)
allows multiple indexes, each on a different comparison criterion, (4)
may be faster when dealing with large objects. However, using an index
may also be slower under certain circumstances due to the extra
indirection, and is always larger than a sorting-based solution
because it needs space for the index in addition to the original
collection. The complexity is $(BIGOH source.length *
log(target.length)).

Two types of indexes are accepted. They are selected by simply passing
the appropriate $(D target) argument: $(OL $(LI Indexes of type $(D
Iterator!(Source)), in which case the index will be sorted with the
predicate $(D less(*a, *b));) $(LI Indexes of an integral type
(e.g. $(D size_t)), in which case the index will be sorted with the
predicate $(D less(source[a], source[b])).))

Example:

----
immutable arr = [ 2, 3, 1 ];
int* index[3];
partialIndex(arr, index);
assert(*index[0] == 1 && *index[1] == 2 && *index[2] == 3);
assert(isSorted!("*a < *b")(index));
----
*/
void partialIndex(
    alias less,
    SwapStrategy ss = SwapStrategy.unstable,
    SRange, TRange)(SRange source, TRange target)
{
    return .topNIndexImpl!(less, true, ss)(source, target);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    immutable arr = [ 2, 3, 1 ];
    auto index = new immutable(int)*[3];
    partialIndex!(binaryFun!("a < b"))(arr, index);
    assert(*index[0] == 1 && *index[1] == 2 && *index[2] == 3);
    assert(isSorted!("*a < *b")(index));
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    static bool less(int a, int b) { return a < b; }
    {
        string[] x = ([ "c", "a", "b", "d" ]).dup;
        // test with integrals
        auto index1 = new size_t[x.length];
        partialIndex!(q{a < b})(x, index1);
        assert(index1[0] == 1 && index1[1] == 2 && index1[2] == 0
               && index1[3] == 3);
        // half-sized
        index1 = new size_t[x.length / 2];
        partialIndex!(q{a < b})(x, index1);
        assert(index1[0] == 1 && index1[1] == 2);

        // and with iterators
        auto index = new string*[x.length];
        partialIndex!(q{a < b})(x, index);
        assert(isSorted!(q{*a < *b})(index));
        assert(*index[0] == "a" && *index[1] == "b" && *index[2] == "c"
               && *index[3] == "d");
    }

    {
        immutable arr = [ 2, 3, 1 ];
        auto index = new immutable(int)*[arr.length];
        partialIndex!(less)(arr, index);
        assert(*index[0] == 1 && *index[1] == 2 && *index[2] == 3);
        assert(isSorted!(q{*a < *b})(index));
    }

    // random data
    auto b = rndstuff!(string);
    auto index = new string*[b.length];
    partialIndex!("toupper(a) < toupper(b)")(b, index);
    assert(isSorted!("toupper(*a) < toupper(*b)")(index));

    // random data with indexes
    auto index1 = new size_t[b.length];
    bool cmp(string x, string y) { return toupper(x) < toupper(y); }
    partialIndex!(cmp)(b, index1);
    bool check(size_t x, size_t y) { return toupper(b[x]) < toupper(b[y]); }
    assert(isSorted!(check)(index1));
}

// Commented out for now, needs reimplementation

// // schwartzMakeIndex
// /**
// Similar to $(D makeIndex) but using $(D schwartzSort) to sort the
// index.

// Example:

// ----
// string[] arr = [ "ab", "c", "Ab", "C" ];
// auto index = schwartzMakeIndex!(toupper, less, SwapStrategy.stable)(arr);
// assert(*index[0] == "ab" && *index[1] == "Ab"
//     && *index[2] == "c" && *index[2] == "C");
// assert(isSorted!("toupper(*a) < toupper(*b)")(index));
// ----
// */
// Iterator!(Range)[] schwartzMakeIndex(
//     alias transform,
//     alias less,
//     SwapStrategy ss = SwapStrategy.unstable,
//     Range)(Range r)
// {
//     alias Iterator!(Range) Iter;
//     auto result = new Iter[r.length];
//     // assume collection already ordered
//     size_t i = 0;
//     foreach (it; begin(r) .. end(r))
//     {
//         result[i++] = it;
//     }
//     // sort the index
//     alias typeof(transform(*result[0])) Transformed;
//     static bool indirectLess(Transformed a, Transformed b)
//     {
//         return less(a, b);
//     }
//     static Transformed indirectTransform(Iter a)
//     {
//         return transform(*a);
//     }
//     schwartzSort!(indirectTransform, less, ss)(result);
//     return result;
// }

// /// Ditto
// Iterator!(Range)[] schwartzMakeIndex(
//     alias transform,
//     string less = q{a < b},
//     SwapStrategy ss = SwapStrategy.unstable,
//     Range)(Range r)
// {
//     return .schwartzMakeIndex!(
//         transform, binaryFun!(less), ss, Range)(r);
// }

// version (wyda) unittest
// {
//     string[] arr = [ "D", "ab", "c", "Ab", "C" ];
//     auto index = schwartzMakeIndex!(toupper, "a < b",
//                                     SwapStrategy.stable)(arr);
//     assert(isSorted!(q{toupper(*a) < toupper(*b)})(index));
//     assert(*index[0] == "ab" && *index[1] == "Ab"
//            && *index[2] == "c" && *index[3] == "C");

//     // random data
//     auto b = rndstuff!(string);
//     auto index1 = schwartzMakeIndex!(toupper)(b);
//     assert(isSorted!("toupper(*a) < toupper(*b)")(index1));
// }

+/

// lowerBound
/**
This function assumes that range $(D r) consists of a subrange $(D r1)
of elements $(D e1) for which $(D pred(e1, value)) is $(D true),
followed by a subrange $(D r2) of elements $(D e2) for which $(D
pred(e2, value)) is $(D false). Using this assumption, $(D lowerBound)
uses binary search to find $(D r1), i.e. the left subrange on which
$(D pred) is always $(D true). Performs $(BIGOH log(r.length))
evaluations of $(D pred).  The precondition is not verified because it
would deteriorate function's complexity. It is possible that the types
of $(D value) and $(D ElementType!(Range)) are different, if the
predicate accepts them. See also STL's $(WEB
sgi.com/tech/stl/lower_bound.html, lower_bound).

Precondition: $(D find!(not!(pred))(r, value).length +
find!(pred)(retro(r), value).length == r.length)

Example:
----
int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
auto p = lowerBound!("a < b")(a, 4);
assert(p == [ 0, 1, 2, 3 ]);
p = lowerBound(a, 4); // uses "a < b" by default
assert(p == [ 0, 1, 2, 3 ]);
----
*/
Range lowerBound(alias pred = "a < b", Range, V)(Range r, V value)
    if (isRandomAccessRange!(Range) && hasLength!(Range))
{
    auto first = 0, count = r.length;
    while (count > 0)
    {
        immutable step = count / 2;
        auto it = first + step;
        if (binaryFun!(pred)(r[it], value))
        {
            first = it + 1;
            count -= step + 1;
        }
        else
        {
            count = step;
        }
    }
    return r[0 .. first];
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    auto p = lowerBound!("a < b")(a, 4);
    assert(p == [0, 1, 2, 3]);
    p = lowerBound(a, 5);
    assert(p == [0, 1, 2, 3, 4]);
    p = lowerBound!(q{a < b})(a, 6);
    assert(p == [ 0, 1, 2, 3, 4, 5]);
}

// upperBound
/**
This function assumes that range $(D r) consists of a subrange $(D r1)
of elements $(D e1) for which $(D pred(value, e1)) is $(D false),
followed by a subrange $(D r2) of elements $(D e2) for which $(D
pred(value, e2)) is $(D true). (Note the differences in subrange
definition and argument order for $(D pred) compared to $(D
lowerBound).) Using this assumption, $(D upperBound) uses binary
search to find $(D r2), i.e. the right subrange on which $(D pred) is
always $(D true). Performs $(BIGOH log(r.length)) evaluations of $(D
pred).  The precondition is not verified because it would deteriorate
function's complexity. It is possible that the types of $(D value) and
$(D ElementType!(Range)) are different, if the predicate accepts
them. See also STL's $(WEB sgi.com/tech/stl/lower_bound.html,
upper_bound).

Precondition: $(D find!(pred)(r, value).length +
find!(not!(pred))(retro(r), value).length == r.length)

Example:
----
auto a = [ 1, 2, 3, 3, 3, 4, 4, 5, 6 ];
auto p = upperBound(a, 3);
assert(p == begin(a) + 5);
----
*/
Range upperBound(alias pred = "a < b", Range, V)(Range r, V value)
    if (isRandomAccessRange!(Range))
{
    auto first = 0;
    size_t count = r.length;
    while (count > 0)
    {
        auto step = count / 2;
        auto it = first + step;
        if (!binaryFun!(pred)(value, r[it]))
        {
            first = it + 1;
            count -= step + 1;
        }
        else count = step;
    }
    return r[first .. r.length];
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 3, 3, 4, 4, 5, 6 ];
    auto p = upperBound(a, 3);
    assert(p == [4, 4, 5, 6 ]);
}

// equalRange
/**
Assuming a range satisfying both preconditions for $(D
lowerBound!(pred)(r, value)) and $(D upperBound!(pred)(r, value)), the
call $(D equalRange!(pred)(r, v)) returns the subrange containing all
elements $(D e) for which both $(D pred(e, value)) and $(D pred(value,
e)) evaluate to $(D false). Performs $(BIGOH log(r.length))
evaluations of $(D pred). See also STL's $(WEB
sgi.com/tech/stl/equal_range.html, equal_range).

Precondition: $(D find!(not!(pred))(r, value).length +
find!(pred)(retro(r), value).length == r.length) && $(D find!(pred)(r,
value).length + find!(not!(pred))(retro(r), value).length == r.length)

Example:
----
auto a = [ 1, 2, 3, 3, 3, 4, 4, 5, 6 ];
auto r = equalRange(a, 3);
assert(r == [ 3, 3, 3 ]);
----
*/
Range equalRange(alias less = "a < b", Range, V)(Range r, V value)
    if (isRandomAccessRange!(Range) && hasLength!(Range))
{
    alias binaryFun!(less) lessFun;
    auto left = lowerBound!(less)(r, value);
    auto right = upperBound!(less)(r[left.length .. r.length], value);
    return r[left.length .. r.length - right.length];
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3, 3, 3, 4, 4, 5, 6 ];
    auto p = equalRange(a, 3);
    assert(p == [ 3, 3, 3 ], text(p));
    p = equalRange(a, 4);
    assert(p == [ 4, 4 ], text(p));
    p = equalRange(a, 2);
    assert(p == [ 2 ]);
}

// canFind
/**
Returns $(D true) if and only if $(D value) can be found in $(D
range). Performs $(BIGOH r.length) evaluations of $(D pred). */

bool canFind(alias pred = "a == b", Range, V)(Range range, V value)
if (is(typeof(find!pred(range, value))))
{
    return !find!pred(range, value).empty;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto a = rndstuff!(int);
    if (a.length)
    {
        auto b = a[a.length / 2];
        assert(canFind(a, b));
    }
}

// canFind
/**
Returns $(D true) if and only if a value $(D v) satisfying the
predicate $(D pred) can be found in the forward range $(D
range). Performs $(BIGOH r.length) evaluations of $(D pred).
 */

bool canFind(alias pred, Range)(Range range)
if (is(typeof(find!pred(range))))
{
    return !find!pred(range).empty;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto a = [ 1, 2, 0, 4 ];
    assert(canFind!"a == 2"(a));
}

// canFindSorted
/**
Returns $(D true) if and only if $(D value) can be found in $(D
range), which is assumed to be sorted. Performs $(BIGOH log(r.length))
evaluations of $(D less). See also STL's $(WEB
sgi.com/tech/stl/binary_search.html, binary_search).
*/

bool canFindSorted(alias less = "a < b", Range, V)(Range range, V value)
    if (isRandomAccessRange!(Range) && hasLength!(Range))
{
    auto lb = lowerBound!(less)(range, value);
    return lb.length < range.length &&
        !binaryFun!(less)(value, range[lb.length]);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto a = rndstuff!(int);
    if (a.length)
    {
        auto b = a[a.length / 2];
        sort(a);
        assert(canFindSorted(a, b));
    }
}

/**
Copies the top $(D n) elements of the input range $(D source) into the
random-access range $(D target), where $(D n =
target.length). Elements of $(D source) are not touched. If $(D
sorted) is $(D true), the target is sorted. Otherwise, the target
respects the $(WEB en.wikipedia.org/wiki/Binary_heap, heap property).

Example:
----
int[] a = [ 10, 16, 2, 3, 1, 5, 0 ];
int[] b = new int[3];
topNCopy(a, b, true);
assert(b == [ 0, 1, 2 ]);
----
 */
TRange topNCopy(alias less = "a < b", SRange, TRange)
    (SRange source, TRange target, SortOutput sorted = SortOutput.no)
    if (isInputRange!(SRange) && isRandomAccessRange!(TRange)
            && hasLength!(TRange) && hasSlicing!(TRange))
{
    if (target.empty) return target;
    auto heap = BinaryHeap!(TRange, less)(target, 0);
    foreach (e; source) heap.conditionalInsert(e);
    auto result = target[0 .. heap.length];
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty) heap.removeFront();
    }
    return result;
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 10, 16, 2, 3, 1, 5, 0 ];
    int[] b = new int[3];
    topNCopy(a, b, SortOutput.yes);
    assert(b == [ 0, 1, 2 ]);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto r = Random(unpredictableSeed);
    int[] a = new int[uniform(1, 1000, r)];
    foreach (i, ref e; a) e = i;
    randomShuffle(a, r);
    auto n = uniform(0, a.length, r);
    int[] b = new int[n];
    topNCopy!(binaryFun!("a < b"))(a, b, SortOutput.yes);
    assert(isSorted!(binaryFun!("a < b"))(b));
}

/**
Lazily computes the union of two or more ranges $(D rs). The ranges
are assumed to be sorted by $(D less). Elements in the output are not
unique; the length of the output is the sum of the lengths of the
inputs. (The $(D length) member is offered if all ranges also have
length.) The element types of all ranges must have a common type.

Example:
----
int[] a = [ 1, 2, 4, 5, 7, 9 ];
int[] b = [ 0, 1, 2, 4, 7, 8 ];
int[] c = [ 10 ];
assert(setUnion(a, b).length == a.length + b.length);
assert(equal(setUnion(a, b), [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9][]));
assert(equal(setUnion(a, c, b),
    [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9, 10][]));
----
 */
struct SetUnion(alias less = "a < b", Rs...) if (allSatisfy!(isInputRange, Rs))
{
private:
    Rs _r;
    alias binaryFun!(less) comp;
    uint _crt;

    void adjustPosition(uint candidate = 0)()
    {
        static if (candidate == Rs.length)
        {
            _crt = _crt.max;
        }
        else
        {
            if (_r[candidate].empty)
            {
                adjustPosition!(candidate + 1)();
                return;
            }
            foreach (i, U; Rs[candidate + 1 .. $])
            {
                enum j = candidate + i + 1;
                if (_r[j].empty) continue;
                if (comp(_r[j].front, _r[candidate].front))
                {
                    // a new candidate was found
                    adjustPosition!(j)();
                    return;
                }
            }
            // Found a successful candidate
            _crt = candidate;
        }
    }

public:
    alias CommonType!(staticMap!(.ElementType, Rs)) ElementType;

    this(Rs rs)
    {
        this._r = rs;
        adjustPosition();
    }

    @property bool empty()
    {
        return _crt == _crt.max;
    }

    void popFront()
    {
        // Assumes _crt is correct
        assert(!empty);
        foreach (i, U; Rs)
        {
            if (i < _crt) continue;
            // found _crt
            assert(!_r[i].empty);
            _r[i].popFront;
            adjustPosition();
            return;
        }
        assert(false);
    }

    @property ElementType front()
    {
        assert(!empty);
        // Assume _crt is correct
        foreach (i, U; Rs)
        {
            if (i < _crt) continue;
            assert(!_r[i].empty);
            return _r[i].front;
        }
        assert(false);
    }

    static if (allSatisfy!(hasLength, Rs))
    {
        @property size_t length()
        {
            size_t result;
            foreach (i, U; Rs)
            {
                result += _r[i].length;
            }
            return result;
        }
    }
}

/// Ditto
SetUnion!(less, Rs) setUnion(alias less = "a < b", Rs...)
(Rs rs)
{
    return typeof(return)(rs);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    int[] c = [ 10 ];
    //foreach (e; setUnion(a, b)) writeln(e);
    assert(setUnion(a, b).length == a.length + b.length);
    assert(equal(setUnion(a, b), [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9][]));
    assert(equal(setUnion(a, c, b),
                    [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9, 10][]));
}

/**
Lazily computes the intersection of two or more input ranges $(D
rs). The ranges are assumed to be sorted by $(D less). The element
types of all ranges must have a common type.

Example:
----
int[] a = [ 1, 2, 4, 5, 7, 9 ];
int[] b = [ 0, 1, 2, 4, 7, 8 ];
int[] c = [ 0, 1, 4, 5, 7, 8 ];
assert(equal(setIntersection(a, a), a));
assert(equal(setIntersection(a, b), [1, 2, 4, 7][]));
assert(equal(setIntersection(a, b, c), [1, 4, 7][]));
----
 */
struct SetIntersection(alias less = "a < b", Rs...)
if (allSatisfy!(isInputRange, Rs))
{
    static assert(Rs.length == 2);
private:
    Rs _input;
    alias binaryFun!(less) comp;
    alias CommonType!(staticMap!(.ElementType, Rs)) ElementType;

    void adjustPosition()
    {
        // Positions to the first two elements that are equal
        while (!empty)
        {
            if (comp(_input[0].front, _input[1].front))
            {
                _input[0].popFront;
            }
            else if (comp(_input[1].front, _input[0].front))
            {
                _input[1].popFront;
            }
            else
            {
                break;
            }
        }
    }

public:
    this(Rs input)
    {
        this._input = input;
        // position to the first element
        adjustPosition;
    }

    @property bool empty()
    {
        foreach (i, U; Rs)
        {
            if (_input[i].empty) return true;
        }
        return false;
    }

    void popFront()
    {
        assert(!empty);
        assert(!comp(_input[0].front, _input[1].front)
                && !comp(_input[1].front, _input[0].front));
        _input[0].popFront;
        _input[1].popFront;
        adjustPosition;
    }

    @property ElementType front()
    {
        assert(!empty);
        return _input[0].front;
    }
}

/// Ditto
SetIntersection!(less, Rs) setIntersection(alias less = "a < b", Rs...)
(Rs ranges)
if (allSatisfy!(isInputRange, Rs))
{
    return typeof(return)(ranges);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    int[] c = [ 0, 1, 4, 5, 7, 8 ];
    //foreach (e; setIntersection(a, b, c)) writeln(e);
    assert(equal(setIntersection(a, b), [1, 2, 4, 7][]));
    assert(equal(setIntersection(a, a), a));
    // assert(equal(setIntersection(a, b, b, a), [1, 2, 4, 7][]));
    // assert(equal(setIntersection(a, b, c), [1, 4, 7][]));
    // assert(equal(setIntersection(a, c, b), [1, 4, 7][]));
    // assert(equal(setIntersection(b, a, c), [1, 4, 7][]));
    // assert(equal(setIntersection(b, c, a), [1, 4, 7][]));
    // assert(equal(setIntersection(c, a, b), [1, 4, 7][]));
    // assert(equal(setIntersection(c, b, a), [1, 4, 7][]));
}

/**
Lazily computes the difference of $(D r1) and $(D r2). The two ranges
are assumed to be sorted by $(D less). The element types of the two
ranges must have a common type.

Example:
----
int[] a = [ 1, 2, 4, 5, 7, 9 ];
int[] b = [ 0, 1, 2, 4, 7, 8 ];
assert(equal(setDifference(a, b), [5, 9][]));
----
 */
struct SetDifference(alias less = "a < b", R1, R2)
    if (isInputRange!(R1) && isInputRange!(R2))
{
private:
    R1 r1;
    R2 r2;
    alias binaryFun!(less) comp;

    void adjustPosition()
    {
        while (!r1.empty)
        {
            if (r2.empty || comp(r1.front, r2.front)) break;
            if (comp(r2.front, r1.front))
            {
                r2.popFront;
            }
            else
            {
                // both are equal
                r1.popFront;
                r2.popFront;
            }
        }
    }

public:
    this(R1 r1, R2 r2)
    {
        this.r1 = r1;
        this.r2 = r2;
        // position to the first element
        adjustPosition;
    }

    void popFront()
    {
        r1.popFront;
        adjustPosition;
    }

    @property ElementType!(R1) front()
    {
        assert(!empty);
        return r1.front;
    }

    bool empty() { return r1.empty; }
}

/// Ditto
SetDifference!(less, R1, R2) setDifference(alias less = "a < b", R1, R2)
(R1 r1, R2 r2)
{
    return typeof(return)(r1, r2);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    //foreach (e; setDifference(a, b)) writeln(e);
    assert(equal(setDifference(a, b), [5, 9][]));
}

/**
Lazily computes the symmetric difference of $(D r1) and $(D r2),
i.e. the elements that are present in exactly one of $(D r1) and $(D
r2). The two ranges are assumed to be sorted by $(D less), and the
output is also sorted by $(D less). The element types of the two
ranges must have a common type.

Example:
----
int[] a = [ 1, 2, 4, 5, 7, 9 ];
int[] b = [ 0, 1, 2, 4, 7, 8 ];
assert(equal(setSymmetricDifference(a, b), [0, 5, 8, 9][]));
----
 */
struct SetSymmetricDifference(alias less = "a < b", R1, R2)
    if (isInputRange!(R1) && isInputRange!(R2))
{
private:
    R1 r1;
    R2 r2;
    //bool usingR2;
    alias binaryFun!(less) comp;

    void adjustPosition()
    {
        while (!r1.empty && !r2.empty)
        {
            if (comp(r1.front, r2.front) || comp(r2.front, r1.front))
            {
                break;
            }
            // equal, pop both
            r1.popFront;
            r2.popFront;
        }
    }

public:
    this(R1 r1, R2 r2)
    {
        this.r1 = r1;
        this.r2 = r2;
        // position to the first element
        adjustPosition;
    }

    void popFront()
    {
        assert(!empty);
        if (r1.empty) r2.popFront;
        else if (r2.empty) r1.popFront;
        else
        {
            // neither is empty
            if (comp(r1.front, r2.front))
            {
                r1.popFront;
            }
            else
            {
                assert(comp(r2.front, r1.front));
                r2.popFront;
            }
        }
        adjustPosition;
    }

    @property ElementType!(R1) front()
    {
        assert(!empty);
        if (r2.empty || !r1.empty && comp(r1.front, r2.front))
        {
            return r1.front;
        }
        assert(r1.empty || comp(r2.front, r1.front));
        return r2.front;
    }

    ref auto opSlice() { return this; }

    @property bool empty() { return r1.empty && r2.empty; }
}

/// Ditto
SetSymmetricDifference!(less, R1, R2)
setSymmetricDifference(alias less = "a < b", R1, R2)
(R1 r1, R2 r2)
{
    return typeof(return)(r1, r2);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    //foreach (e; setSymmetricDifference(a, b)) writeln(e);
    assert(equal(setSymmetricDifference(a, b), [0, 5, 8, 9][]));
}

// Internal random array generators

version(unittest)
{
    private enum size_t maxArraySize = 50;
    private enum size_t minArraySize = maxArraySize - 1;

    private string[] rndstuff(T : string)()
    {
        static Random rnd;
        static bool first = true;
        if (first)
        {
            rnd = Random(unpredictableSeed);
            first = false;
        }
        string[] result =
            new string[uniform(minArraySize, maxArraySize, rnd)];
        string alpha = "abcdefghijABCDEFGHIJ";
        foreach (ref s; result)
        {
            foreach (i; 0 .. uniform(0u, 20u, rnd))
            {
                auto j = uniform(0, alpha.length - 1, rnd);
                s ~= alpha[j];
            }
        }
        return result;
    }

    private int[] rndstuff(T : int)()
    {
        static Random rnd;
        static bool first = true;
        if (first)
        {
            rnd = Random(unpredictableSeed);
            first = false;
        }
        int[] result = new int[uniform(minArraySize, maxArraySize, rnd)];
        foreach (ref i; result)
        {
            i = uniform(-100, 100, rnd);
        }
        return result;
    }

    private double[] rndstuff(T : double)()
    {
        double[] result;
        foreach (i; rndstuff!(int)())
        {
            result ~= i / 50.;
        }
        return result;
    }
}

// NWayUnion
/**
Computes the union of multiple sets. The input sets are passed as a
range of ranges and each is assumed to be sorted by $(D
less). Computation is done lazily, one union element at a time. The
complexity of one $(D popFront) operation is $(BIGOH
log(ror.length)). However, the length of $(D ror) decreases as ranges
in it are exhausted, so the complexity of a full pass through $(D
NWayUnion) is dependent on the distribution of the lengths of ranges
contained within $(D ror). If all ranges have the same length $(D n)
(worst case scenario), the complexity of a full pass through $(D
NWayUnion) is $(BIGOH n * ror.length * log(ror.length)), i.e., $(D
log(ror.length)) times worse than just spanning all ranges in
turn. The output comes sorted (unstably) by $(D less).

Warning: Because $(D NWayUnion) does not allocate extra memory, it
will leave $(D ror) modified. Namely, $(D NWayUnion) assumes ownership
of $(D ror) and discretionarily swaps and advances elements of it. If
you want $(D ror) to preserve its contents after the call, you may
want to pass a duplicate to $(D NWayUnion) (and perhaps cache the
duplicate in between calls).

Example:
----
double[][] a =
[
    [ 1, 4, 7, 8 ],
    [ 1, 7 ],
    [ 1, 7, 8],
    [ 4 ],
    [ 7 ],
];
auto witness = [
    1, 1, 1, 4, 4, 7, 7, 7, 7, 8, 8
];
assert(equal(nWayUnion(a), witness[]));
----
 */
struct NWayUnion(alias less, RangeOfRanges)
{
    private alias .ElementType!(.ElementType!RangeOfRanges) ElementType;
    private alias binaryFun!less comp;
    private RangeOfRanges _ror;
    static bool compFront(.ElementType!RangeOfRanges a,
            .ElementType!RangeOfRanges b)
    {
        // revert comparison order so we get the smallest elements first
        return comp(b.front, a.front);
    }
    BinaryHeap!(RangeOfRanges, compFront) _heap;

    this(RangeOfRanges ror)
    {
        // Preemptively get rid of all empty ranges in the input
        // No need for stability either
        _ror = remove!("a.empty", SwapStrategy.unstable)(ror);
        //Build the heap across the range
        _heap.acquire(_ror);
    }

    @property bool empty() { return _ror.empty; }

    @property ref ElementType front()
    {
        return _heap.front.front;
    }

    void popFront()
    {
        _heap.removeFront();
        // let's look at the guy just popped
        _ror.back.popFront;
        if (_ror.back.empty)
        {
            _ror.popBack;
            // nothing else to do: the empty range is not in the
            // heap and not in _ror
            return;
        }
        // Put the popped range back in the heap
        _heap.conditionalInsert(_ror.back) || assert(false);
    }
}

/// Ditto
NWayUnion!(less, RangeOfRanges) nWayUnion
(alias less = "a < b", RangeOfRanges)
(RangeOfRanges ror)
{
    return typeof(return)(ror);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    double[][] a =
    [
        [ 1, 4, 7, 8 ],
        [ 1, 7 ],
        [ 1, 7, 8],
        [ 4 ],
        [ 7 ],
    ];
    auto witness = [
        1, 1, 1, 4, 4, 7, 7, 7, 7, 8, 8
    ];
    //foreach (e; nWayUnion(a)) writeln(e);
    assert(equal(nWayUnion(a), witness[]));
}

// largestPartialIntersection
/**
Given a range of sorted forward ranges $(D ror), copies to $(D tgt)
the elements that are common to most ranges, along with their number
of occurrences. All ranges in $(D ror) are assumed to be sorted by $(D
less). Only the most frequent $(D tgt.length) elements are returned.

Example:
----
// Figure which number can be found in most arrays of the set of
// arrays below.
double[][] a =
[
    [ 1, 4, 7, 8 ],
    [ 1, 7 ],
    [ 1, 7, 8],
    [ 4 ],
    [ 7 ],
];
auto b = new Tuple!(double, uint)[1];
largestPartialIntersection(a, b);
// First member is the item, second is the occurrence count
assert(b[0] == tuple(7.0, 4u));
----

$(D 7.0) is the correct answer because it occurs in $(D 4) out of the
$(D 5) inputs, more than any other number. The second member of the
resulting tuple is indeed $(D 4) (recording the number of occurrences
of $(D 7.0)). If more of the top-frequent numbers are needed, just
create a larger $(D tgt) range. In the axample above, creating $(D b)
with length $(D 2) yields $(D tuple(1.0, 3u)) in the second position.

The function $(D largestPartialIntersection) is useful for
e.g. searching an $(LUCKY inverted index) for the documents most
likely to contain some terms of interest. The complexity of the search
is $(BIGOH n * log(tgt.length)), where $(D n) is the sum of lengths of
all input ranges. This approach is faster than keeping an associative
array of the occurrences and then selecting its top items, and also
requires less memory ($(D largestPartialIntersection) builds its
result directly in $(D tgt) and requires no extra memory).

Warning: Because $(D largestPartialIntersection) does not allocate
extra memory, it will leave $(D ror) modified. Namely, $(D
largestPartialIntersection) assumes ownership of $(D ror) and
discretionarily swaps and advances elements of it. If you want $(D
ror) to preserve its contents after the call, you may want to pass a
duplicate to $(D largestPartialIntersection) (and perhaps cache the
duplicate in between calls).
 */
void largestPartialIntersection
(alias less = "a < b", RangeOfRanges, Range)
(RangeOfRanges ror, Range tgt, SortOutput sorted = SortOutput.no)
{
    struct UnitWeights
    {
        static int opIndex(ElementType!(ElementType!RangeOfRanges)) { return 1; }
    }
    return largestPartialIntersectionWeighted!less(ror, tgt, UnitWeights(),
            sorted);
}

// largestPartialIntersectionWeighted
/**
Similar to $(D largestPartialIntersection), but associates a weight
with each distinct element in the intersection.

Example:
----
// Figure which number can be found in most arrays of the set of
// arrays below, with specific per-element weights
double[][] a =
[
    [ 1, 4, 7, 8 ],
    [ 1, 7 ],
    [ 1, 7, 8],
    [ 4 ],
    [ 7 ],
];
auto b = new Tuple!(double, uint)[1];
double[double] weights = [ 1:1.2, 4:2.3, 7:1.1, 8:1.1 ];
largestPartialIntersectionWeighted(a, b, weights);
// First member is the item, second is the occurrence count
assert(b[0] == tuple(4.0, 2u));
----

The correct answer in this case is $(D 4.0), which, although only
appears two times, has a total weight $(D 4.6) (three times its weight
$(D 2.3)). The value $(D 7) is weighted with $(D 1.1) and occurs four
times for a total weight $(D 4.4).
 */
void largestPartialIntersectionWeighted
(alias less = "a < b", RangeOfRanges, Range, WeightsAA)
(RangeOfRanges ror, Range tgt, WeightsAA weights, SortOutput sorted = SortOutput.no)
{
    if (tgt.empty) return;
    alias ElementType!Range InfoType;
    bool heapComp(InfoType a, InfoType b)
    {
        return weights[a.field[0]] * a.field[1] >
            weights[b.field[0]] * b.field[1];
    }
    topNCopy!heapComp(group(nWayUnion!less(ror)), tgt, sorted);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    double[][] a =
        [
            [ 1, 4, 7, 8 ],
            [ 1, 7 ],
            [ 1, 7, 8],
            [ 4 ],
            [ 7 ],
        ];
    auto b = new Tuple!(double, uint)[2];
    largestPartialIntersection(a, b, SortOutput.yes);
    //sort(b);
    //writeln(b);
    assert(b == [ tuple(7., 4u), tuple(1., 3u) ][], text(b));
    assert(a[0].empty);
}

unittest
{
    // scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    string[][] a =
        [
            [ "1", "4", "7", "8" ],
            [ "1", "7" ],
            [ "1", "7", "8"],
            [ "4" ],
            [ "7" ],
        ];
    auto b = new Tuple!(string, uint)[2];
    largestPartialIntersection(a, b, SortOutput.yes);
    //writeln(b);
    assert(b == [ tuple("7", 4u), tuple("1", 3u) ][], text(b));
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
// Figure which number can be found in most arrays of the set of
// arrays below, with specific per-element weights
    double[][] a =
        [
            [ 1, 4, 7, 8 ],
            [ 1, 7 ],
            [ 1, 7, 8],
            [ 4 ],
            [ 7 ],
            ];
    auto b = new Tuple!(double, uint)[1];
    double[double] weights = [ 1:1.2, 4:2.3, 7:1.1, 8:1.1 ];
    largestPartialIntersectionWeighted(a, b, weights);
// First member is the item, second is the occurrence count
    //writeln(b[0]);
    assert(b[0] == tuple(4.0, 2u));
}
