#include <regex.h>
#include <stdlib.h>
#include <ctype.h>
#include <sys/types.h>
#include <string.h>

/* this is ugly.
 * the idea is to build a parse tree, then do some poor man's OOP with a
 * generic matcher function call that is always that the start of each
 * record, and a next pointer.  When the parse tree is done, we need to
 * recursively set the next pointers to point to the part of the parse
 * tree that needs to match next.
 * This is the prototype of the generic match function call pointer.
 * The first argument is the "this" pointer, the second is the text to
 * be matched against, ofs is the offset from the start of the matched
 * text (so we can match "^") and matches is an array where match
 * positions are stored. */
/* now declared in regex.h: */
/* typedef int (*matcher)(void*,const char*,int ofs,regmatch_t* matches,int plus,int eflags); */

/* one would think that this is approach is an order of magnitude slower
 * than the standard NFA approach, but it isn't.  The busybox grep took
 * 0.26 seconds for a fixed string compared to 0.19 seconds for the
 * glibc regex. */

/* first part: parse a regex into a parse tree */
struct bracketed {
  unsigned int cc[32];
};

/* now declared in regex.h:
struct regex {
  matcher m;
  void* next;
  int pieces;
  int num;
  struct branch *b;
}; */

struct atom {
  matcher m;
  void* next;
  enum { EMPTY, REGEX, BRACKET, ANY, LINESTART, LINEEND, WORDSTART, WORDEND, CHAR, } type;
  int bnum;
  union {
    struct regex r;
    struct bracketed b;
    char c;
  } u;
};

struct piece {
  matcher m;
  void* next;
  struct atom a;
  unsigned char min,max;
};

struct branch {
  matcher m;
  void* next;
  int num;
  struct piece *p;
};

static void clearcc(unsigned int* x) {
  memset(x,0,sizeof(*x));
}

static void setcc(unsigned int* x,unsigned int bit) {
  x[bit/32]|=(1<<((bit%32)-1));
}

static int issetcc(unsigned int* x,unsigned int bit) {
  return x[bit/32] & (1<<((bit%32)-1));
}

static const char* parsebracketed(struct bracketed*__restrict__ b,const char*__restrict__ s,regex_t*__restrict__ rx) {
  const char* t;
  int i,negflag=0;
  if (*s!='[') return s;
  t=s+1;
  clearcc(b->cc);
  if (*t=='^') { negflag=1; ++t; }
  do {
    if (*t==0) return s;
    setcc(b->cc,rx->cflags&REG_ICASE?*t:tolower(*t));
    if (t[1]=='-' && t[2]!=']') {
      for (i=*t+1; i<=t[2]; ++i) setcc(b->cc,rx->cflags&REG_ICASE?i:tolower(i));
      t+=2;
    }
    ++t;
  } while (*t!=']');
  if (negflag) for (i=0; i<32; ++i) b->cc[i]=~b->cc[i];
  return t+1;
}

static const char* parseregex(struct regex* r,const char* s,regex_t* rx);

static int matchatom(void*__restrict__ x,const char*__restrict__ s,int ofs,struct __regex_t*__restrict__ preg,int plus,int eflags) {
  register struct atom* a=(struct atom*)x;
  int matchlen=0;
  switch (a->type) {
  case EMPTY:
//    printf("matching EMPTY against \"%s\"\n",s);
    preg->l[a->bnum].rm_so=preg->l[a->bnum].rm_eo=ofs;
    goto match;
  case REGEX:
//    printf("matching REGEX against \"%s\"\n",s);
    if ((matchlen=a->u.r.m(a,s,ofs,preg,0,eflags))>=0) {
      preg->l[a->bnum].rm_so=ofs;
      preg->l[a->bnum].rm_eo=ofs+matchlen;
      goto match;
    }
    break;
  case BRACKET:
//    printf("matching BRACKET against \"%s\"\n",s);
    matchlen=1;
    if (*s=='\n' && (preg->cflags&REG_NEWLINE)) break;
    if (*s && issetcc(a->u.b.cc,(preg->cflags&REG_ICASE?tolower(*s):*s)))
      goto match;
    break;
  case ANY:
//    printf("matching ANY against \"%s\"\n",s);
    if (*s=='\n' && (preg->cflags&REG_NEWLINE)) break;
    matchlen=1;
    if (*s) goto match;
    break;
  case LINESTART:
//    printf("matching LINESTART against \"%s\"\n",s);
    if (ofs==0 && (eflags&REG_NOTBOL)==0) {
      goto match;
    }
    break;
  case LINEEND:
//    printf("matching LINEEND against \"%s\"\n",s);
    if ((*s && *s!='\n') || (eflags&REG_NOTEOL)==0) break;
    goto match;
  case WORDSTART:
    if ((ofs==0 || isspace(s[-1])) && !isspace(*s))
      goto match;
    break;
  case WORDEND:
    if (ofs>0 && !isspace(s[-1]) && isspace(*s))
      goto match;
    break;
  case CHAR:
//    printf("matching CHAR %c against \"%s\"\n",a->u.c,s);
    matchlen=1;
    if (((preg->cflags&REG_ICASE)?tolower(*s):*s)==a->u.c) goto match;
    break;
  }
  return -1;
match:
  if (a->next)
    return ((struct atom*)(a->next))->m(a->next,s+matchlen,ofs+matchlen,preg,plus+matchlen,eflags);
  else
    return plus+matchlen;
}

static const char* parseatom(struct atom*__restrict__ a,const char*__restrict__ s,regex_t*__restrict__ rx) {
  const char *tmp;
  a->m=matchatom;
  a->bnum=-1;
  switch (*s) {
  case '(':
    a->bnum=++rx->brackets;
    if (s[1]==')') {
      a->type=EMPTY;
      return s+2;
    }
    a->type=REGEX;
    if ((tmp=parseregex(&a->u.r,s+1,rx))!=s) {
      if (*tmp==')')
	return tmp+1;
    }
  case 0:
  case '|':
  case ')':
    return s;
  case '[':
    a->type=BRACKET;
    if ((tmp=parsebracketed(&a->u.b,s,rx))!=s)
      return tmp;
    return s;
  case '.':
    a->type=ANY;
    break;
  case '^':
    a->type=LINESTART;
    break;
  case '$':
    a->type=LINEEND;
    break;
  case '\\':
    if (!*++s) return s;
    if (*s=='<') {
      a->type=WORDSTART;
      break;
    } else if (*s=='>') {
      a->type=WORDEND;
      break;
    }
  default:
    a->type=CHAR;
    a->u.c=rx->cflags&REG_ICASE?*s:tolower(*s);
    break;
  }
  return s+1;
}

/* needs to do "greedy" matching, i.e. match as often as possible */
static int matchpiece(void*__restrict__ x,const char*__restrict__ s,int ofs,struct __regex_t*__restrict__ preg,int plus,int eflags) {
  register struct piece* a=(struct piece*)x;
  int matchlen=0;
  int tmp,num=0;
  unsigned int *offsets=alloca(sizeof(int)*a->max);
  offsets[0]=0;
//  printf("matchpiece \"%s\"...\n",s);
  /* first, try to match the atom as often as possible, up to a->max times */
  if (a->max == 1 && a->min == 1)
    return a->a.m(&a->a,s+matchlen,ofs+matchlen,preg,0,eflags);
  while (num<a->max) {
    void* save=a->a.next;
    a->a.next=0;
    if ((tmp=a->a.m(&a->a,s+matchlen,ofs+matchlen,preg,0,eflags))>=0) {
      a->a.next=save;
      ++num;
      matchlen+=tmp;
      offsets[num]=tmp;
    } else {
      a->a.next=save;
      break;
    }
  }
  if (num<a->min) return -1;		/* already at minimum matches; signal mismatch */
  /* then, while the rest does not match, back off */
  for (;;) {
    if (a->next)
      tmp=((struct atom*)(a->next))->m(a->next,s+matchlen,ofs+matchlen,preg,plus+matchlen,eflags);
    else
      tmp=plus+matchlen;
    if (tmp>=0) break;	/* it did match; don't back off any further */
    matchlen-=offsets[num];
    --num;
  }
  return tmp;
}

static const char* parsepiece(struct piece*__restrict__ p,const char*__restrict__ s,regex_t*__restrict__ rx) {
  const char* tmp=parseatom(&p->a,s,rx);
  if (tmp==s) return s;
  p->m=matchpiece;
  p->min=p->max=1;
  switch (*tmp) {
  case '*': p->min=0; p->max=RE_DUP_MAX; break;
  case '+': p->min=1; p->max=RE_DUP_MAX; break;
  case '?': p->min=0; p->max=1; break;
  case '{':
    if (isdigit(*++tmp)) {
      p->min=*tmp-'0'; p->max=RE_DUP_MAX;
      while (isdigit(*++tmp)) p->min=p->min*10+*tmp-'0';
      if (*tmp==',') {
	if (isdigit(*++tmp)) {
	  p->max=*tmp-'0';
	  while (isdigit(*++tmp)) p->max=p->max*10+*tmp-'0';
	}
      }
      if (*tmp!='}') return s;
      ++tmp;
    }
  default:
    return tmp;
  }
  return tmp+1;
}

/* trivial, just pass through */
static int matchbranch(void*__restrict__ x,const char*__restrict__ s,int ofs,struct __regex_t*__restrict__ preg,int plus,int eflags) {
  register struct branch* a=(struct branch*)x;
  int tmp;
  tmp=a->p->m(a->p,s,ofs,preg,plus,eflags);
  if (tmp>=0) {
    if (a->next)
      return ((struct atom*)(a->next))->m(a->next,s+tmp,ofs+tmp,preg,plus+tmp,eflags);
    else
      return plus+tmp;
  }
  return -1;
}

static const char* parsebranch(struct branch*__restrict__ b,const char*__restrict__ s,regex_t*__restrict__ rx,int*__restrict__ pieces) {
  struct piece p;
  const char *tmp;
  b->m=matchbranch;
  b->num=0; b->p=0;
  for (;;) {
    if (*s=='|') {
      if (b->num==0) {
	tmp=s+1;
	p.a.type=EMPTY;
	p.min=p.max=1;
      }
    } else {
      tmp=parsepiece(&p,s,rx);
      if (tmp==s) return s;
    }
    if (!(b->p=realloc(b->p,++b->num*sizeof(p)))) return s;
    b->p[b->num-1]=p;
    if (*s=='|') { ++tmp; break; }
    s=tmp;
  }
  *pieces+=b->num;
  return tmp;
}

/* try the branches one by one */
static int matchregex(void*__restrict__ x,const char*__restrict__ s,int ofs,struct __regex_t*__restrict__ preg,int plus,int eflags) {
  register struct regex* a=(struct regex*)x;
  int i,tmp;
  for (i=0; i<a->num; ++i) {
    tmp=a->b[i].m(&a->b[i],s,ofs,preg,plus,eflags);
    if (tmp>=0) {
      if (a->next)
	return ((struct atom*)(a->next))->m(a->next,s+tmp,ofs+tmp,preg,plus+tmp,eflags);
      else
	return plus+tmp;
    }
  }
  return -1;
}

static const char* parseregex(struct regex*__restrict__ r,const char*__restrict__ s,regex_t*__restrict__ p) {
  struct branch b;
  const char *tmp;
  r->m=matchregex;
  r->num=0; r->b=0; r->pieces=0;
  for (;;) {
    tmp=parsebranch(&b,s,p,&r->pieces);
    if (tmp==s) return s;
    if (!(r->b=realloc(r->b,++r->num*sizeof(b)))) return s;
    r->b[r->num-1]=b;
    s=tmp;
  }
  return tmp;
}


/* The matcher relies on the presence of next pointers, of which the
 * parser does not know the correct destination.  So we need an
 * additional pass through the data structure that sets the next
 * pointers correctly. */
static void regex_putnext(struct regex* r,void* next);

static void atom_putnext(struct atom*__restrict__ a,void*__restrict__ next) {
  a->next=next;
  if (a->type==REGEX)
    regex_putnext(&a->u.r,next);
}

static void piece_putnext(struct piece*__restrict__ p,void*__restrict__ next) {
  p->next=next;
  atom_putnext(&p->a,next);
}

static void branch_putnext(struct branch*__restrict__ b,void*__restrict__ next) {
  int i;
  for (i=0; i<b->num-1; ++i)
    piece_putnext(&b->p[i],&b->p[i+1]);
  piece_putnext(&b->p[i],0);
  b->next=next;
}

static void regex_putnext(struct regex*__restrict__ r,void*__restrict__ next) {
  int i;
  for (i=0; i<r->num; ++i)
    branch_putnext(&r->b[i],next);
  r->next=next;
}



int regcomp(regex_t*__restrict__ preg, const char*__restrict__ regex, int cflags) {
  const char* t=parseregex(&preg->r,regex,preg);
  if (t==regex) return -1;
  regex_putnext(&preg->r,0);
  preg->cflags=cflags;
  return 0;
}

int regexec(const regex_t*__restrict__ preg, const char*__restrict__ string, size_t nmatch, regmatch_t pmatch[], int eflags) {
  int matched;
  const char *orig=string;
  ((regex_t*)preg)->l=alloca(sizeof(regmatch_t)*(preg->brackets+1));
  while (*string) {
    matched=preg->r.m((void*)&preg->r,string,string-orig,(regex_t*)preg,0,eflags);
    if (matched>=0) {
      if ((preg->cflags&REG_NOSUB)==0) memmove(pmatch,preg->l,nmatch*sizeof(regmatch_t));
      return 0;
    }
    ++string; eflags|=REG_NOTBOL;
  }
  return REG_NOMATCH;
}



void regfree(regex_t* preg) {
  int i;
  for (i=0; i<preg->r.num; ++i) {
    free(preg->r.b[i].p);
    free(preg->r.b);
  }
}

size_t regerror(int errcode, const regex_t*__restrict__ preg, char*__restrict__ errbuf, size_t errbuf_size) {
  strncpy(errbuf,"invalid regular expression (sorry)",errbuf_size);
  return strlen(errbuf);
}




#if 0
int main() {
  struct regex r;
  int bnum=-1;
  const char* t=parseregex(&r,"^a*ab$",&bnum);
  regex_putnext(&r,0);
  printf("%d pieces, %s\n",r.pieces,t);
  printf("%d\n",r.m(&r,"aaab",0,0,0));
  return 0;
}
#endif
