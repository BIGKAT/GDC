/**
 * Part of the D programming language runtime library.
 */

/*
 *  Copyright (C) 2004-2007 by Digital Mars, www.digitalmars.com
 *  Written by Walter Bright
 *
 *  This software is provided 'as-is', without any express or implied
 *  warranty. In no event will the authors be held liable for any damages
 *  arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute it
 *  freely, in both source and binary form, subject to the following
 *  restrictions:
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

/* NOTE: This file has been patched from the original DMD distribution to
   work with the GDC compiler.

   Modified by David Friedman, November 2006
*/
 
module arraycat;

import object;
import std.string;
import std.c.string;

extern (C)
void[] _d_arraycopy(size_t size, void[] from, void[] to)
{
    //printf("f = %p,%d, t = %p,%d, size = %d\n", from.ptr, from.length, to.ptr, to.length, size);

    if (to.length != from.length)
    {
	//throw new Error(std.string.format("lengths don't match for array copy, %s = %s", to.length, from.length));
	throw new Error(cast(string) ("lengths don't match for array copy," ~
                                      toString(to.length) ~ " = "
                                      ~ toString(from.length)));
    }
    else if (to.ptr + to.length * size <= from.ptr ||
	from.ptr + from.length * size <= to.ptr)
    {
	memcpy(to.ptr, from.ptr, to.length * size);
    }
    else
    {
	throw new Error("overlapping array copy");
	//memmove(to.ptr, from.ptr, to.length * size);
    }
    return to;
}

