/* Copyright (c) 1998, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */
#include "slinclud.h"

#include "slang.h"
#include "_slang.h"

struct _SLang_BString_Type
{
   unsigned int num_refs;
   unsigned int len;
   int ptr_type;
#define IS_SLSTRING		1
#define IS_MALLOCED		2
#define IS_NOT_TO_BE_FREED	3
   union
     {
	unsigned char bytes[1];
	unsigned char *ptr;
     }
   v;
};

#define BS_GET_POINTER(b) ((b)->ptr_type ? (b)->v.ptr : (b)->v.bytes)

static SLang_BString_Type *create_bstring_of_type (char *bytes, unsigned int len, int type)
{
   SLang_BString_Type *b;
   unsigned int size;

   size = sizeof(SLang_BString_Type);
   if (type == 0)
     size += len;

   if (NULL == (b = (SLang_BString_Type *)SLmalloc (size)))
     return NULL;

   b->len = len;
   b->num_refs = 1;
   b->ptr_type = type;

   switch (type)
     {
      case 0:
	if (bytes != NULL) memcpy ((char *) b->v.bytes, bytes, len);
	/* Now \0 terminate it because we want to also use it as a C string
	 * whenever possible.  Note that sizeof(SLang_BString_Type) includes
	 * space for 1 character and we allocated len extra bytes.  Thus, it is
	 * ok to add a \0 to the end.
	 */
	b->v.bytes[len] = 0;
	break;

      case IS_SLSTRING:
	if (NULL == (b->v.ptr = (unsigned char *)SLang_create_nslstring (bytes, len)))
	  {
	     SLfree ((char *) b);
	     return NULL;
	  }
	break;

      case IS_MALLOCED:
      case IS_NOT_TO_BE_FREED:
	b->v.ptr = (unsigned char *)bytes;
	bytes [len] = 0;	       /* NULL terminate */
	break;
     }

   return b;
}

SLang_BString_Type *
SLbstring_create (unsigned char *bytes, unsigned int len)
{
   return create_bstring_of_type ((char *)bytes, len, 0);
}

/* Note that ptr must be len + 1 bytes long for \0 termination */
SLang_BString_Type *
SLbstring_create_malloced (unsigned char *ptr, unsigned int len, int free_on_error)
{
   SLang_BString_Type *b;

   if (ptr == NULL)
     return NULL;

   if (NULL == (b = create_bstring_of_type ((char *)ptr, len, IS_MALLOCED)))
     {
	if (free_on_error)
	  SLfree ((char *) ptr);
     }
   return b;
}

SLang_BString_Type *SLbstring_create_slstring (char *s)
{
   if (s == NULL)
     return NULL;

   return create_bstring_of_type (s, strlen (s), IS_SLSTRING);
}

SLang_BString_Type *SLbstring_dup (SLang_BString_Type *b)
{
   if (b != NULL)
     b->num_refs += 1;

   return b;
}

unsigned char *SLbstring_get_pointer (SLang_BString_Type *b, unsigned int *len)
{
   if (b == NULL)
     {
	*len = 0;
	return NULL;
     }
   *len = b->len;
   return BS_GET_POINTER(b);
}

void SLbstring_free (SLang_BString_Type *b)
{
   if (b == NULL)
     return;

   if (b->num_refs > 1)
     {
	b->num_refs -= 1;
	return;
     }

   switch (b->ptr_type)
     {
      case 0:
      case IS_NOT_TO_BE_FREED:
      default:
	break;

      case IS_SLSTRING:
	SLang_free_slstring ((char *)b->v.ptr);
	break;

      case IS_MALLOCED:
	SLfree ((char *)b->v.ptr);
	break;
     }

   SLfree ((char *) b);
}

int SLang_pop_bstring (SLang_BString_Type **b)
{
   return SLclass_pop_ptr_obj (SLANG_BSTRING_TYPE, (VOID_STAR *)b);
}

int SLang_push_bstring (SLang_BString_Type *b)
{
   if (b == NULL)
     return SLang_push_null ();

   b->num_refs += 1;

   if (0 == SLclass_push_ptr_obj (SLANG_BSTRING_TYPE, (VOID_STAR)b))
     return 0;

   b->num_refs -= 1;
   return -1;
}

static int
bstring_bstring_bin_op_result (int op, unsigned char a, unsigned char b,
			       unsigned char *c)
{
   (void) a;
   (void) b;
   switch (op)
     {
      default:
	return 0;

      case SLANG_PLUS:
	*c = SLANG_BSTRING_TYPE;
	break;

      case SLANG_GT:
      case SLANG_GE:
      case SLANG_LT:
      case SLANG_LE:
      case SLANG_EQ:
      case SLANG_NE:
	*c = SLANG_CHAR_TYPE;
	break;
     }
   return 1;
}

static int compare_bstrings (SLang_BString_Type *a, SLang_BString_Type *b)
{
   unsigned int len;
   int ret;

   len = a->len;
   if (b->len < len) len = b->len;

   ret = memcmp ((char *)BS_GET_POINTER(b), (char *)BS_GET_POINTER(a), len);
   if (ret != 0)
     return ret;

   if (a->len > b->len)
     return 1;
   if (a->len == b->len)
     return 0;

   return -1;
}

static SLang_BString_Type *
concat_bstrings (SLang_BString_Type *a, SLang_BString_Type *b)
{
   unsigned int len;
   SLang_BString_Type *c;
   char *bytes;

   len = a->len + b->len;

   if (NULL == (c = SLbstring_create (NULL, len)))
     return NULL;

   bytes = (char *)BS_GET_POINTER(c);

   memcpy (bytes, (char *)BS_GET_POINTER(a), a->len);
   memcpy (bytes + a->len, (char *)BS_GET_POINTER(b), b->len);

   return c;
}

static void free_n_bstrings (SLang_BString_Type **a, unsigned int n)
{
   unsigned int i;

   if (a == NULL) return;

   for (i = 0; i < n; i++)
     {
	SLbstring_free (a[i]);
	a[i] = NULL;
     }
}

static int
bstring_bstring_bin_op (int op,
			unsigned char a_type, VOID_STAR ap, unsigned int na,
			unsigned char b_type, VOID_STAR bp, unsigned int nb,
			VOID_STAR cp)
{
   char *ic;
   SLang_BString_Type **a, **b, **c;
   unsigned int n, n_max;
   unsigned int da, db;

   (void) a_type;
   (void) b_type;

   if (na == 1) da = 0; else da = 1;
   if (nb == 1) db = 0; else db = 1;

   if (na > nb) n_max = na; else n_max = nb;

   a = (SLang_BString_Type **) ap;
   b = (SLang_BString_Type **) bp;
   for (n = 0; n < n_max; n++)
     {
	if ((*a == NULL) || (*b == NULL))
	  {
	     SLang_verror (SL_VARIABLE_UNINITIALIZED,
			   "Binary string element[%u] not initialized for binary operation", n);
	     return -1;
	  }
	a += da; b += db;
     }

   a = (SLang_BString_Type **) ap;
   b = (SLang_BString_Type **) bp;
   ic = (char *) cp;
   c = NULL;

   switch (op)
     {
       case SLANG_PLUS:
	/* Concat */
	c = (SLang_BString_Type **) cp;
	for (n = 0; n < n_max; n++)
	  {
	     if (NULL == (c[n] = concat_bstrings (*a, *b)))
	       goto return_error;

	     a += da; b += db;
	  }
	break;

      case SLANG_NE:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (0 != compare_bstrings (*a, *b));
	     a += da;
	     b += db;
	  }
	break;
      case SLANG_GT:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (compare_bstrings (*a, *b) > 0);
	     a += da;
	     b += db;
	  }
	break;
      case SLANG_GE:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (compare_bstrings (*a, *b) >= 0);
	     a += da;
	     b += db;
	  }
	break;
      case SLANG_LT:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (compare_bstrings (*a, *b) < 0);
	     a += da;
	     b += db;
	  }
	break;
      case SLANG_LE:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (compare_bstrings (*a, *b) <= 0);
	     a += da;
	     b += db;
	  }
	break;
      case SLANG_EQ:
	for (n = 0; n < n_max; n++)
	  {
	     ic [n] = (compare_bstrings (*a, *b) == 0);
	     a += da;
	     b += db;
	  }
	break;
     }
   return 1;

   return_error:
   if (c != NULL)
     {
	free_n_bstrings (c, n);
	while (n < n_max)
	  {
	     c[n] = NULL;
	     n++;
	  }
     }
   return -1;
}

/* If preserve_ptr, then use a[i] as the bstring data.  See how this function
 * is called by the binary op routines for why.
 */
static SLang_BString_Type **
make_n_bstrings (SLang_BString_Type **b, char **a, unsigned int n, int ptr_type)
{
   unsigned int i;
   int malloc_flag;

   malloc_flag = 0;
   if (b == NULL)
     {
	b = (SLang_BString_Type **) SLmalloc ((n + 1) * sizeof (SLang_BString_Type *));
	if (b == NULL)
	  return NULL;
	malloc_flag = 1;
     }

   for (i = 0; i < n; i++)
     {
	char *s = a[i];

	if (s == NULL)
	  {
	     b[i] = NULL;
	     continue;
	  }

	if (NULL == (b[i] = create_bstring_of_type (s, strlen(s), ptr_type)))
	  {
	     free_n_bstrings (b, i);
	     if (malloc_flag) SLfree ((char *) b);
	     return NULL;
	  }
     }

   return b;
}

static int
bstring_string_bin_op (int op,
		       unsigned char a_type, VOID_STAR ap, unsigned int na,
		       unsigned char b_type, VOID_STAR bp, unsigned int nb,
		       VOID_STAR cp)
{
   SLang_BString_Type **b;
   int ret;

   if (NULL == (b = make_n_bstrings (NULL, (char **)bp, nb, IS_NOT_TO_BE_FREED)))
     return -1;

   b_type = SLANG_BSTRING_TYPE;
   ret = bstring_bstring_bin_op (op,
				 a_type, ap, na,
				 b_type, (VOID_STAR) b, nb,
				 cp);
   free_n_bstrings (b, nb);
   SLfree ((char *) b);
   return ret;
}

static int
string_bstring_bin_op (int op,
		       unsigned char a_type, VOID_STAR ap, unsigned int na,
		       unsigned char b_type, VOID_STAR bp, unsigned int nb,
		       VOID_STAR cp)
{
   SLang_BString_Type **a;
   int ret;

   if (NULL == (a = make_n_bstrings (NULL, (char **)ap, na, IS_NOT_TO_BE_FREED)))
     return -1;

   a_type = SLANG_BSTRING_TYPE;
   ret = bstring_bstring_bin_op (op,
				 a_type, (VOID_STAR) a, na,
				 b_type, bp, nb,
				 cp);
   free_n_bstrings (a, na);
   SLfree ((char *) a);

   return ret;
}

static void bstring_destroy (unsigned char unused, VOID_STAR s)
{
   (void) unused;
   SLbstring_free (*(SLang_BString_Type **) s);
}

static int bstring_push (unsigned char unused, VOID_STAR sptr)
{
   (void) unused;

   return SLang_push_bstring (*(SLang_BString_Type **) sptr);
}

static int string_to_bstring (unsigned char a_type, VOID_STAR ap, unsigned int na,
			      unsigned char b_type, VOID_STAR bp)
{
   char **s;
   SLang_BString_Type **b;

   (void) a_type;
   (void) b_type;

   s = (char **) ap;
   b = (SLang_BString_Type **) bp;

   if (NULL == make_n_bstrings (b, s, na, IS_SLSTRING))
     return -1;

   return 1;
}

static int bstring_to_string (unsigned char a_type, VOID_STAR ap, unsigned int na,
			      unsigned char b_type, VOID_STAR bp)
{
   char **s;
   unsigned int i;
   SLang_BString_Type **a;

   (void) a_type;
   (void) b_type;

   s = (char **) bp;
   a = (SLang_BString_Type **) ap;

   for (i = 0; i < na; i++)
     {
	SLang_BString_Type *ai = a[i];

	if (ai == NULL)
	  {
	     s[i] = NULL;
	     continue;
	  }

	if (NULL == (s[i] = SLang_create_slstring ((char *)BS_GET_POINTER(ai))))
	  {
	     while (i != 0)
	       {
		  i--;
		  SLang_free_slstring (s[i]);
		  s[i] = NULL;
	       }
	     return -1;
	  }
     }

   return 1;
}

static char *bstring_string (unsigned char type, VOID_STAR v)
{
   SLang_BString_Type *s;
   unsigned char buf[128];
   unsigned char *bytes, *bytes_max;
   unsigned char *b, *bmax;

   (void) type;

   s = *(SLang_BString_Type **) v;
   bytes = BS_GET_POINTER(s);
   bytes_max = bytes + s->len;

   b = buf;
   bmax = buf + (sizeof (buf) - 4);

   while (bytes < bytes_max)
     {
	unsigned char ch = *bytes;

	if ((ch < 32) || (ch >= 127) || (ch == '\\'))
	  {
	     if (b + 4 > bmax)
	       break;

	     sprintf ((char *) b, "\\%03o", ch);
	     b += 4;
	  }
	else
	  {
	     if (b == bmax)
	       break;

	     *b++ = ch;
	  }

	bytes++;
     }

   if (bytes < bytes_max)
     {
	*b++ = '.';
	*b++ = '.';
	*b++ = '.';
     }
   *b = 0;

   return SLmake_string ((char *)buf);
}

static unsigned int bstrlen_cmd (SLang_BString_Type *b)
{
   return b->len;
}

static SLang_Intrin_Fun_Type BString_Table [] = /*{{{*/
{
   MAKE_INTRINSIC_1("bstrlen",  bstrlen_cmd, SLANG_UINT_TYPE, SLANG_BSTRING_TYPE),
   MAKE_INTRINSIC_0("pack", _SLpack, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_2("unpack", _SLunpack, SLANG_VOID_TYPE, SLANG_STRING_TYPE, SLANG_BSTRING_TYPE),
   MAKE_INTRINSIC_1("pad_pack_format", _SLpack_pad_format, SLANG_VOID_TYPE, SLANG_STRING_TYPE),
   MAKE_INTRINSIC_1("sizeof_pack", _SLpack_compute_size, SLANG_UINT_TYPE, SLANG_STRING_TYPE),
   SLANG_END_INTRIN_FUN_TABLE
};

int _SLang_init_bstring (void)
{
   SLang_Class_Type *cl;

   if (NULL == (cl = SLclass_allocate_class ("BString_Type")))
     return -1;
   (void) SLclass_set_destroy_function (cl, bstring_destroy);
   (void) SLclass_set_push_function (cl, bstring_push);
   (void) SLclass_set_string_function (cl, bstring_string);

   if (-1 == SLclass_register_class (cl, SLANG_BSTRING_TYPE, sizeof (char *),
				     SLANG_CLASS_TYPE_PTR))
     return -1;

   if ((-1 == SLclass_add_typecast (SLANG_BSTRING_TYPE, SLANG_STRING_TYPE, bstring_to_string, 1))
       || (-1 == SLclass_add_typecast (SLANG_STRING_TYPE, SLANG_BSTRING_TYPE, string_to_bstring, 1))
       || (-1 == SLclass_add_binary_op (SLANG_BSTRING_TYPE, SLANG_BSTRING_TYPE, bstring_bstring_bin_op, bstring_bstring_bin_op_result))
       || (-1 == SLclass_add_binary_op (SLANG_STRING_TYPE, SLANG_BSTRING_TYPE, string_bstring_bin_op, bstring_bstring_bin_op_result))
       || (-1 == SLclass_add_binary_op (SLANG_BSTRING_TYPE, SLANG_STRING_TYPE, bstring_string_bin_op, bstring_bstring_bin_op_result)))

     return -1;

   if (-1 == SLadd_intrin_fun_table (BString_Table, NULL))
     return -1;

   return 0;
}

