
// Compiler implementation of the D programming language
// Copyright (c) 1999-2009 by Digital Mars
// All Rights Reserved
// written by Walter Bright
// http://www.digitalmars.com
// License for redistribution is by either the Artistic License
// in artistic.txt, or the GNU General Public License in gnu.txt.
// See the included readme.txt for details.

/* NOTE: This file has been patched from the original DMD distribution to
   work with the GDC compiler.

   Modified by David Friedman, July 2007
*/

/* A dt_t is a simple structure representing data to be added
 * to the data segment of the output object file. As such,
 * it is a list of initialized bytes, 0 data, and offsets from
 * other symbols.
 * Each D symbol and type can be converted into a dt_t so it can
 * be written to the data segment.
 */

#undef integer_t
#include        <stdio.h>
#include        <string.h>
#include        <time.h>
#include        <assert.h>
#include        <complex.h>

#ifdef __APPLE__
#define integer_t dmd_integer_t
#endif

#include        "lexer.h"
#include        "mtype.h"
#include        "expression.h"
#include        "init.h"
#include        "enum.h"
#include        "aggregate.h"
#include        "declaration.h"


// Back end
#ifndef IN_GCC
#include        "cc.h"
#include        "el.h"
#include        "oper.h"
#include        "global.h"
#include        "code.h"
#include        "type.h"
#endif
#include        "dt.h"

extern Symbol *static_sym();

/* ================================================================ */

#ifdef IN_GCC
static dt_t *createTsarrayDt(dt_t * elem_or_all, Type *t)
{
    assert(elem_or_all != NULL);
    target_size_t eoa_size = dt_size(elem_or_all);
    if (eoa_size == t->size())
    {
        return elem_or_all;
    }
    else
    {
        TypeSArray * tsa = (TypeSArray *) t->toBasetype();
        assert(tsa->ty == Tsarray);

        target_size_t dim = tsa->dim->toInteger();
        dt_t * adt = NULL;
        dt_t ** padt = & adt;

        if (eoa_size * dim == eoa_size)
        {
            for (target_size_t i = 0; i < dim; i++)
                padt = dtcontainer(padt, NULL, elem_or_all);
        }
        else
        {
            assert(tsa->size(0) % eoa_size == 0);
            for (target_size_t i = 0; i < dim; i++)
                padt = dtcontainer(padt, NULL,
                    createTsarrayDt(elem_or_all, tsa->next));
        }
        dt_t * fdt = NULL;
        dtcontainer(& fdt, t, adt);
        return fdt;
    }
}
#endif


dt_t *Initializer::toDt()
{
    assert(0);
    return NULL;
}


dt_t *VoidInitializer::toDt()
{   /* Void initializers are set to 0, just because we need something
     * to set them to in the static data segment.
     */
    dt_t *dt = NULL;

    dtnzeros(&dt, type->size());
    return dt;
}


dt_t *StructInitializer::toDt()
{
    Array dts;
    unsigned i;
    unsigned j;
    dt_t *dt;
    dt_t *d;
    dt_t **pdtend;
    target_size_t offset;

    //printf("StructInitializer::toDt('%s')\n", toChars());
    dts.setDim(ad->fields.dim);
    dts.zero();

    for (i = 0; i < vars.dim; i++)
    {
        VarDeclaration *v = (VarDeclaration *)vars.data[i];
        Initializer *val = (Initializer *)value.data[i];

        //printf("vars[%d] = %s\n", i, v->toChars());

        for (j = 0; 1; j++)
        {
            assert(j < dts.dim);
            //printf(" adfield[%d] = %s\n", j, ((VarDeclaration *)ad->fields.data[j])->toChars());
            if ((VarDeclaration *)ad->fields.data[j] == v)
            {
                if (dts.data[j])
                    error(loc, "field %s of %s already initialized", v->toChars(), ad->toChars());
                dts.data[j] = (void *)val->toDt();
                break;
            }
        }
    }

    dt = NULL;
    pdtend = &dt;
    offset = 0;
    for (j = 0; j < dts.dim; j++)
    {
        VarDeclaration *v = (VarDeclaration *)ad->fields.data[j];

        d = (dt_t *)dts.data[j];
        if (!d)
        {   // An instance specific initializer was not provided.
            // Look to see if there's a default initializer from the
            // struct definition
            VarDeclaration *v = (VarDeclaration *)ad->fields.data[j];

            if (v->init)
            {
                d = v->init->toDt();
            }
            else if (v->offset >= offset)
            {
                target_size_t k;
                target_size_t offset2 = v->offset + v->type->size();
                // Make sure this field does not overlap any explicitly
                // initialized field.
                for (k = j + 1; 1; k++)
                {
                    if (k == dts.dim)           // didn't find any overlap
                    {
                        v->type->toDt(&d);
                        break;
                    }
                    VarDeclaration *v2 = (VarDeclaration *)ad->fields.data[k];

                    if (v2->offset < offset2 && dts.data[k])
                        break;                  // overlap
                }
            }
        }
        if (d)
        {
            if (v->offset < offset)
                error(loc, "duplicate union initialization for %s", v->toChars());
            else
            {   target_size_t sz = dt_size(d);
                target_size_t vsz = v->type->size();
                target_size_t voffset = v->offset;

#ifdef IN_GCC
                if (offset < voffset)
                    pdtend = dtnzeros(pdtend, voffset - offset);
                if (v->type->toBasetype()->ty == Tsarray)
                {
                    d = createTsarrayDt(d, v->type);
                    sz = dt_size(d);
                    assert(sz <= vsz);
                }
                pdtend = dtcat(pdtend, d);
                offset = voffset + sz;
#else
                target_size_t dim = 1;
                for (Type *vt = v->type->toBasetype();
                     vt->ty == Tsarray;
                     vt = vt->next->toBasetype())
                {   TypeSArray *tsa = (TypeSArray *)vt;
                    dim *= tsa->dim->toInteger();
                }
                //printf("sz = %d, dim = %d, vsz = %d\n", sz, dim, vsz);
                assert(sz == vsz || sz * dim <= vsz);

                for (target_size_t i = 0; i < dim; i++)
                {
                    if (offset < voffset)
                        pdtend = dtnzeros(pdtend, voffset - offset);
                    if (!d)
                    {
                        if (v->init)
                            d = v->init->toDt();
                        else
                            v->type->toDt(&d);
                    }
                    pdtend = dtcat(pdtend, d);
                    d = NULL;
                    offset = voffset + sz;
                    voffset += vsz / dim;
                    if (sz == vsz)
                        break;
                }
#endif
            }
        }
    }
    if (offset < ad->structsize)
        dtnzeros(pdtend, ad->structsize - offset);

#ifdef IN_GCC
    dt_t * cdt = NULL;
    dtcontainer(& cdt, ad->type, dt);
    dt = cdt;
#endif
    return dt;
}


dt_t *ArrayInitializer::toDt()
{
    //printf("ArrayInitializer::toDt('%s')\n", toChars());
    Type *tb = type->toBasetype();
    Type *tn = tb->next->toBasetype();

    if (tn->ty == Tbit)
        return toDtBit();

    Array dts;
    unsigned size;
    unsigned length;
    unsigned i;
    dt_t *dt;
    dt_t *d;
    dt_t **pdtend;

    //printf("\tdim = %d\n", dim);
    dts.setDim(dim);
    dts.zero();

    size = tn->size();

    length = 0;
    for (i = 0; i < index.dim; i++)
    {   Expression *idx;
        Initializer *val;

        idx = (Expression *)index.data[i];
        if (idx)
            length = idx->toInteger();
        //printf("\tindex[%d] = %p, length = %u, dim = %u\n", i, idx, length, dim);

        assert(length < dim);
        val = (Initializer *)value.data[i];
        dt = val->toDt();
        if (dts.data[length])
            error(loc, "duplicate initializations for index %d", length);
        if (tn->ty == Tsarray)
            dt = createTsarrayDt(dt, tb->next);
        dts.data[length] = (void *)dt;
        length++;
    }

    Expression *edefault = tb->next->defaultInit();
#ifdef IN_GCC
    dt_t * sadefault = NULL;

    if (tn->ty == Tsarray)
        tn->toDt(& sadefault);
    else
        edefault->toDt(& sadefault);
#else
    unsigned n = 1;
    for (Type *tbn = tn; tbn->ty == Tsarray; tbn = tbn->next->toBasetype())
    {   TypeSArray *tsa = (TypeSArray *)tbn;

        n *= tsa->dim->toInteger();
    }
#endif

    d = NULL;
    pdtend = &d;
    for (i = 0; i < dim; i++)
    {
        dt = (dt_t *)dts.data[i];
#ifdef IN_GCC
        pdtend = dtcontainer(pdtend, NULL, dt ? dt : sadefault);
#else
        if (dt)
            pdtend = dtcat(pdtend, dt);
        else
        {
            for (int j = 0; j < n; j++)
                pdtend = edefault->toDt(pdtend);
        }
#endif
    }
    switch (tb->ty)
    {
        case Tsarray:
        {   unsigned tadim;
            TypeSArray *ta = (TypeSArray *)tb;

            tadim = ta->dim->toInteger();
            if (dim < tadim)
            {
                if (edefault->isBool(FALSE))
                    // pad out end of array
                    // (ok for GDC as well)
                    pdtend = dtnzeros(pdtend, size * (tadim - dim));
                else
                {
                    for (i = dim; i < tadim; i++)
#ifdef IN_GCC
                        pdtend = dtcontainer(pdtend, NULL, sadefault);
#else
                    {   for (int j = 0; j < n; j++)
                            pdtend = edefault->toDt(pdtend);
                    }
#endif
                }
            }
            else if (dim > tadim)
            {
#ifdef DEBUG
                printf("1: ");
#endif
                error(loc, "too many initializers, %d, for array[%d]", dim, tadim);
            }
#ifdef IN_GCC
            dt_t * cdt = NULL;
            dtcontainer(& cdt, type, d);
            d = cdt;
#endif
            break;
        }

        case Tpointer:
        case Tarray:
            // Create symbol, and then refer to it
            Symbol *s;
            s = static_sym();
            s->Sdt = d;
            outdata(s);

            d = NULL;
            if (tb->ty == Tarray)
                dtdword(&d, dim);
            dtxoff(&d, s, 0, TYnptr);
#ifdef IN_GCC
            dt_t * cdt;
            cdt = NULL;
            if (tb->ty == Tarray)
            {
                dtcontainer(& cdt, type, d);
                d = cdt;
            }
#endif
            break;

        default:
            assert(0);
    }
    return d;
}


dt_t *ArrayInitializer::toDtBit()
{
#if DMDV1
    unsigned size;
    unsigned length;
    unsigned i;
    unsigned tadim;
    dt_t *d;
    dt_t **pdtend;
    Type *tb = type->toBasetype();

    Bits databits;
    Bits initbits;

    if (tb->ty == Tsarray)
    {
        /* The 'dim' for ArrayInitializer is only the maximum dimension
         * seen in the initializer, not the type. So, for static arrays,
         * use instead the dimension of the type in order
         * to get the whole thing.
         */
        dinteger_t value = ((TypeSArray*)tb)->dim->toInteger();
        tadim = value;
        assert(tadim == value);  // truncation overflow should already be checked
        databits.resize(tadim);
        initbits.resize(tadim);
    }
    else
    {
        databits.resize(dim);
        initbits.resize(dim);
    }

    /* The default initializer may be something other than zero.
     */
    if (tb->next->defaultInit()->toInteger())
       databits.set();

    size = sizeof(databits.data[0]);

    length = 0;
    for (i = 0; i < index.dim; i++)
    {   Expression *idx;
        Initializer *val;
        Expression *eval;

        idx = (Expression *)index.data[i];
        if (idx)
        {   dinteger_t value;
            value = idx->toInteger();
            length = value;
            if (length != value)
            {   error(loc, "index overflow %llu", value);
                length = 0;
            }
        }
        assert(length < dim);

        val = (Initializer *)value.data[i];
        eval = val->toExpression();
        if (initbits.test(length))
            error(loc, "duplicate initializations for index %d", length);
        initbits.set(length);
        if (eval->toInteger())          // any non-zero value is boolean 'true'
            databits.set(length);
        else
            databits.clear(length);     // boolean 'false'
        length++;
    }

    d = NULL;
#ifdef IN_GCC
    pdtend = dtnbits(&d, databits.allocdim * size, (char *)databits.data, sizeof(databits.data[0]));
#else
    pdtend = dtnbytes(&d, databits.allocdim * size, (char *)databits.data);
#endif
    switch (tb->ty)
    {
        case Tsarray:
        {
            if (dim > tadim)
            {
#ifdef DEBUG
                printf("2: ");
#endif
                error(loc, "too many initializers, %d, for array[%d]", dim, tadim);
            }
            else
            {
                tadim = (tadim + 31) / 32;
                if (databits.allocdim < tadim)
                    pdtend = dtnzeros(pdtend, size * (tadim - databits.allocdim));      // pad out end of array
            }
            break;
        }

        case Tpointer:
        case Tarray:
            // Create symbol, and then refer to it
            Symbol *s;
            s = static_sym();
            s->Sdt = d;
            outdata(s);

            d = NULL;
            if (tb->ty == Tarray)
                dtdword(&d, dim);
            dtxoff(&d, s, 0, TYnptr);
            break;

        default:
            assert(0);
    }
    return d;
#else
    return NULL;
#endif
}


dt_t *ExpInitializer::toDt()
{
    dt_t *dt = NULL;

    exp = exp->optimize(WANTvalue);
    exp->toDt(&dt);
    return dt;
}

/* ================================================================ */

dt_t **Expression::toDt(dt_t **pdt)
{
#ifdef DEBUG
    printf("Expression::toDt() %d\n", op);
    dump(0);
#endif
    error("non-constant expression %s", toChars());
    pdt = dtnzeros(pdt, 1);
    return pdt;
}

#ifndef IN_GCC

dt_t **IntegerExp::toDt(dt_t **pdt)
{   unsigned sz;

    //printf("IntegerExp::toDt() %d\n", op);
    sz = type->size();
    if (value == 0)
        pdt = dtnzeros(pdt, sz);
    else
        pdt = dtnbytes(pdt, sz, (char *)&value);
    return pdt;
}

static char zeropad[6];

dt_t **RealExp::toDt(dt_t **pdt)
{
    d_float32 fvalue;
    d_float64 dvalue;
    d_float80 evalue;

    //printf("RealExp::toDt(%Lg)\n", value);
    switch (type->toBasetype()->ty)
    {
        case Tfloat32:
        case Timaginary32:
            fvalue = value;
            pdt = dtnbytes(pdt,4,(char *)&fvalue);
            break;

        case Tfloat64:
        case Timaginary64:
            dvalue = value;
            pdt = dtnbytes(pdt,8,(char *)&dvalue);
            break;

        case Tfloat80:
        case Timaginary80:
            evalue = value;
            pdt = dtnbytes(pdt,REALSIZE - REALPAD,(char *)&evalue);
            pdt = dtnbytes(pdt,REALPAD,zeropad);
            assert(REALPAD <= sizeof(zeropad));
            break;

        default:
            fprintf(stderr, "%s\n", toChars());
            type->print();
            assert(0);
            break;
    }
    return pdt;
}

dt_t **ComplexExp::toDt(dt_t **pdt)
{
    //printf("ComplexExp::toDt() '%s'\n", toChars());
    d_float32 fvalue;
    d_float64 dvalue;
    d_float80 evalue;

    switch (type->toBasetype()->ty)
    {
        case Tcomplex32:
            fvalue = creall(value);
            pdt = dtnbytes(pdt,4,(char *)&fvalue);
            fvalue = cimagl(value);
            pdt = dtnbytes(pdt,4,(char *)&fvalue);
            break;

        case Tcomplex64:
            dvalue = creall(value);
            pdt = dtnbytes(pdt,8,(char *)&dvalue);
            dvalue = cimagl(value);
            pdt = dtnbytes(pdt,8,(char *)&dvalue);
            break;

        case Tcomplex80:
            evalue = creall(value);
            pdt = dtnbytes(pdt,REALSIZE - REALPAD,(char *)&evalue);
            pdt = dtnbytes(pdt,REALPAD,zeropad);
            evalue = cimagl(value);
            pdt = dtnbytes(pdt,REALSIZE - REALPAD,(char *)&evalue);
            pdt = dtnbytes(pdt,REALPAD,zeropad);
            break;

        default:
            assert(0);
            break;
    }
    return pdt;
}


#endif

dt_t **NullExp::toDt(dt_t **pdt)
{
    assert(type);
    return dtnzeros(pdt, type->size());
}

dt_t **StringExp::toDt(dt_t **pdt)
{
    //printf("StringExp::toDt() '%s', type = %s\n", toChars(), type->toChars());
    Type *t = type->toBasetype();

    // BUG: should implement some form of static string pooling
    switch (t->ty)
    {
        case Tarray:
            dt_t * adt; adt = NULL;
            dtdword(& adt, len);
#ifndef IN_GCC
            dtabytes(& adt, TYnptr, 0, (len + 1) * sz, (char *)string);
            pdt = dcat(pdt, adt);
#else
            dtawords(& adt, len + 1, string, sz);
            pdt = dtcontainer(pdt, type, adt);
#endif
            break;

        case Tsarray:
        {   TypeSArray *tsa = (TypeSArray *)type;
            dinteger_t dim;

#ifndef IN_GCC
            pdt = dtnbytes(pdt, len * sz, (const char *)string);
#else
            pdt = dtnwords(pdt, len, string, sz);
#endif
            if (tsa->dim)
            {
                dim = tsa->dim->toInteger();
                if (len < dim)
                {
                    // Pad remainder with 0
                    pdt = dtnzeros(pdt, (dim - len) * tsa->next->size());
                }
            }
            break;
        }
        case Tpointer:
#ifndef IN_GCC
            pdt = dtabytes(pdt, TYnptr, 0, (len + 1) * sz, (char *)string);
#else
            pdt = dtawords(pdt, len + 1, string, sz);
#endif
            break;

        default:
            fprintf(stderr, "StringExp::toDt(type = %s)\n", type->toChars());
            assert(0);
    }
    return pdt;
}

dt_t **ArrayLiteralExp::toDt(dt_t **pdt)
{
    //printf("ArrayLiteralExp::toDt() '%s', type = %s\n", toChars(), type->toChars());

    dt_t *d;
    dt_t **pdtend;

    d = NULL;
    pdtend = &d;
    for (int i = 0; i < elements->dim; i++)
    {   Expression *e = (Expression *)elements->data[i];

        pdtend = e->toDt(pdtend);
    }
#ifdef IN_GCC
    dt_t * cdt = NULL;
    dtcontainer(& cdt, type, d);
    d = cdt;
#endif
    Type *t = type->toBasetype();

    switch (t->ty)
    {
        case Tsarray:
            pdt = dtcat(pdt, d);
            break;

        case Tpointer:
        case Tarray:
            dt_t * adt; adt = NULL;
            if (t->ty == Tarray)
                dtdword(& adt, elements->dim);
            if (d)
            {
                // Create symbol, and then refer to it
                Symbol *s;
                s = static_sym();
                s->Sdt = d;
                outdata(s);

                dtxoff(& adt, s, 0, TYnptr);
            }
            else
                dtdword(& adt, 0);
#ifdef IN_GCC
            if (t->ty == Tarray)
                dtcontainer(pdt, type, adt);
            else
#endif
                dtcat(pdt, adt);

            break;

        default:
            assert(0);
    }
    return pdt;
}

dt_t **StructLiteralExp::toDt(dt_t **pdt)
{
    Array dts;
    unsigned i;
    unsigned j;
    dt_t *dt;
    dt_t *d;
    dt_t *sdt = NULL;
    target_size_t offset;

    //printf("StructLiteralExp::toDt() %s)\n", toChars());
    dts.setDim(sd->fields.dim);
    dts.zero();
    assert(elements->dim <= sd->fields.dim);

    for (i = 0; i < elements->dim; i++)
    {
        Expression *e = (Expression *)elements->data[i];
        if (!e)
            continue;
        dt = NULL;
        e->toDt(&dt);
        dts.data[i] = (void *)dt;
    }

    offset = 0;
    for (j = 0; j < dts.dim; j++)
    {
        VarDeclaration *v = (VarDeclaration *)sd->fields.data[j];

        d = (dt_t *)dts.data[j];
        if (!d)
        {   // An instance specific initializer was not provided.
            // Look to see if there's a default initializer from the
            // struct definition
            VarDeclaration *v = (VarDeclaration *)sd->fields.data[j];

            if (v->init)
            {
                d = v->init->toDt();
            }
            else if (v->offset >= offset)
            {
                target_size_t k;
                target_size_t offset2 = v->offset + v->type->size();
                // Make sure this field (v) does not overlap any explicitly
                // initialized field.
                for (k = j + 1; 1; k++)
                {
                    if (k == dts.dim)           // didn't find any overlap
                    {
                        v->type->toDt(&d);
                        break;
                    }
                    VarDeclaration *v2 = (VarDeclaration *)sd->fields.data[k];

                    if (v2->offset < offset2 && dts.data[k])
                        break;                  // overlap
                }
            }
        }
        if (d)
        {
            if (v->offset < offset)
                error("duplicate union initialization for %s", v->toChars());
            else
            {   target_size_t sz = dt_size(d);
                target_size_t vsz = v->type->size();
                target_size_t voffset = v->offset;
                assert(sz <= vsz);

#ifdef IN_GCC
                if (offset < voffset)
                    dtnzeros(& sdt, voffset - offset);
                if (v->type->toBasetype()->ty == Tsarray)
                {
                    d = createTsarrayDt(d, v->type);
                    sz = dt_size(d);
                    assert(sz <= vsz);
                }
                dtcat(& sdt, d);
                offset = voffset + sz;
#else
                target_size_t dim = 1;
                for (Type *vt = v->type->toBasetype();
                     vt->ty == Tsarray;
                     vt = vt->next->toBasetype())
                {   TypeSArray *tsa = (TypeSArray *)vt;
                    dim *= tsa->dim->toInteger();
                }

                for (target_size_t i = 0; i < dim; i++)
                {
                    if (offset < voffset)
                        dtnzeros(& sdt, voffset - offset);
                    if (!d)
                    {
                        if (v->init)
                            d = v->init->toDt();
                        else
                            v->type->toDt(&d);
                    }
                    dtcat(& sdt, d);
                    d = NULL;
                    offset = voffset + sz;
                    voffset += vsz / dim;
                    if (sz == vsz)
                        break;
                }
#endif
            }
        }
    }
    if (offset < sd->structsize)
        dtnzeros(& sdt, sd->structsize - offset);
#ifdef IN_GCC
    dtcontainer(pdt, type, sdt);
#else
    pdt = dtcat(pdt, sdt);
#endif

    return pdt;
}


dt_t **SymOffExp::toDt(dt_t **pdt)
{
    Symbol *s;

    //printf("SymOffExp::toDt('%s')\n", var->toChars());
    assert(var);
    if (!(var->isDataseg() || var->isCodeseg()) || var->needThis())
    {
#ifdef DEBUG
        printf("SymOffExp::toDt()\n");
#endif
        error("non-constant expression %s", toChars());
        return pdt;
    }
    s = var->toSymbol();
    return dtxoff(pdt, s, offset, TYnptr);
}

dt_t **VarExp::toDt(dt_t **pdt)
{
    //printf("VarExp::toDt() %d\n", op);
    for (; *pdt; pdt = &((*pdt)->DTnext))
        ;

    VarDeclaration *v = var->isVarDeclaration();
    if (v && v->isConst() && type->toBasetype()->ty != Tsarray && v->init)
    {
    if (v->inuse)
        {
            error("recursive reference %s", toChars());
            return pdt;
        }
        v->inuse++;
        *pdt = v->init->toDt();
        v->inuse--;
        return pdt;
    }
    SymbolDeclaration *sd = var->isSymbolDeclaration();
    if (sd && sd->dsym)
    {
        sd->dsym->toDt(pdt);
        return pdt;
    }
#ifdef DEBUG
    printf("VarExp::toDt(), kind = %s\n", var->kind());
#endif
    error("non-constant expression %s", toChars());
    pdt = dtnzeros(pdt, 1);
    return pdt;
}

/* ================================================================= */

// Generate the data for the static initializer.

void ClassDeclaration::toDt(dt_t **pdt)
{
    //printf("ClassDeclaration::toDt(this = '%s')\n", toChars());

    // Put in first two members, the vtbl[] and the monitor
    dtxoff(pdt, toVtblSymbol(), 0, TYnptr);
    dtdword(pdt, 0);                    // monitor

    // Put in the rest
    toDt2(pdt, this);

    //printf("-ClassDeclaration::toDt(this = '%s')\n", toChars());
}

void ClassDeclaration::toDt2(dt_t **pdt, ClassDeclaration *cd)
{
    unsigned offset;
    unsigned i;
    dt_t *dt;
    unsigned csymoffset;

#define LOG 0

#if LOG
    printf("ClassDeclaration::toDt2(this = '%s', cd = '%s')\n", toChars(), cd->toChars());
#endif
    if (baseClass)
    {
        baseClass->toDt2(pdt, cd);
        offset = baseClass->structsize;
    }
    else
    {
        offset = PTRSIZE * 2;
    }

    // Note equivalence of this loop to struct's
    for (i = 0; i < fields.dim; i++)
    {
        VarDeclaration *v = (VarDeclaration *)fields.data[i];
        Initializer *init;

        //printf("\t\tv = '%s' v->offset = %2d, offset = %2d\n", v->toChars(), v->offset, offset);
        dt = NULL;
        init = v->init;
        if (init)
        {   //printf("\t\t%s has initializer %s\n", v->toChars(), init->toChars());
            ExpInitializer *ei = init->isExpInitializer();
            Type *tb = v->type->toBasetype();
            if (ei && tb->ty == Tsarray)
            {
#ifdef IN_GCC
                dt = init->toDt();
                dt = createTsarrayDt(dt, v->type);
#else
                ((TypeSArray *)tb)->toDtElem(&dt, ei->exp);
#endif
            }
            else
                dt = init->toDt();
        }
        else if (v->offset >= offset)
        {   //printf("\t\tdefault initializer\n");
            v->type->toDt(&dt);
        }
        if (dt)
        {
            if (v->offset < offset)
                error("duplicated union initialization for %s", v->toChars());
            else
            {
                if (offset < v->offset)
                    dtnzeros(pdt, v->offset - offset);
                dtcat(pdt, dt);
                offset = v->offset + v->type->size();
            }
        }
    }

    // Interface vptr initializations
    toSymbol();                                         // define csym

    for (i = 0; i < vtblInterfaces->dim; i++)
    {   BaseClass *b = (BaseClass *)vtblInterfaces->data[i];

#if 1 || INTERFACE_VIRTUAL
        for (ClassDeclaration *cd2 = cd; 1; cd2 = cd2->baseClass)
        {
            assert(cd2);
            csymoffset = cd2->baseVtblOffset(b);
            if (csymoffset != ~0)
            {
                if (offset < b->offset)
                    dtnzeros(pdt, b->offset - offset);
                dtxoff(pdt, cd2->toSymbol(), csymoffset, TYnptr);
                break;
            }
        }
#else
        csymoffset = baseVtblOffset(b);
        assert(csymoffset != ~0);
        dtxoff(pdt, csym, csymoffset, TYnptr);
#endif
        offset = b->offset + PTRSIZE;
    }

    if (offset < structsize)
        dtnzeros(pdt, structsize - offset);

#undef LOG
}

void StructDeclaration::toDt(dt_t **pdt)
{
    if (zeroInit)
    {
        dtnzeros(pdt, structsize);
        return;
    }

    unsigned offset;
    unsigned i;
    dt_t *dt;
    dt_t *sdt = NULL;

    //printf("StructDeclaration::toDt(), this='%s'\n", toChars());
    offset = 0;

    // Note equivalence of this loop to class's
    for (i = 0; i < fields.dim; i++)
    {
        VarDeclaration *v = (VarDeclaration *)fields.data[i];
        Initializer *init;

        //printf("\tfield '%s' voffset %d, offset = %d\n", v->toChars(), v->offset, offset);
        dt = NULL;
        init = v->init;
        if (init)
        {   //printf("\t\thas initializer %s\n", init->toChars());
            ExpInitializer *ei = init->isExpInitializer();
            Type *tb = v->type->toBasetype();
            if (ei && tb->ty == Tsarray)
            {
#ifdef IN_GCC
                dt = init->toDt();
                dt = createTsarrayDt(dt, v->type);
#else
                ((TypeSArray *)tb)->toDtElem(&dt, ei->exp);
#endif
            }
            else
                dt = init->toDt();
        }
        else if (v->offset >= offset)
            v->type->toDt(&dt);
        if (dt)
        {
            if (v->offset < offset)
                error("overlapping initialization for struct %s.%s", toChars(), v->toChars());
            else
            {
                if (offset < v->offset)
                    dtnzeros(& sdt, v->offset - offset);
                dtcat(& sdt, dt);
                offset = v->offset + v->type->size();
            }
        }
    }

    if (offset < structsize)
        dtnzeros(& sdt, structsize - offset);
#ifdef IN_GCC
    dtcontainer(pdt, type, sdt);
#else
    dtcat(pdt, sdt);
#endif

    dt_optimize(*pdt);
}

/* ================================================================= */

dt_t **Type::toDt(dt_t **pdt)
{
    //printf("Type::toDt()\n");
    Expression *e = defaultInit();
    return e->toDt(pdt);
}

dt_t **TypeSArray::toDt(dt_t **pdt)
{
    return toDtElem(pdt, NULL);
}

dt_t **TypeSArray::toDtElem(dt_t **pdt, Expression *e)
{
    int i;
    unsigned len;

    //printf("TypeSArray::toDtElem()\n");
    len = dim->toInteger();
    if (len)
    {
        while (*pdt)
            pdt = &((*pdt)->DTnext);
        Type *tnext = next;
        Type *tbn = tnext->toBasetype();
        while (tbn->ty == Tsarray)
        {   TypeSArray *tsa = (TypeSArray *)tbn;

            len *= tsa->dim->toInteger();
            tnext = tbn->next;
            tbn = tnext->toBasetype();
        }
        if (!e)                         // if not already supplied
            e = tnext->defaultInit();   // use default initializer
        if (tbn->ty == Tbit)
        {
            Bits databits;

            databits.resize(len);
            if (e->toInteger())
                databits.set();
#ifdef IN_GCC
            pdt = dtnbits(pdt, databits.allocdim * sizeof(databits.data[0]),
                (char *)databits.data, sizeof(databits.data[0]));
#else
            pdt = dtnbytes(pdt, databits.allocdim * sizeof(databits.data[0]),
                (char *)databits.data);
#endif
        }
        else
        {
            dt_t *adt = NULL;
            dt_t **padt = & adt;
            /* problem...?
            if (tbn->ty == Tstruct)
                tnext->toDt(pdt);
            else
                e->toDt(pdt);
            */
            e->toDt(padt);
            dt_optimize(*padt);

            // These first two cases are okay for GDC too
            if ((*padt)->dt == DT_azeros && !(*padt)->DTnext)
            {
                (*padt)->DTazeros *= len;
                pdt = dtcat(pdt, adt);
            }
            else if ((*padt)->dt == DT_1byte && (*padt)->DTonebyte == 0 && !(*padt)->DTnext)
            {
                (*padt)->dt = DT_azeros;
                (*padt)->DTazeros = len;
                pdt = dtcat(pdt, adt);
            }
            else if (e->op != TOKstring)
            {
#ifdef IN_GCC
                pdt = dtcat(pdt, createTsarrayDt(adt, this));
#else
                for (i = 1; i < len; i++)
                {
                    if (tbn->ty == Tstruct)
                    {   padt = tnext->toDt(padt);
                        while (*padt)
                            adt = &((*padt)->DTnext);
                    }
                    else
                        padt = e->toDt(padt);
                }
                pdt = dtcat(pdt, adt);
#endif
            }
        }
    }
    return pdt;
}

dt_t **TypeStruct::toDt(dt_t **pdt)
{
    sym->toDt(pdt);
    return pdt;
}

dt_t **TypeTypedef::toDt(dt_t **pdt)
{
    if (sym->init)
    {
        dt_t *dt = sym->init->toDt();

        while (*pdt)
            pdt = &((*pdt)->DTnext);
        *pdt = dt;
        return pdt;
    }
    sym->basetype->toDt(pdt);
    return pdt;
}



