/* -*- mode: C -*- */

/* Some "inline" functions for generic scalar types */

#ifdef TRANSPOSE_2D_ARRAY
static SLang_Array_Type *TRANSPOSE_2D_ARRAY (SLang_Array_Type *at, SLang_Array_Type *bt)
{
   GENERIC_TYPE *a_data, *b_data;
   int nr, nc, i;

   nr = at->dims[0];
   nc = at->dims[1];

   a_data = (GENERIC_TYPE *) at->data;
   b_data = (GENERIC_TYPE *) bt->data;

   for (i = 0; i < nr; i++)
     {
	GENERIC_TYPE *offset = b_data + i;
	int j;
	for (j = 0; j < nc; j++)
	  {
	     *offset = *a_data++;
	     offset += nr;
	  }
     }
   return bt;
}
#undef TRANSPOSE_2D_ARRAY
#endif


#ifdef INNERPROD_FUNCTION

static void INNERPROD_FUNCTION
  (SLang_Array_Type *at, SLang_Array_Type *bt, SLang_Array_Type *ct,
   unsigned int a_loops, unsigned int a_stride,
   unsigned int b_loops, unsigned int b_inc,
   unsigned int inner_loops)
{
   GENERIC_TYPE_A *a;
   GENERIC_TYPE_B *b;
   GENERIC_TYPE_C *c;

   c = (GENERIC_TYPE_C *) ct->data;
   b = (GENERIC_TYPE_B *) bt->data;
   a = (GENERIC_TYPE_A *) at->data;
   
   while (a_loops--)
     {
	GENERIC_TYPE_B *bb;
	unsigned int j;

	bb = b;

	for (j = 0; j < inner_loops; j++)
	  {
	     double x = (double) a[j];

	     if (x != 0.0)
	       {
		  unsigned int k;

		  for (k = 0; k < b_loops; k++)
		    c[k] += x * bb[k];
	       }
	     bb += b_inc;
	  }
	c += b_loops;
	a += a_stride;
     }
}
#undef INNERPROD_FUNCTION

#undef GENERIC_TYPE_A
#undef GENERIC_TYPE_B
#undef GENERIC_TYPE_C
#endif

#ifdef INNERPROD_COMPLEX_A
static void INNERPROD_COMPLEX_A
  (SLang_Array_Type *at, SLang_Array_Type *bt, SLang_Array_Type *ct,
   unsigned int a_loops, unsigned int a_stride,
   unsigned int b_loops, unsigned int b_inc,
   unsigned int inner_loops)
{
   double *a;
   GENERIC_TYPE *b;
   double *c;

   c = (double *) ct->data;
   b = (GENERIC_TYPE *) bt->data;
   a = (double *) at->data;
   
   a_stride *= 2;

   while (a_loops--)
     {
	GENERIC_TYPE *bb;
	unsigned int bb_loops;

	bb = b;
	bb_loops = b_loops;
	
	while (bb_loops--)
	  {
	     double real_sum;
	     double imag_sum;
	     unsigned int iloops;
	     double *aa;
	     GENERIC_TYPE *bbb;
	     
	     aa = a;
	     bbb = bb;
	     iloops = inner_loops;

	     real_sum = 0.0;
	     imag_sum = 0.0;
	     while (iloops--)
	       {
		  real_sum += aa[0] * (double)bbb[0];
		  imag_sum += aa[1] * (double)bbb[0];
		  aa += 2;
		  bbb += b_inc;
	       }

	     *c++ = real_sum;
	     *c++ = imag_sum;
	     bb++;
	  }

	a += a_stride;
     }
}

static void INNERPROD_A_COMPLEX
  (SLang_Array_Type *at, SLang_Array_Type *bt, SLang_Array_Type *ct,
   unsigned int a_loops, unsigned int a_stride,
   unsigned int b_loops, unsigned int b_inc,
   unsigned int inner_loops)
{
   GENERIC_TYPE *a;
   double *b;
   double *c;

   c = (double *) ct->data;
   b = (double *) bt->data;
   a = (GENERIC_TYPE *) at->data;
   
   b_inc *= 2;

   while (a_loops--)
     {
	double *bb;
	unsigned int bb_loops;

	bb = b;
	bb_loops = b_loops;
	
	while (bb_loops--)
	  {
	     double real_sum;
	     double imag_sum;
	     unsigned int iloops;
	     GENERIC_TYPE *aa;
	     double *bbb;

	     aa = a;
	     bbb = bb;
	     iloops = inner_loops;

	     real_sum = 0.0;
	     imag_sum = 0.0;
	     while (iloops--)
	       {
		  real_sum += (double)aa[0] * bbb[0];
		  imag_sum += (double)aa[0] * bbb[1];
		  aa += 1;
		  bbb += b_inc;
	       }

	     *c++ = real_sum;
	     *c++ = imag_sum;
	     bb += 2;
	  }

	a += a_stride;
     }
}

#undef INNERPROD_A_COMPLEX
#undef INNERPROD_COMPLEX_A
#endif				       /* INNERPROD_COMPLEX_A */


#ifdef INNERPROD_COMPLEX_COMPLEX
static void INNERPROD_COMPLEX_COMPLEX
  (SLang_Array_Type *at, SLang_Array_Type *bt, SLang_Array_Type *ct,
   unsigned int a_loops, unsigned int a_stride,
   unsigned int b_loops, unsigned int b_inc,
   unsigned int inner_loops)
{
   double *a;
   double *b;
   double *c;

   c = (double *) ct->data;
   b = (double *) bt->data;
   a = (double *) at->data;
   
   a_stride *= 2;
   b_inc *= 2;

   while (a_loops--)
     {
	double *bb;
	unsigned int bb_loops;

	bb = b;
	bb_loops = b_loops;
	
	while (bb_loops--)
	  {
	     double real_sum;
	     double imag_sum;
	     unsigned int iloops;
	     double *aa;
	     double *bbb;

	     aa = a;
	     bbb = bb;
	     iloops = inner_loops;

	     real_sum = 0.0;
	     imag_sum = 0.0;
	     while (iloops--)
	       {
		  real_sum += aa[0]*bbb[0] - aa[1]*bbb[1];
		  imag_sum += aa[0]*bbb[1] + aa[1]*bbb[0];
		  aa += 2;
		  bbb += b_inc;
	       }

	     *c++ = real_sum;
	     *c++ = imag_sum;
	     bb += 2;
	  }

	a += a_stride;
     }
}
#undef INNERPROD_COMPLEX_COMPLEX
#endif

#ifdef GENERIC_TYPE
# undef GENERIC_TYPE
#endif
