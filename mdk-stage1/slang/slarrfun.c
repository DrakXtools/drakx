/* Advanced array manipulation routines for S-Lang */
/* Copyright (c) 1998, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

#include "slinclud.h"

#include "slang.h"
#include "_slang.h"

static int next_transposed_index (int *dims, int *max_dims, unsigned int num_dims)
{
   int i;

   for (i = 0; i < (int) num_dims; i++)
     {
	int dims_i;

	dims_i = dims [i] + 1;
	if (dims_i != (int) max_dims [i])
	  {
	     dims [i] = dims_i;
	     return 0;
	  }
	dims [i] = 0;
     }

   return -1;
}

static SLang_Array_Type *allocate_transposed_array (SLang_Array_Type *at)
{
   unsigned int num_elements;
   SLang_Array_Type *bt;
   VOID_STAR b_data;

   num_elements = at->num_elements;
   b_data = (VOID_STAR) SLmalloc (at->sizeof_type * num_elements);
   if (b_data == NULL)
     return NULL;

   bt = SLang_create_array (at->data_type, 0, b_data, at->dims, 2);
   if (bt == NULL)
     {
	SLfree ((char *)b_data);
	return NULL;
     }

   bt->dims[1] = at->dims[0];
   bt->dims[0] = at->dims[1];

   return bt;
}

#define GENERIC_TYPE float
#define TRANSPOSE_2D_ARRAY transpose_floats
#define GENERIC_TYPE_A float
#define GENERIC_TYPE_B float
#define GENERIC_TYPE_C float
#define INNERPROD_FUNCTION innerprod_float_float
#if SLANG_HAS_COMPLEX
# define INNERPROD_COMPLEX_A innerprod_complex_float
# define INNERPROD_A_COMPLEX innerprod_float_complex
#endif
#include "slarrfun.inc"

#define GENERIC_TYPE double
#define TRANSPOSE_2D_ARRAY transpose_doubles
#define GENERIC_TYPE_A double
#define GENERIC_TYPE_B double
#define GENERIC_TYPE_C double
#define INNERPROD_FUNCTION innerprod_double_double
#if SLANG_HAS_COMPLEX
# define INNERPROD_COMPLEX_A innerprod_complex_double
# define INNERPROD_A_COMPLEX innerprod_double_complex
#endif
#include "slarrfun.inc"

#define GENERIC_TYPE_A double
#define GENERIC_TYPE_B float
#define GENERIC_TYPE_C double
#define INNERPROD_FUNCTION innerprod_double_float
#include "slarrfun.inc"

#define GENERIC_TYPE_A float
#define GENERIC_TYPE_B double
#define GENERIC_TYPE_C double
#define INNERPROD_FUNCTION innerprod_float_double
#include "slarrfun.inc"

/* Finally pick up the complex_complex multiplication
 * and do the integers
 */
#if SLANG_HAS_COMPLEX
# define INNERPROD_COMPLEX_COMPLEX innerprod_complex_complex
#endif
#define GENERIC_TYPE int
#define TRANSPOSE_2D_ARRAY transpose_ints
#include "slarrfun.inc"

#if SIZEOF_LONG != SIZEOF_INT
# define GENERIC_TYPE long
# define TRANSPOSE_2D_ARRAY transpose_longs
# include "slarrfun.inc"
#else
# define transpose_longs transpose_ints
#endif

#if SIZEOF_SHORT != SIZEOF_INT
# define GENERIC_TYPE short
# define TRANSPOSE_2D_ARRAY transpose_shorts
# include "slarrfun.inc"
#else
# define transpose_shorts transpose_ints
#endif

#define GENERIC_TYPE char
#define TRANSPOSE_2D_ARRAY transpose_chars
#include "slarrfun.inc"

/* This routine works only with linear arrays */
static SLang_Array_Type *transpose (SLang_Array_Type *at)
{
   int dims [SLARRAY_MAX_DIMS];
   int *max_dims;
   unsigned int num_dims;
   SLang_Array_Type *bt;
   int i;
   unsigned int sizeof_type;
   int is_ptr;
   char *b_data;

   max_dims = at->dims;
   num_dims = at->num_dims;

   if ((at->num_elements == 0)
       || (num_dims == 1))
     {
	bt = SLang_duplicate_array (at);
	if (num_dims == 1) bt->num_dims = 2;
	goto transpose_dims;
     }

   /* For numeric arrays skip the overhead below */
   if (num_dims == 2)
     {
	bt = allocate_transposed_array (at);
	if (bt == NULL) return NULL;

	switch (at->data_type)
	  {
	   case SLANG_INT_TYPE:
	   case SLANG_UINT_TYPE:
	     return transpose_ints (at, bt);
	   case SLANG_DOUBLE_TYPE:
	    return transpose_doubles (at, bt);
	   case SLANG_FLOAT_TYPE:
	     return transpose_floats (at, bt);
	   case SLANG_CHAR_TYPE:
	   case SLANG_UCHAR_TYPE:
	     return transpose_chars (at, bt);
	   case SLANG_LONG_TYPE:
	   case SLANG_ULONG_TYPE:
	     return transpose_longs (at, bt);
	   case SLANG_SHORT_TYPE:
	   case SLANG_USHORT_TYPE:
	     return transpose_shorts (at, bt);
	  }
     }
   else
     {
	bt = SLang_create_array (at->data_type, 0, NULL, max_dims, num_dims);
	if (bt == NULL) return NULL;
     }

   sizeof_type = at->sizeof_type;
   is_ptr = (at->flags & SLARR_DATA_VALUE_IS_POINTER);

   memset ((char *)dims, 0, sizeof(dims));

   b_data = (char *) bt->data;

   do
     {
	if (-1 == _SLarray_aget_transfer_elem (at, dims, (VOID_STAR) b_data,
					       sizeof_type, is_ptr))
	  {
	     SLang_free_array (bt);
	     return NULL;
	  }
	b_data += sizeof_type;
     }
   while (0 == next_transposed_index (dims, max_dims, num_dims));

   transpose_dims:

   num_dims = bt->num_dims;
   for (i = 0; i < (int) num_dims; i++)
     bt->dims[i] = max_dims [num_dims - i - 1];

   return bt;
}

static void array_transpose (SLang_Array_Type *at)
{
   if (NULL != (at = transpose (at)))
     (void) SLang_push_array (at, 1);
}

static int get_inner_product_parms (SLang_Array_Type *a, int *dp,
				    unsigned int *loops, unsigned int *other)
{
   int num_dims;
   int d;
   
   d = *dp;
   
   num_dims = (int)a->num_dims;
   if (num_dims == 0) 
     {
	SLang_verror (SL_INVALID_PARM, "Inner-product operation requires an array of at least 1 dimension.");
	return -1;
     }

   /* An index of -1 refers to last dimension */
   if (d == -1)
     d += num_dims;
   *dp = d;

   if (a->num_elements == 0)
     {				       /* [] # [] ==> [] */
	*loops = *other = 0;
	return 0;
     }

   *loops = a->num_elements / a->dims[d];

   if (d == 0)
     {
	*other = *loops;  /* a->num_elements / a->dims[0]; */
	return 0;
     }
   
   *other = a->dims[d];
   return 0;
}

/* This routines takes two arrays A_i..j and B_j..k and produces a third
 * via C_i..k = A_i..j B_j..k.
 * 
 * If A is a vector, and B is a 2-d matrix, then regard A as a 2-d matrix
 * with 1-column.
 */
static void do_inner_product (void)
{
   SLang_Array_Type *a, *b, *c;
   void (*fun)(SLang_Array_Type *, SLang_Array_Type *, SLang_Array_Type *,
	       unsigned int, unsigned int, unsigned int, unsigned int, 
	       unsigned int);
   unsigned char c_type;
   int dims[SLARRAY_MAX_DIMS];
   int status;
   unsigned int a_loops, b_loops, b_inc, a_stride;
   int ai_dims, i, j;
   unsigned int num_dims, a_num_dims, b_num_dims;
   int ai, bi;

   /* The result of a inner_product will be either a float, double, or
    * a complex number.
    * 
    * If an integer array is used, it will be promoted to a float.
    */
   
   switch (SLang_peek_at_stack1 ())
     {
      case SLANG_DOUBLE_TYPE:
	if (-1 == SLang_pop_array_of_type (&b, SLANG_DOUBLE_TYPE))
	  return;
	break;

#if SLANG_HAS_COMPLEX
      case SLANG_COMPLEX_TYPE:
	if (-1 == SLang_pop_array_of_type (&b, SLANG_COMPLEX_TYPE))
	  return;
	break;
#endif
      case SLANG_FLOAT_TYPE:
      default:
	if (-1 == SLang_pop_array_of_type (&b, SLANG_FLOAT_TYPE))
	  return;
	break;
     }

   switch (SLang_peek_at_stack1 ())
     {
      case SLANG_DOUBLE_TYPE:
	status = SLang_pop_array_of_type (&a, SLANG_DOUBLE_TYPE);
	break;

#if SLANG_HAS_COMPLEX
      case SLANG_COMPLEX_TYPE:
	status = SLang_pop_array_of_type (&a, SLANG_COMPLEX_TYPE);
	break;
#endif
      case SLANG_FLOAT_TYPE:
      default:
	status = SLang_pop_array_of_type (&a, SLANG_FLOAT_TYPE);
	break;
     }
   
   if (status == -1)
     {
	SLang_free_array (b);
	return;
     }
   
   ai = -1;			       /* last index of a */
   bi = 0;			       /* first index of b */
   if ((-1 == get_inner_product_parms (a, &ai, &a_loops, &a_stride))
       || (-1 == get_inner_product_parms (b, &bi, &b_loops, &b_inc)))
     {
	SLang_verror (SL_TYPE_MISMATCH, "Array dimensions are not compatible for inner-product");
	goto free_and_return;
     }
       
   a_num_dims = a->num_dims;
   b_num_dims = b->num_dims;

   /* Coerse a 1-d vector to 2-d */
   if ((a_num_dims == 1) 
       && (b_num_dims == 2)
       && (a->num_elements))
     {
	a_num_dims = 2;
	ai = 1;
	a_loops = a->num_elements;
	a_stride = 1;
     }

   if ((ai_dims = a->dims[ai]) != b->dims[bi])
     {
	SLang_verror (SL_TYPE_MISMATCH, "Array dimensions are not compatible for inner-product");
	goto free_and_return;
     }

   num_dims = a_num_dims + b_num_dims - 2;
   if (num_dims > SLARRAY_MAX_DIMS)
     {
	SLang_verror (SL_NOT_IMPLEMENTED,
		      "Inner-product result exceed max allowed dimensions");
	goto free_and_return;
     }

   if (num_dims)
     {
	j = 0;
	for (i = 0; i < (int)a_num_dims; i++)
	  if (i != ai) dims [j++] = a->dims[i];
	for (i = 0; i < (int)b_num_dims; i++)
	  if (i != bi) dims [j++] = b->dims[i];
     }
   else
     {
	/* a scalar */
	num_dims = 1;
	dims[0] = 1;
     }

   c_type = 0; fun = NULL;
   switch (a->data_type)
     {
      case SLANG_FLOAT_TYPE:
	switch (b->data_type)
	  {
	   case SLANG_FLOAT_TYPE:
	     c_type = SLANG_FLOAT_TYPE;
	     fun = innerprod_float_float;
	     break;
	   case SLANG_DOUBLE_TYPE:
	     c_type = SLANG_DOUBLE_TYPE;
	     fun = innerprod_float_double;
	     break;
#if SLANG_HAS_COMPLEX
	   case SLANG_COMPLEX_TYPE:
	     c_type = SLANG_COMPLEX_TYPE;
	     fun = innerprod_float_complex;
	     break;
#endif
	  }
	break;
      case SLANG_DOUBLE_TYPE:
	switch (b->data_type)
	  {
	   case SLANG_FLOAT_TYPE:
	     c_type = SLANG_DOUBLE_TYPE;
	     fun = innerprod_double_float;
	     break;
	   case SLANG_DOUBLE_TYPE:
	     c_type = SLANG_DOUBLE_TYPE;
	     fun = innerprod_double_double;
	     break;
#if SLANG_HAS_COMPLEX
	   case SLANG_COMPLEX_TYPE:
	     c_type = SLANG_COMPLEX_TYPE;
	     fun = innerprod_double_complex;
	     break;
#endif
	  }
	break;
#if SLANG_HAS_COMPLEX
      case SLANG_COMPLEX_TYPE:
	c_type = SLANG_COMPLEX_TYPE;
	switch (b->data_type)
	  {
	   case SLANG_FLOAT_TYPE:
	     fun = innerprod_complex_float;
	     break;
	   case SLANG_DOUBLE_TYPE:
	     fun = innerprod_complex_double;
	     break;
	   case SLANG_COMPLEX_TYPE:
	     fun = innerprod_complex_complex;
	     break;
	  }
	break;
#endif
      default:
	break;
     }

   if (NULL == (c = SLang_create_array (c_type, 0, NULL, dims, num_dims)))
     goto free_and_return;

   (*fun)(a, b, c, a_loops, a_stride, b_loops, b_inc, ai_dims);

   (void) SLang_push_array (c, 1);
   /* drop */

   free_and_return:
   SLang_free_array (a);
   SLang_free_array (b);
}



static SLang_Intrin_Fun_Type Array_Fun_Table [] =
{
   MAKE_INTRINSIC_1("transpose", array_transpose, SLANG_VOID_TYPE, SLANG_ARRAY_TYPE),
   SLANG_END_INTRIN_FUN_TABLE
};

int SLang_init_array (void)
{
   if (-1 == SLadd_intrin_fun_table (Array_Fun_Table, "__SLARRAY__"))
     return -1;
#if SLANG_HAS_FLOAT
   _SLang_Matrix_Multiply = do_inner_product;
#endif
   return 0;
}

