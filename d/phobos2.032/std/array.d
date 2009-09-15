// Written in the D programming language

module std.array;

import std.c.stdio;
import core.memory;
import std.algorithm, std.contracts, std.conv, std.encoding, std.range,
    std.string, std.traits, std.typecons;
version(unittest) private import std.stdio;

/**
Returns a newly-allocated array consisting of a copy of the input
range $(D r).

Example:

----
auto a = array([1, 2, 3, 4, 5][]);
assert(a == [ 1, 2, 3, 4, 5 ]);
----
 */
ElementType!Range[] array(Range)(Range r) if (isForwardRange!Range)
{
    alias ElementType!Range E;
    static if (hasLength!Range)
    {
        if (r.empty) return null;
        auto result = (cast(E*) enforce(GC.malloc(r.length * E.sizeof),
                text("Out of memory while allocating an array of ",
                        r.length, " objects of type ", E.stringof)))[0 .. r.length];
        foreach (ref e; result)
        {
            // hacky
            static if (is(typeof(&e.opAssign)))
            {
                // this should be in-place construction
                new(&e) E(r.front);
            }
            else
            {
                e = r.front;
            }
            r.popFront;
        }
        return result;
    }
    else
    {
        auto a = Appender!(E[])();
        foreach (e; r)
        {
            a.put(e);
        }
        return a.data;
    }
    // // 2. Initialize the memory
    // size_t constructedElements = 0;
    // scope(failure)
    // {
    //     // Deconstruct only what was constructed
    //     foreach_reverse (i; 0 .. constructedElements)
    //     {
    //         try
    //         {
    //             //result[i].~E();
    //         }
    //         catch (Exception e)
    //         {
    //         }
    //     }
    //     // free the entire array
    //     std.gc.realloc(result, 0);
    // }
    // foreach (src; elements)
    // {
    //     static if (is(typeof(new(result + constructedElements) E(src))))
    //     {
    //         new(result + constructedElements) E(src);
    //     }
    //     else
    //     {
    //         result[constructedElements] = src;
    //     }
    //     ++constructedElements;
    // }
    // // 3. Success constructing all elements, type the array and return it
    // setTypeInfo(typeid(E), result);
    // return result[0 .. constructedElements];
}

version(unittest)
{
    struct TestArray { int x; string toString() { return .to!string(x); } }
}

unittest
{
    auto a = array([1, 2, 3, 4, 5][]);
    //writeln(a);
    assert(a == [ 1, 2, 3, 4, 5 ]);

    auto b = array([TestArray(1), TestArray(2)][]);
    //writeln(b);

    class C
    {
        int x;
        this(int y) { x = y; }
        override string toString() { return .to!string(x); }
    }
    auto c = array([new C(1), new C(2)][]);
    //writeln(c);

    auto d = array([1., 2.2, 3][]);
    assert(is(typeof(d) == double[]));
    //writeln(d);
}

template IndexType(C : T[], T)
{
    alias size_t IndexType;
}

unittest
{
    static assert(is(IndexType!(double[]) == size_t));
    static assert(!is(IndexType!(double) == size_t));
}

/**
Implements the range interface primitive $(D empty) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.empty) is
equivalent to $(D empty(array)).

Example:
----
void main()
{
    auto a = [ 1, 2, 3 ];
    assert(!a.empty);
    assert(a[3 .. $].empty);
}
----
 */

bool empty(T)(in T[] a) { return !a.length; }

unittest
{
    auto a = [ 1, 2, 3 ];
    assert(!a.empty);
    assert(a[3 .. $].empty);
}

/**
Implements the range interface primitive $(D popFront) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.popFront) is
equivalent to $(D popFront(array)).


Example:
----
void main()
{
    int[] a = [ 1, 2, 3 ];
    a.popFront;
    assert(a == [ 2, 3 ]);
}
----
*/

void popFront(T)(ref T[] a)
{
    assert(a.length, "Attempting to popFront() past the end of an array of "
            ~ T.stringof);
    a = a[1 .. $];
}

unittest
{
    //@@@BUG 2608@@@
    //auto a = [ 1, 2, 3 ];
    int[] a = [ 1, 2, 3 ];
    a.popFront;
    assert(a == [ 2, 3 ]);
}

/**
Implements the range interface primitive $(D popBack) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.popBack) is
equivalent to $(D popBack(array)).


Example:
----
void main()
{
    int[] a = [ 1, 2, 3 ];
    a.popBack;
    assert(a == [ 1, 2 ]);
}
----
*/

void popBack(T)(ref T[] a) { assert(a.length); a = a[0 .. $ - 1]; }

unittest
{
    //@@@BUG 2608@@@
    //auto a = [ 1, 2, 3 ];
    int[] a = [ 1, 2, 3 ];
    a.popBack;
    assert(a == [ 1, 2 ]);
}

/**
Implements the range interface primitive $(D front) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.front) is
equivalent to $(D front(array)).


Example:
----
void main()
{
    int[] a = [ 1, 2, 3 ];
    assert(a.front == 1);
}
----
*/
ref typeof(A[0]) front(A)(A a) if (is(typeof(A[0])))
{
    assert(a.length, "Attempting to fetch the front of an empty array");
    return a[0];
}

/// Ditto
void front(T)(T[] a, T v) { assert(a.length); a[0] = v; }

/**
Implements the range interface primitive $(D back) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.back) is
equivalent to $(D back(array)).

Example:
----
void main()
{
    int[] a = [ 1, 2, 3 ];
    assert(a.front == 1);
}
----
*/
ref T back(T)(T[] a) { assert(a.length); return a[a.length - 1]; }

/**
Implements the range interface primitive $(D put) for built-in
arrays. Due to the fact that nonmember functions can be called with
the first argument using the dot notation, $(D array.put(e)) is
equivalent to $(D put(array, e)).

Example:
----
void main()
{
    int[] a = [ 1, 2, 3 ];
    int[] b = a;
    a.put(5);
    assert(a == [ 2, 3 ]);
    assert(b == [ 5, 2, 3 ]);
}
----
*/
void put(T, E)(ref T[] a, E e) { assert(a.length); a[0] = e; a = a[1 .. $]; }

// overlap
/*
Returns the overlapping portion, if any, of two arrays. Unlike $(D
equal), $(D overlap) only compares the pointers in the ranges, not the
values referred by them. If $(D r1) and $(D r2) have an overlapping
slice, returns that slice. Otherwise, returns the null slice.

Example:
----
int[] a = [ 10, 11, 12, 13, 14 ];
int[] b = a[1 .. 3];
assert(overlap(a, b) == [ 11, 12 ]);
b = b.dup;
// overlap disappears even though the content is the same
assert(isEmpty(overlap(a, b)));
----
*/
T[] overlap(T)(T[] r1, T[] r2)
{
    auto b = max(r1.ptr, r2.ptr);
    auto e = min(&(r1.ptr[r1.length - 1]) + 1, &(r2.ptr[r2.length - 1]) + 1);
    return b < e ? b[0 .. e - b] : null;
}

unittest
{
    int[] a = [ 10, 11, 12, 13, 14 ];
    int[] b = a[1 .. 3];
    a[1] = 100;
    assert(overlap(a, b) == [ 100, 12 ]);
}

/**
Inserts $(D stuff) in $(D container) at position $(D pos).
 */
void insert(T, Range)(ref T[] array, size_t pos, Range stuff)
{
    static if (is(typeof(stuff[0])))
    {
        // presumably an array
        alias stuff toInsert;
        //assert(!overlap(array, toInsert));
    }
    else
    {
        // presumably only one element
        auto toInsert = (&stuff)[0 .. 1];
    }

    // @@@BUG 2130@@@
    // invariant
    //     size_t delta = toInsert.length,
    //     size_t oldLength = array.length,
    //     size_t newLength = oldLength + delta;
    invariant
        delta = toInsert.length,
        oldLength = array.length,
        newLength = oldLength + delta;

    // Reallocate the array to make space for new content
    array = (cast(T*) core.memory.GC.realloc(array.ptr,
                    newLength * array[0].sizeof))[0 .. newLength];
    assert(array.length == newLength);

    // Move data in pos .. pos + stuff.length to the end of the array
    foreach_reverse (i; pos .. oldLength)
    {
        // This will be guaranteed to not throw
        move(array[i], array[i + delta]);
    }

    // Copy stuff into array
    foreach (e; toInsert)
    {
        array[pos++] = e;
    }
}

unittest
{
    int[] a = ([1, 4, 5]).dup;
    insert(a, 1u, [2, 3]);
    assert(a == [1, 2, 3, 4, 5]);
    insert(a, 1u, 99);
    assert(a == [1, 99, 2, 3, 4, 5]);
}

// @@@ TODO: document this
bool sameHead(T)(in T[] lhs, in T[] rhs)
{
    return lhs.ptr == rhs.ptr;
}

/**
Erases elements from $(D array) with indices ranging from $(D from)
(inclusive) to $(D to) (exclusive).
 */
// void erase(T)(ref T[] array, size_t from, size_t to)
// {
//     invariant newLength = array.length - (to - from);
//     foreach (i; to .. array.length)
//     {
//         move(array[i], array[from++]);
//     }
//     array.length = newLength;
// }

// unittest
// {
//     int[] a = [1, 2, 3, 4, 5];
//     erase(a, 1u, 3u);
//     assert(a == [1, 4, 5]);
// }

/**
Erases element from $(D array) at index $(D from).
 */
// void erase(T)(ref T[] array, size_t from)
// {
//     erase(array, from, from + 1);
// }

// unittest
// {
//     int[] a = [1, 2, 3, 4, 5];
//     erase(a, 2u);
//     assert(a == [1, 2, 4, 5]);
// }

/**
Replaces elements from $(D array) with indices ranging from $(D from)
(inclusive) to $(D to) (exclusive) with the range $(D stuff). Expands
or shrinks the array as needed.
 */
void replace(T, Range)(ref T[] array, size_t from, size_t to,
        Range stuff)
{
    // container = container[0 .. from] ~ stuff ~ container[to .. $];
    if (overlap(array, stuff))
    {
        // use slower/conservative method
        array = array[0 .. from] ~ stuff ~ array[to .. $];
    }
    else if (stuff.length <= to - from)
    {
        // replacement reduces length
        // BUG 2128
        //invariant stuffEnd = from + stuff.length;
        auto stuffEnd = from + stuff.length;
        array[from .. stuffEnd] = stuff;
        remove(array, tuple(stuffEnd, to));
    }
    else
    {
        // replacement increases length
        // @@@TODO@@@: optimize this
        invariant replaceLen = to - from;
        array[from .. to] = stuff[0 .. replaceLen];
        insert(array, to, stuff[replaceLen .. $]);
    }
}

unittest
{
    int[] a = [1, 4, 5];
    replace(a, 1u, 2u, [2, 3, 4]);
    assert(a == [1, 2, 3, 4, 5]);
}

/**
Implements an output range that appends data to an array. This is
recommended over $(D a ~= data) because it is more efficient.

Example:
----
string arr;
auto app = appender(&arr);
string b = "abcdefg";
foreach (char c; b) app.put(c);
assert(app.data == "abcdefg");

int[] a = [ 1, 2 ];
auto app2 = appender(&a);
app2.put(3);
app2.put([ 4, 5, 6 ]);
assert(app2.data == [ 1, 2, 3, 4, 5, 6 ]);
----
 */

struct Appender(A : T[], T)
{
private:
    Unqual!(T)[] * pArray;
    size_t _capacity;

public:
/**
Initialize an $(D Appender) with a pointer to an existing array. The
$(D Appender) object will append to this array. If $(D null) is passed
(or the default constructor gets called), the $(D Appender) object
will allocate and use a new array.
 */
    this(T[] * p)
    {
        pArray = cast(Unqual!(T)[] *) p;
        if (!pArray) pArray = (new typeof(*pArray)[1]).ptr;
        _capacity = GC.sizeOf(pArray.ptr) / T.sizeof;
    }

/**
Returns the managed array.
 */ 
    T[] data()
    {
        return cast(typeof(return)) (pArray ? *pArray : null);
    }

/**
Returns the capacity of the array (the maximum number of elements the
managed array can accommodate before triggering a reallocation).
 */ 
    size_t capacity() const { return _capacity; }
    
/**
Appends one item to the managed array.
 */ 
    void put(U)(U item) if (isImplicitlyConvertible!(U, T) ||
            isSomeString!(T[]) && isSomeString!(U[]))
    {
        static if (isSomeString!(T[]) && T.sizeof != U.sizeof)
        {
            // must do some transcoding around here
            encode!(T)(item, this);
        }
        else
        {
            if (!pArray) pArray = (new typeof(*pArray)[1]).ptr;
            if (pArray.length < _capacity)
            {
                // Should do in-place construction here
                pArray.ptr[pArray.length] = item;
                *pArray = pArray.ptr[0 .. pArray.length + 1];
            }
            else
            {
                // Time to reallocate, do it and cache capacity
                *pArray ~= item;
                _capacity = GC.sizeOf(pArray.ptr) / T.sizeof;
            }
        }
    }

/**
Appends an entire range to the managed array.
 */ 
    void put(Range)(Range items) if (isForwardRange!Range
            && is(typeof(Appender.init.put(ElementType!(Range).init))))
    {
        // @@@ UNCOMMENT WHEN BUG 2912 IS FIXED @@@
        // static if (is(typeof(*cast(T[]*) pArray ~= items)))
        // {
        //     if (!pArray) pArray = (new typeof(*pArray)[1]).ptr;
        //     *pArray ~= items;
        // }
        // else
        // {
        //     // Generic input range
        //     for (; !items.empty; items.popFront)
        //     {
        //         put(items.front());
        //     }
        // }

        // @@@ Doctored version taking BUG 2912 into account @@@
        static if (is(typeof(*cast(T[]*) pArray ~= items)) &&
                T.sizeof == ElementType!Range.sizeof)
        {
            if (!pArray) pArray = (new typeof(*pArray)[1]).ptr;
            *pArray ~= items;
        }
        else
        {
            // Generic input range
            foreach (e; items) put(e);
        }
    }

/**
Clears the managed array.
*/
    void clear()
    {
        if (!pArray) return;
        pArray.length = 0;
        //_capacity = .capacity(pArray.ptr) / T.sizeof;
        _capacity = GC.sizeOf(pArray.ptr) / T.sizeof;
    }
}

/**
Convenience function that returns an $(D Appender!(T)) object
initialized with $(D t).
 */ 
Appender!(E[]) appender(A : E[], E)(A * array = null)
{
    return Appender!(E[])(array);
}

unittest
{
    auto arr = new char[0];
    auto app = appender(&arr);
    string b = "abcdefg";
    foreach (char c; b) app.put(c);
    assert(app.data == "abcdefg");

    int[] a = [ 1, 2 ];
    auto app2 = appender(&a);
    app2.put(3);
    app2.put([ 4, 5, 6 ][]);
    assert(app2.data == [ 1, 2, 3, 4, 5, 6 ]);
}

/*
A simple slice type only holding pointers to the beginning and the end
of an array. Experimental duplication of the built-in slice - do not
use yet.
 */
struct SimpleSlice(T)
{
    private T * _b, _e;

    this(U...)(U values)
    {
        _b = cast(T*) core.memory.GC.malloc(U.length * T.sizeof);
        _e = _b + U.length;
        foreach (i, Unused; U) _b[i] = values[i];
    }

    void opAssign(R)(R anotherSlice)
    {
        static if (is(typeof(*_b = anotherSlice)))
        {
            // assign all elements to a value
            foreach (p; _b .. _e)
            {
                *p = anotherSlice;
            }
        }
        else
        {
            // assign another slice to this
            enforce(anotherSlice.length == length);
            auto p = _b;
            foreach (p; _b .. _e)
            {
                *p = anotherSlice.front;
                anotherSlice.popFront;
            }
        }
    }

/**
   Range primitives.
 */
    bool empty() const
    {
        assert(_b <= _e);
        return _b == _e;
    }

/// Ditto
    ref T front()
    {
        assert(!empty);
        return *_b;
    }

/// Ditto
    void popFront()
    {
        assert(!empty);
        ++_b;
    }

/// Ditto
    ref T back()
    {
        assert(!empty);
        return _e[-1];
    }

/// Ditto
    void popBack()
    {
        assert(!empty);
        --_e;
    }

/// Ditto
    T opIndex(size_t n)
    {
        assert(n < length);
        return _b[n];
    }

/// Ditto
    const(T) opIndex(size_t n) const
    {
        assert(n < length);
        return _b[n];
    }

/// Ditto
    void opIndexAssign(T value, size_t n)
    {
        assert(n < length);
        _b[n] = value;
    }

/// Ditto
    SimpleSliceLvalue!T opSlice()
    {
        typeof(return) result = void;
        result._b = _b;
        result._e = _e;
        return result;
    }

/// Ditto
    SimpleSliceLvalue!T opSlice(size_t x, size_t y)
    {
        enforce(x <= y && y <= length);
        typeof(return) result = { _b + x, _b + y };
        return result;
    }

/// Returns the length of the slice.
    size_t length() const
    {
        return _e - _b;
    }

/**
Sets the length of the slice. Newly added elements will be filled with
$(D T.init).
 */
    void length(size_t newLength)
    {
        immutable oldLength = length;
        _b = cast(T*) core.memory.GC.realloc(_b, newLength * T.sizeof);
        _e = _b + newLength;
        this[oldLength .. length] = T.init;
    }

/// Concatenation.
    SimpleSlice opCat(R)(R another)
    {
        immutable newLen = length + another.length;
        typeof(return) result = void;
        result._b = cast(T*)
            core.memory.GC.malloc(newLen * T.sizeof);
        result._e = result._b + newLen;
        result[0 .. this.length] = this;
        result[this.length .. result.length] = another;
        return result;
    }

/// Concatenation with rebinding.
    void opCatAssign(R)(R another)
    {
        auto newThis = this ~ another;
        move(newThis, this);
    }
}

// Support for mass assignment
struct SimpleSliceLvalue(T)
{
    private SimpleSlice!T _s;
    alias _s this;

    void opAssign(R)(R anotherSlice)
    {
        static if (is(typeof(*_b = anotherSlice)))
        {
            // assign all elements to a value
            foreach (p; _b .. _e)
            {
                *p = anotherSlice;
            }
        }
        else
        {
            // assign another slice to this
            enforce(anotherSlice.length == length);
            auto p = _b;
            foreach (p; _b .. _e)
            {
                *p = anotherSlice.front;
                anotherSlice.popFront;
            }
        }
    }
}

unittest
{
    // SimpleSlice!(int) s;

    // s = SimpleSlice!(int)(4, 5, 6);
    // assert(equal(s, [4, 5, 6][]));
    // assert(s.length == 3);
    // assert(s[0] == 4);
    // assert(s[1] == 5);
    // assert(s[2] == 6);
    
    // assert(s[] == s);
    // assert(s[0 .. s.length] == s);
    // assert(equal(s[0 .. s.length - 1], [4, 5][]));

    // auto s1 = s ~ s[0 .. 1];
    // assert(equal(s1, [4, 5, 6, 4][]));

    // assert(s1[3] == 4);
    // s1[3] = 42;
    // assert(s1[3] == 42);

    // const s2 = s;
    // assert(s2.length == 3);
    // assert(!s2.empty);
    // assert(s2[0] == s[0]);

    // s[0 .. 2] = 10;
    // assert(equal(s, [10, 10, 6][]));

    // s ~= [ 5, 9 ][];
    // assert(equal(s, [10, 10, 6, 5, 9][]));

    // s.length = 7;
    // assert(equal(s, [10, 10, 6, 5, 9, 0, 0][]));
}

/*
 *  Copyright (C) 2004-2009 by Digital Mars, www.digitalmars.com
 *  Written by Andrei Alexandrescu, www.erdani.org
 *
 *  This software is provided 'as-is', without any express or implied
 *  warranty. In no event will the authors be held liable for any damages
 *  arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute it
 *  freely, subject to the following restrictions:
 *
 *  o  The origin of this software must not be misrepresented; you must not
 *     claim that you wrote the original software. If you use this software
 *     in a product, an acknowledgment in the product documentation would be
 *     appreciated but is not required.
 *  o  Altered source versions must be plainly marked as such, and must not
 *     be misrepresented as being the original software.
 *  o  This notice may not be removed or altered from any source
 *     distribution.
 */
