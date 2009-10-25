#include "d-gcc-includes.h"
#include "total.h"
#include "statement.h"

#include "d-lang.h"
#include "d-codegen.h"

typedef enum {
    Arg_Integer,
    Arg_Pointer,
    Arg_Memory,
    Arg_FrameRelative,
    Arg_LocalSize,
    Arg_Dollar
} AsmArgType;

typedef enum {
    Mode_Input,
    Mode_Output,
    Mode_Update
} AsmArgMode;

struct AsmArg {
    AsmArgType   type;
    Expression * expr;
    AsmArgMode   mode;
    AsmArg(AsmArgType type, Expression * expr, AsmArgMode mode) {
	this->type = type;
	this->expr = expr;
	this->mode = mode;
    }
};

struct AsmCode {
    char *   insnTemplate;
    unsigned insnTemplateLen;
    Array    args; // of AsmArg
    unsigned moreRegs;
    unsigned dollarLabel;
    int      clobbersMemory;
    AsmCode() {
	insnTemplate = NULL;
	insnTemplateLen = 0;
	moreRegs = 0;
	dollarLabel = 0;
	clobbersMemory = 0;
    }
};

#if D_GCC_VER >= 40
/* Apple GCC extends ASM_EXPR to five operands; cannot use build4. */
tree
d_build_asm_stmt(tree t1, tree t2, tree t3, tree t4)
{
    tree t = make_node(ASM_EXPR);
    TREE_TYPE(t) = void_type_node;
    SET_EXPR_LOCATION(t, input_location);
    TREE_OPERAND(t,0) = t1;
    TREE_OPERAND(t,1) = t2;
    TREE_OPERAND(t,2) = t3;
    TREE_OPERAND(t,3) = t4;
    TREE_SIDE_EFFECTS(t) = 1;
    return t;
}
#endif

#if V2 //for GDC D1
AsmStatement::AsmStatement(Loc loc, Token *tokens) :
    Statement(loc)
{
    this->tokens = tokens; // Do I need to copy these?
    asmcode = 0;
    asmalign = 0;
    refparam = 0;
    naked = 0;
    regs = 0;
}

Statement *AsmStatement::syntaxCopy()
{
    // copy tokens? copy 'code'?
    AsmStatement * a_s = new AsmStatement(loc,tokens);
    a_s->asmcode = asmcode;
    a_s->refparam = refparam;
    a_s->naked = naked;
    a_s->regs = a_s->regs;
    return a_s;
}

void AsmStatement::toCBuffer(OutBuffer *buf, HdrGenState *hgs)
{
    bool sep = 0, nsep = 0;
    buf->writestring("asm { ");
    
    for (Token * t = tokens; t; t = t->next) {	
	switch (t->value) {
	case TOKlparen:
	case TOKrparen:
	case TOKlbracket:
	case TOKrbracket:
	case TOKcolon:
	case TOKsemicolon:
	case TOKcomma:
	case TOKstring:
	case TOKcharv:
	case TOKwcharv:
	case TOKdcharv:
	    nsep = 0;
	    break;
	default:
	    nsep = 1;
	}
	if (sep + nsep == 2)
    		buf->writeByte(' ');
	sep = nsep;
	buf->writestring(t->toChars());
    }
    buf->writestring("; }");
    buf->writenl();
}

int AsmStatement::comeFrom()
{
    return FALSE;
}

//#if V2

int
AsmStatement::blockExit()
{
    // TODO: Be smarter about this
    return BEany;
}

//#endif

#endif //V2 for GDC

/* GCC does not support jumps from asm statements.  When optimization
   is turned on, labels referenced only from asm statements will not
   be output at the correct location.  There are ways around this:

   1) Reference the label with a reachable goto statement
   2) Have reachable computed goto in the function
   3) Hack cfgbuild.c to act as though there is a computed goto.

   These are all pretty bad, but if would be nice to be able to tell
   GCC not to optimize in this case (even on per label/block basis).

   The current solution is output our own private labels (as asm
   statements) along with the "real" label.  If the label happens to
   be referred to by a goto statement, the "real" label will also be
   output in the correct location.

   Also had to add 'asmLabelNum' to LabelDsymbol to indicate it needs
   special processing.

   (junk) d-lang.cc:916:case LABEL_DECL: // C doesn't do this.  D needs this for referencing labels in inline assembler since there may be not goto referencing it.

*/

static unsigned d_priv_asm_label_serial = 0;

// may need to make this target-specific
static void d_format_priv_asm_label(char * buf, unsigned n)
{
    //ASM_GENERATE_INTERNAL_LABEL(buf, "LDASM", n);//inserts a '*' for use with assemble_name
    sprintf(buf, ".LDASM%u", n);
}

void
d_expand_priv_asm_label(IRState * irs, unsigned n)
{
    char buf[64];
    d_format_priv_asm_label(buf, n);
    strcat(buf, ":");
    tree insnt = build_string(strlen(buf), buf);
#if D_GCC_VER < 40
    expand_asm(insnt, 1);
#else
    tree t = d_build_asm_stmt(insnt, NULL_TREE, NULL_TREE, NULL_TREE);
    ASM_VOLATILE_P( t ) = 1;
    ASM_INPUT_P( t) = 1; // what is this doing?
    irs->addExp(t);
#endif
}

ExtAsmStatement::ExtAsmStatement(Loc loc, Expression *insnTemplate, Expressions *args, Array *argNames,
    Expressions *argConstraints, int nOutputArgs, Expressions *clobbers)
    : Statement(loc)
{
    this->insnTemplate = insnTemplate;
    this->args = args;
    this->argNames = argNames;
    this->argConstraints = argConstraints;
    this->nOutputArgs = nOutputArgs;
    this->clobbers = clobbers;
}

Statement *ExtAsmStatement::syntaxCopy()
{
    /* insnTemplate, argConstraints, and clobbers would be
       semantically static in GNU C. */
    Expression *insnTemplate = this->insnTemplate->syntaxCopy();
    Expressions * args = Expression::arraySyntaxCopy(this->args);
    // argNames is an array of identifiers
    Expressions * argConstraints = Expression::arraySyntaxCopy(this->argConstraints);
    Expressions * clobbers = Expression::arraySyntaxCopy(this->clobbers);
    return new ExtAsmStatement(loc, insnTemplate, args, argNames,
	argConstraints, nOutputArgs, clobbers);
}

Statement *ExtAsmStatement::semantic(Scope *sc)
{
    insnTemplate = insnTemplate->semantic(sc);
    insnTemplate = insnTemplate->optimize(WANTvalue);
    if (insnTemplate->op != TOKstring || ((StringExp *)insnTemplate)->sz != 1)
	error("instruction template must be a constant char string");
    if (args)
	for (unsigned i = 0; i < args->dim; i++) {
	    Expression * e = (Expression *) args->data[i];
	    e = e->semantic(sc);
	    if (i < nOutputArgs)
		e = e->modifiableLvalue(sc, NULL);
	    else
		e = e->optimize(WANTvalue|WANTinterpret);
	    args->data[i] = e;

	    e = (Expression *) argConstraints->data[i];
	    e = e->semantic(sc);
	    e = e->optimize(WANTvalue);
	    if (e->op != TOKstring || ((StringExp *)e)->sz != 1)
		error("constraint must be a constant char string");
	    argConstraints->data[i] = e;
	}
    if (clobbers)
	for (unsigned i = 0; i < clobbers->dim; i++) {
	    Expression * e = (Expression *) clobbers->data[i];
	    e = e->semantic(sc);
	    e = e->optimize(WANTvalue);
	    if (e->op != TOKstring || ((StringExp *)e)->sz != 1)
		error("clobber specification must be a constant char string");
	    clobbers->data[i] = e;
	}
    return this;
}

//#if V2

int
ExtAsmStatement::blockExit()
{
    // TODO: Be smarter about this
    return BEany;
}

//#endif

// StringExp::toIR usually adds a NULL.  We don't want that...

static tree
naturalString(Expression * e)
{
    // don't fail, just an error?
    assert(e->op == TOKstring);
    StringExp * s = (StringExp *) e;
    assert(s->sz == 1);
    return build_string(s->len, (char *) s->string);
}

void ExtAsmStatement::toIR(IRState *irs)
{
    ListMaker outputs;
    ListMaker inputs;
    ListMaker tree_clobbers;

    gen.doLineNote( loc );

    if (this->args)
	for (unsigned i = 0; i < args->dim; i++)
	{
	    Identifier * name = argNames->data[i] ? (Identifier *) argNames->data[i] : NULL;
	    Expression * constr = (Expression *) argConstraints->data[i];
	    tree p = tree_cons(name ? build_string(name->len, name->string) : NULL_TREE,
		naturalString(constr), NULL_TREE);
	    tree v = ((Expression *) args->data[i])->toElem(irs);

	    if (i < nOutputArgs)
		outputs.cons(p, v);
	    else
		inputs.cons(p, v);
	}
    if (clobbers)
	for (unsigned i = 0; i < clobbers->dim; i++) {
	    Expression * clobber = (Expression *) clobbers->data[i];
	    tree_clobbers.cons(NULL_TREE, naturalString(clobber));
	}

    irs->doAsm(naturalString(insnTemplate), outputs.head, inputs.head, tree_clobbers.head);
}

#ifdef TARGET_80387
#include "d-asm-i386.h"
#else
#define D_NO_INLINE_ASM_AT_ALL
#endif

#ifndef D_NO_INLINE_ASM_AT_ALL

bool d_have_inline_asm() { return true; }

Statement *AsmStatement::semantic(Scope *sc)
{
    
    sc->func->inlineAsm = 1;
    sc->func->inlineStatus = ILSno; // %% not sure
    // %% need to set DECL_UNINLINABLE too?
    sc->func->hasReturnExp = 1; // %% DMD does this, apparently...
    
    // empty statement -- still do the above things because they might be expected?
    if (! tokens)
	return this;
    
    AsmProcessor ap(sc, this);
    ap.run();
    return this;
}

void
AsmStatement::toIR(IRState * irs)
{
    gen.doLineNote( loc );

    if (! asmcode)
	return;

    static tree i_cns = 0;
    static tree p_cns = 0;
    static tree m_cns = 0;
    static tree mw_cns = 0;
    static tree mrw_cns = 0;
    static tree memory_name = 0;

    if (! i_cns) {
	i_cns = build_string(1, "i");
	p_cns = build_string(1, "p");
	m_cns = build_string(1, "m");
	mw_cns  = build_string(2, "=m");
	mrw_cns = build_string(2, "+m");
	memory_name = build_string(6, "memory");
	dkeep(i_cns);
	dkeep(p_cns);
	dkeep(m_cns);
    }

    AsmCode * code = (AsmCode *) asmcode;
    ListMaker inputs;
    ListMaker outputs;
    ListMaker clobbers;
    //tree dollar_label = NULL_TREE;//OLD
    HOST_WIDE_INT var_frame_offset; // "frame_offset" is a macro
    bool clobbers_mem = code->clobbersMemory;
    int input_idx = 0;
    int n_outputs = 0;
    int arg_map[10];

    assert(code->args.dim <= 10);

    for (unsigned i = 0; i < code->args.dim; i++) {
	AsmArg * arg = (AsmArg *) code->args.data[i];
	
	bool is_input = true;
	tree arg_val = NULL_TREE;
	tree cns = NULL_TREE;
	
	switch (arg->type) {
	case Arg_Integer:
	    arg_val = arg->expr->toElem(irs);
	do_integer:
	    cns = i_cns;
	    break;
	case Arg_Pointer:
	    if (arg->expr->op == TOKvar)
		arg_val = ((VarExp *) arg->expr)->var->toSymbol()->Stree;
	    else if (arg->expr->op == TOKdsymbol) {
		arg_val = irs->getLabelTree( (LabelDsymbol *) ((DsymbolExp *) arg->expr)->s );
	    } else
		assert(0);
	    arg_val = irs->addressOf(arg_val);
	    cns = p_cns;
	    break;
	case Arg_Memory:
	    if (arg->expr->op == TOKvar)
		arg_val = ((VarExp *) arg->expr)->var->toSymbol()->Stree;
	    else if (arg->expr->op == TOKfloat64)
	    {
		/* Constant scalar value.  In order to reference it as memory,
		   create an anonymous static var. */
		tree cnst = build_decl(VAR_DECL, NULL_TREE, arg->expr->type->toCtype());
		g.ofile->giveDeclUniqueName(cnst);
		DECL_INITIAL(cnst) = arg->expr->toElem(irs);
		TREE_STATIC(cnst) = TREE_CONSTANT(cnst) = TREE_READONLY(cnst) =
		    TREE_PRIVATE(cnst) = DECL_ARTIFICIAL(cnst) = DECL_IGNORED_P(cnst) = 1;
		g.ofile->rodc(cnst, 1);
		arg_val = cnst;    
	    }
	    else
		arg_val = arg->expr->toElem(irs);
	    if (DECL_P( arg_val ))
		TREE_ADDRESSABLE( arg_val ) = 1;
	    switch (arg->mode) {
	    case Mode_Input:  cns = m_cns; break;
	    case Mode_Output: cns = mw_cns;  is_input = false; break;
	    case Mode_Update: cns = mrw_cns; is_input = false; break;
	    default: assert(0); break;
	    }
	    break;
	case Arg_FrameRelative:
	    if (arg->expr->op == TOKvar)
		arg_val = ((VarExp *) arg->expr)->var->toSymbol()->Stree;
	    else
		assert(0);
	    if ( getFrameRelativeValue(arg_val, & var_frame_offset) ) {
		arg_val = irs->integerConstant(var_frame_offset);
		cns = i_cns;
	    } else {
		this->error("%s", "argument not frame relative");
		return;
	    }
	    if (arg->mode != Mode_Input)
		clobbers_mem = true;
	    break;
	case Arg_LocalSize:
	    var_frame_offset = cfun->x_frame_offset;
	    if (var_frame_offset < 0)
		var_frame_offset = - var_frame_offset;
	    arg_val = irs->integerConstant( var_frame_offset );
	    goto do_integer;
	    /* OLD
	case Arg_Dollar:
	    if (! dollar_label)
		dollar_label = build_decl(LABEL_DECL, NULL_TREE, void_type_node);
	    arg_val = dollar_label;
	    goto do_pointer;
	    */
	default:
	    assert(0);
	}

	if (is_input) {
	    arg_map[i] = --input_idx;
	    inputs.cons(tree_cons(NULL_TREE, cns, NULL_TREE), arg_val);
	} else {
	    arg_map[i] = n_outputs++;
	    outputs.cons(tree_cons(NULL_TREE, cns, NULL_TREE), arg_val);
	}
    }

    // Telling GCC that callee-saved registers are clobbered makes it preserve
    // those registers.   This changes the stack from what a naked function
    // expects.
    
    if (! irs->func->naked) {
	for (int i = 0; i < 32; i++) {
	    if (regs & (1 << i)) {
		clobbers.cons(NULL_TREE, regInfo[i].gccName);
	    }
	}
	for (int i = 0; i < 32; i++) {
	    if (code->moreRegs & (1 << (i-32))) {
		clobbers.cons(NULL_TREE, regInfo[i].gccName);
	    }
	}
	if (clobbers_mem)
	    clobbers.cons(NULL_TREE, memory_name);
    }


    // Remap argument numbers
    for (unsigned i = 0; i < code->args.dim; i++) {
	if (arg_map[i] < 0)
	    arg_map[i] = -arg_map[i] - 1 + n_outputs;
    }
    
    bool pct = false;
    char * p = code->insnTemplate;
    char * q = p + code->insnTemplateLen;
    //printf("start: %.*s\n", code->insnTemplateLen, code->insnTemplate);
    while (p < q) {
	if (pct) {
	    if (*p >= '0' && *p <= '9') {
		// %% doesn't check against nargs
		*p = '0' + arg_map[*p - '0'];
		pct = false;
	    } else if (*p == '%') {
		pct = false;
	    }
	    //assert(*p == '%');// could be 'a', etc. so forget it..
	} else if (*p == '%')
	    pct = true;
	++p;
    }

    //printf("final: %.*s\n", code->insnTemplateLen, code->insnTemplate);

    tree insnt = build_string(code->insnTemplateLen, code->insnTemplate);
#if D_GCC_VER == 34
    location_t gcc_loc = { loc.filename, loc.linnum };
    expand_asm_operands(insnt, outputs.head, inputs.head, clobbers.head, 1, gcc_loc);
#else
    tree t = d_build_asm_stmt(insnt, outputs.head, inputs.head, clobbers.head);
    ASM_VOLATILE_P( t ) = 1;
    irs->addExp( t );
#endif
    //if (dollar_label)//OLD
    // expand_label(dollar_label);
    if (code->dollarLabel)
	d_expand_priv_asm_label(irs, code->dollarLabel);
}

#else

bool d_have_inline_asm() { return false; }

Statement *
AsmStatement::semantic(Scope *sc)
{
    sc->func->inlineAsm = 1;
    return Statement::semantic(sc);
}

void
AsmStatement::toIR(IRState *)
{
    sorry("assembler statements are not supported on this target");
}

#endif
