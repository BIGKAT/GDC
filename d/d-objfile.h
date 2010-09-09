/* GDC -- D front-end for GCC
   Copyright (C) 2004 David Friedman

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

#ifndef GCC_DCMPLR_OBFILE_H
#define GCC_DCMPLR_OBFILE_H

struct ModuleInfo {
    Array classes; // Array of ClassDeclaration*
    Array ctors; // Arrays of FuncDeclaration*
    Array dtors;
    Array unitTests;
};

typedef enum {
    TEnone,
    TEnormal,
    TEall,
    TEprivate,
    TEauto
} TemplateEmission;

/* nearly everything is static for effeciency since there is
   only one object per run of the backend */
struct ObjectFile {
    static ModuleInfo * moduleInfo; // of ModuleInfo*

    ObjectFile(); // constructor is *NOT* static

    static void beginModule(Module * m);
    static void endModule();

    static void finish();

    /* support for multiple modules per object file */
    static Array modules;
    static bool hasModule(Module *m);
private:
    static unsigned moduleSearchIndex;
public:

    static void doLineNote(const Loc & loc);
    static void setLoc(const Loc & loc);

    // ** Declaration maninpulation
    static void setDeclLoc(tree t, const Loc & loc);

    // Some DMD Declarations don't have the loc set, this searches decl's parents
    // until a valid loc is found.
    static void setDeclLoc(tree t, Dsymbol * decl);

#if D_GCC_VER >= 40
    static void setCfunEndLoc(const Loc & loc);
#endif

    static void giveDeclUniqueName(tree decl, const char * prefix = NULL);
public:
    // Set a DECL's STATIC and EXTERN based on the decl's storage class
    // and if it is to be emitted in this module.
    static void setupSymbolStorage(Dsymbol * decl, tree decl_tree, bool force_static_public = false);

    // Definitely in static data, but not neccessarily this module.
    // Assumed to be public data.
    static void setupStaticStorage(Dsymbol * dsym, tree decl_tree);
    static void makeDeclOneOnly(tree decl_tree, Dsymbol * dsym = NULL);

    static void outputStaticSymbol(tree t);
    static void outputFunction(FuncDeclaration * f);

    static void addAggMethods(tree rec_type, AggregateDeclaration * agg);

    static void initTypeDecl(tree t, Dsymbol * d_sym);

    static void declareType(tree t, Type * d_type);
    static void declareType(tree t, Dsymbol * d_sym);

protected:
    static void initTypeDecl(tree t, tree decl);
    static void declareType(tree t, tree decl);
public:

    // Hack for systems without linkonce support
    static bool shouldEmit(Dsymbol * d_sym);
    static bool shouldEmit(Symbol * sym);

    static void doThunk(tree thunk_decl, tree target_decl, target_ptrdiff_t offset);
protected:
    // Can't output thunks while a function is being compiled.
    static Array deferredThunks;
    static void outputThunk(tree thunk_decl, tree target_decl, target_ptrdiff_t offset);
public:

    // Can't use VAR_DECLs for the DECL_INITIAL of static varibles or in CONSTRUCTORSs
    static tree stripVarDecl(tree value);

    static FuncDeclaration * doSimpleFunction(const char * name, tree expr, bool static_ctor, bool public_fn = false);
    static FuncDeclaration * doFunctionToCallFunctions(const char * name, Array * functions, bool force_and_public = false);

    // ** Module info.  Assuming only one module per run of the compiler.

    // ** static constructors (not D static constructors)
    static Array staticCtorList; // of FuncDeclaration*. usually only one.
    static Array staticDtorList; // of FuncDeclaration*. only if __attribute__(destructor) is used.

    static void rodc(tree decl, int top_level)
    {
#if D_GCC_VER < 40
	rest_of_decl_compilation(decl, NULL, top_level, 0);
#else
	rest_of_decl_compilation(decl, top_level, 0);
#endif
    }
};

#endif

