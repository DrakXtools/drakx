/* -*- mode: C; mode: fold; -*- */
/* Standard intrinsic functions for S-Lang.  Included here are string
   and array operations */
/* Copyright (c) 1992, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

#include "slinclud.h"
/*{{{ Include Files */

#include <time.h>

#ifndef __QNX__
# if defined(__GO32__) || defined(__WATCOMC__)
#  include <dos.h>
#  include <bios.h>
# endif
#endif

#if SLANG_HAS_FLOAT
# include <math.h>
#endif

#include "slang.h"
#include "_slang.h"

/*}}}*/

/* builtin stack manipulation functions */
int SLdo_pop(void) /*{{{*/
{
   return SLdo_pop_n (1);
}

/*}}}*/

int SLdo_pop_n (unsigned int n)
{
   SLang_Object_Type x;

   while (n--)
     {
	if (SLang_pop(&x)) return -1;
	SLang_free_object (&x);
     }

   return 0;
}

static void do_dup(void) /*{{{*/
{
   (void) SLdup_n (1);
}

/*}}}*/

static int length_cmd (void)
{
   SLang_Class_Type *cl;
   SLang_Object_Type obj;
   VOID_STAR p;
   unsigned int length;
   int len;

   if (-1 == SLang_pop (&obj))
     return -1;

   cl = _SLclass_get_class (obj.data_type);
   p = _SLclass_get_ptr_to_value (cl, &obj);

   len = 1;
   if (cl->cl_length != NULL)
     {
	if (0 == (*cl->cl_length)(obj.data_type, p, &length))
	  len = (int) length;
	else
	  len = -1;
     }

   SLang_free_object (&obj);
   return len;
}

/* convert integer to a string of length 1 */
static void char_cmd (int *x) /*{{{*/
{
   char ch, buf[2];

   ch = (char) *x;
   buf[0] = ch;
   buf[1] = 0;
   SLang_push_string (buf);
}

/*}}}*/

/* format object into a string and returns slstring */
char *_SLstringize_object (SLang_Object_Type *obj) /*{{{*/
{
   SLang_Class_Type *cl;
   unsigned char stype;
   VOID_STAR p;
   char *s, *s1;

   stype = obj->data_type;
   p = (VOID_STAR) &obj->v.ptr_val;

   cl = _SLclass_get_class (stype);

   s = (*cl->cl_string) (stype, p);
   if (s != NULL)
     {
	s1 = SLang_create_slstring (s);
	SLfree (s);
	s = s1;
     }
   return s;
}
/*}}}*/

int SLang_run_hooks(char *hook, unsigned int num_args, ...)
{
   unsigned int i;
   va_list ap;

   if (SLang_Error) return -1;

   if (0 == SLang_is_defined (hook))
     return 0;

   (void) SLang_start_arg_list ();
   va_start (ap, num_args);
   for (i = 0; i < num_args; i++)
     {
	char *arg;

	arg = va_arg (ap, char *);
	if (-1 == SLang_push_string (arg))
	  break;
     }
   va_end (ap);
   (void) SLang_end_arg_list ();

   if (SLang_Error) return -1;
   return SLang_execute_function (hook);
}

static void intrin_getenv_cmd (char *s)
{
   SLang_push_string (getenv (s));
}

#ifdef HAVE_PUTENV
static void intrin_putenv (void) /*{{{*/
{
   char *s;

   /* Some putenv implementations required malloced strings. */
   if (SLpop_string(&s)) return;

   if (putenv (s))
     {
	SLang_Error = SL_INTRINSIC_ERROR;
	SLfree (s);
     }

   /* Note that s is NOT freed */
}

/*}}}*/

#endif

static void lang_print_stack (void) /*{{{*/
{
   char buf[32];
   unsigned int n;

   n = (unsigned int) (_SLStack_Pointer - _SLRun_Stack);
   while (n)
     {
	n--;
	sprintf (buf, "(%u)", n);
	_SLdump_objects (buf, _SLRun_Stack + n, 1, 1);
     }
}

/*}}}*/

static void byte_compile_file (char *f, int *m)
{
   SLang_byte_compile_file (f, *m);
}

static void intrin_type_info1 (void)
{
   SLang_Object_Type obj;
   unsigned int type;

   if (-1 == SLang_pop (&obj))
     return;

   type = obj.data_type;
   if (type == SLANG_ARRAY_TYPE)
     type = obj.v.array_val->data_type;

   SLang_free_object (&obj);

   _SLang_push_datatype (type);
}

static void intrin_type_info (void)
{
   SLang_Object_Type obj;

   if (-1 == SLang_pop (&obj))
     return;

   _SLang_push_datatype (obj.data_type);
   SLang_free_object (&obj);
}

void _SLstring_intrinsic (void) /*{{{*/
{
   SLang_Object_Type x;
   char *s;

   if (SLang_pop (&x)) return;
   if (NULL != (s = _SLstringize_object (&x)))
     _SLang_push_slstring (s);

   SLang_free_object (&x);
}

/*}}}*/

static void intrin_typecast (void)
{
   unsigned char to_type;
   if (0 == _SLang_pop_datatype (&to_type))
     (void) SLclass_typecast (to_type, 0, 1);
}

#if SLANG_HAS_FLOAT
static void intrin_double (void)
{
   (void) SLclass_typecast (SLANG_DOUBLE_TYPE, 0, 1);
}

#endif

static void intrin_int (void) /*{{{*/
{
   (void) SLclass_typecast (SLANG_INT_TYPE, 0, 1);
}

/*}}}*/

static char *
intrin_function_name (void)
{
   if (NULL == _SLang_Current_Function_Name)
     return "";
   return _SLang_Current_Function_Name;
}

static void intrin_message (char *s)
{
   SLang_vmessage ("%s", s);
}

static void intrin_error (char *s)
{
   SLang_verror (SL_USER_ERROR, "%s", s);
}

static void intrin_pop_n (int *n)
{
   SLdo_pop_n ((unsigned int) *n);
}

static void intrin_reverse_stack (int *n)
{
   SLreverse_stack (*n);
}

static void intrin_roll_stack (int *n)
{
   SLroll_stack (*n);
}

static void usage (void)
{
   char *msg;

   _SLstrops_do_sprintf_n (SLang_Num_Function_Args - 1);   /* do not include format */

   if (-1 == SLang_pop_slstring (&msg))
     return;

   SLang_verror (SL_USAGE_ERROR, "Usage: %s", msg);
   SLang_free_slstring (msg);
}

/* Convert string to integer */
static int intrin_integer (char *s)
{
   int i;

   i = SLatoi ((unsigned char *) s);

   if (SLang_Error)
     SLang_verror (SL_TYPE_MISMATCH, "Unable to convert string to integer");
   return i;
}
/*}}}*/

static void guess_type (char *s)
{
   _SLang_push_datatype (SLang_guess_type(s));
}

static int load_file (char *s)
{
   if (-1 == SLang_load_file (s))
     return 0;
   return 1;
}

static void get_doc_string (char *file, char *topic)
{
   FILE *fp;
   char line[1024];
   unsigned int topic_len, str_len;
   char *str;
   char ch;

   if (NULL == (fp = fopen (file, "r")))
     {
	SLang_push_null ();
	return;
     }

   topic_len = strlen (topic);
   ch = *topic;

   while (1)
     {
	if (NULL == fgets (line, sizeof(line), fp))
	  {
	     fclose (fp);
	     (void) SLang_push_null ();
	     return;
	  }

	if ((ch == *line)
	    && (0 == strncmp (line, topic, topic_len))
	    && ((line[topic_len] == '\n') || (line [topic_len] == 0)
		|| (line[topic_len] == ' ') || (line[topic_len] == '\t')))
	  break;
     }

   if (NULL == (str = SLmake_string (line)))
     {
	fclose (fp);
	(void) SLang_push_null ();
	return;
     }
   str_len = strlen (str);

   while (NULL != fgets (line, sizeof (line), fp))
     {
	unsigned int len;
	char *new_str;

	ch = *line;
	if (ch == '#') continue;
	if (ch == '-') break;

	len = strlen (line);
	if (NULL == (new_str = SLrealloc (str, str_len + len + 1)))
	  {
	     SLfree (str);
	     str = NULL;
	     break;
	  }
	str = new_str;
	strcpy (str + str_len, line);
	str_len += len;
     }

   fclose (fp);

   (void) SLang_push_malloced_string (str);
}

static int push_string_array_elements (SLang_Array_Type *at)
{
   char **strs;
   unsigned int num;
   unsigned int i;

   if (at == NULL)
     return -1;
   
   strs = (char **)at->data;
   num = at->num_elements;
   for (i = 0; i < num; i++)
     {
	if (-1 == SLang_push_string (strs[i]))
	  {
	     SLdo_pop_n (i);
	     return -1;
	  }
     }
   SLang_push_integer ((int) num);
   return 0;
}

	
static void intrin_apropos (void)
{
   int num_args;
   char *pat;
   char *namespace_name;
   unsigned int flags;
   SLang_Array_Type *at;

   num_args = SLang_Num_Function_Args;

   if (-1 == SLang_pop_uinteger (&flags))
     return;
   if (-1 == SLang_pop_slstring (&pat))
     return;
   
   namespace_name = NULL;
   at = NULL;
   if (num_args == 3)
     {
	if (-1 == SLang_pop_slstring (&namespace_name))
	  goto free_and_return;
     }

   at = _SLang_apropos (namespace_name, pat, flags);
   if (num_args == 3)
     {
	(void) SLang_push_array (at, 0);
	goto free_and_return;
     }

   /* Maintain compatibility with old version of the function.  That version
    * did not take three arguments and returned everything to the stack.
    * Yuk.
    */
   (void) push_string_array_elements (at);

   free_and_return:
   /* NULLs ok */
   SLang_free_slstring (namespace_name);
   SLang_free_slstring (pat);
   SLang_free_array (at);
}

static int intrin_get_defines (void)
{
   int n = 0;
   char **s = _SLdefines;

   while (*s != NULL)
     {
	if (-1 == SLang_push_string (*s))
	  {
	     SLdo_pop_n ((unsigned int) n);
	     return -1;
	  }
	s++;
	n++;
     }
   return n;
}

static void intrin_get_reference (char *name)
{
   _SLang_push_ref (1, (VOID_STAR) _SLlocate_name (name));
}

#ifdef HAVE_SYS_UTSNAME_H
# include <sys/utsname.h>
#endif

static void uname_cmd (void)
{
#ifdef HAVE_UNAME
   struct utsname u;
   char *field_names [6];
   unsigned char field_types[6];
   VOID_STAR field_values [6];
   char *ptrs[6];
   int i;

   if (-1 == uname (&u))
     (void) SLang_push_null ();

   field_names[0] = "sysname"; ptrs[0] = u.sysname;
   field_names[1] = "nodename"; ptrs[1] = u.nodename;
   field_names[2] = "release"; ptrs[2] = u.release;
   field_names[3] = "version"; ptrs[3] = u.version;
   field_names[4] = "machine"; ptrs[4] = u.machine;

   for (i = 0; i < 5; i++)
     {
	field_types[i] = SLANG_STRING_TYPE;
	field_values[i] = (VOID_STAR) &ptrs[i];
     }

   if (0 == SLstruct_create_struct (5, field_names, field_types, field_values))
     return;
#endif

   SLang_push_null ();
}

static void uninitialize_ref_intrin (SLang_Ref_Type *ref)
{
   (void) _SLang_uninitialize_ref (ref);
}

static SLang_Intrin_Fun_Type SLang_Basic_Table [] = /*{{{*/
{
   MAKE_INTRINSIC_1("__is_initialized", _SLang_is_ref_initialized, SLANG_INT_TYPE, SLANG_REF_TYPE),
   MAKE_INTRINSIC_S("__get_reference", intrin_get_reference, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_1("__uninitialize", uninitialize_ref_intrin, SLANG_VOID_TYPE, SLANG_REF_TYPE),
   MAKE_INTRINSIC_SS("get_doc_string_from_file",  get_doc_string, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_SS("autoload",  SLang_autoload, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("is_defined",  SLang_is_defined, SLANG_INT_TYPE),
   MAKE_INTRINSIC_0("string",  _SLstring_intrinsic, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("uname", uname_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("getenv",  intrin_getenv_cmd, SLANG_VOID_TYPE),
#ifdef HAVE_PUTENV
   MAKE_INTRINSIC_0("putenv",  intrin_putenv, SLANG_VOID_TYPE),
#endif
   MAKE_INTRINSIC_S("evalfile",  load_file, SLANG_INT_TYPE),
   MAKE_INTRINSIC_I("char",  char_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("eval",  SLang_load_string, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("dup",  do_dup, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("integer",  intrin_integer, SLANG_INT_TYPE),
   MAKE_INTRINSIC_S("system",  SLsystem, SLANG_INT_TYPE),
   MAKE_INTRINSIC_0("_apropos",  intrin_apropos, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("_trace_function",  _SLang_trace_fun, SLANG_VOID_TYPE),
#if SLANG_HAS_FLOAT
   MAKE_INTRINSIC_S("atof", _SLang_atof, SLANG_DOUBLE_TYPE),
   MAKE_INTRINSIC_0("double", intrin_double, SLANG_VOID_TYPE),
#endif
   MAKE_INTRINSIC_0("int",  intrin_int, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("typecast", intrin_typecast, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("_stkdepth", _SLstack_depth, SLANG_INT_TYPE),
   MAKE_INTRINSIC_I("_stk_reverse", intrin_reverse_stack, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("typeof", intrin_type_info, VOID_TYPE),
   MAKE_INTRINSIC_0("_typeof", intrin_type_info1, VOID_TYPE),
   MAKE_INTRINSIC_I("_pop_n", intrin_pop_n, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("_print_stack", lang_print_stack, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_I("_stk_roll", intrin_roll_stack, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_SI("byte_compile_file", byte_compile_file, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("_clear_error", _SLang_clear_error, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("_function_name", intrin_function_name, SLANG_STRING_TYPE),
#if SLANG_HAS_FLOAT
   MAKE_INTRINSIC_S("set_float_format", _SLset_double_format, SLANG_VOID_TYPE),
#endif
   MAKE_INTRINSIC_S("_slang_guess_type", guess_type, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("error", intrin_error, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("message", intrin_message, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("__get_defined_symbols", intrin_get_defines, SLANG_INT_TYPE),
   MAKE_INTRINSIC_I("__pop_args", _SLstruct_pop_args, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_1("__push_args", _SLstruct_push_args, SLANG_VOID_TYPE, SLANG_ARRAY_TYPE),
   MAKE_INTRINSIC_0("usage", usage, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("implements", _SLang_implements_intrinsic, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("use_namespace", _SLang_use_namespace_intrinsic, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("current_namespace", _SLang_cur_namespace_intrinsic, SLANG_STRING_TYPE),
   MAKE_INTRINSIC_0("length", length_cmd, SLANG_INT_TYPE),
   SLANG_END_INTRIN_FUN_TABLE
};

/*}}}*/

#ifdef SLANG_DOC_DIR
char *SLang_Doc_Dir = SLANG_DOC_DIR;
#else
char *SLang_Doc_Dir = "";
#endif

static SLang_Intrin_Var_Type Intrin_Vars[] =
{
   MAKE_VARIABLE("_debug_info", &_SLang_Compile_Line_Num_Info, SLANG_INT_TYPE, 0),
   MAKE_VARIABLE("_auto_declare", &_SLang_Auto_Declare_Globals, SLANG_INT_TYPE, 0),
   MAKE_VARIABLE("_traceback", &SLang_Traceback, SLANG_INT_TYPE, 0),
   MAKE_VARIABLE("_slangtrace", &_SLang_Trace, SLANG_INT_TYPE, 0),
   MAKE_VARIABLE("_slang_version", &SLang_Version, SLANG_INT_TYPE, 1),
   MAKE_VARIABLE("_slang_version_string", &SLang_Version_String, SLANG_STRING_TYPE, 1),
   MAKE_VARIABLE("_NARGS", &SLang_Num_Function_Args, SLANG_INT_TYPE, 1),
   MAKE_VARIABLE("_slang_doc_dir", &SLang_Doc_Dir, SLANG_STRING_TYPE, 1),
   MAKE_VARIABLE("NULL", NULL, SLANG_NULL_TYPE, 1),
   SLANG_END_INTRIN_VAR_TABLE
};

int SLang_init_slang (void) /*{{{*/
{
   char name[3];
   unsigned int i;
   char **s;
   static char *sys_defines [] =
     {
#if defined(__os2__)
	"OS2",
#endif
#if defined(__MSDOS__)
	"MSDOS",
#endif
#if defined(__WIN16__)
	"WIN16",
#endif
#if defined (__WIN32__)
	"WIN32",
#endif
#if defined(__NT__)
	"NT",
#endif
#if defined (VMS)
	"VMS",
#endif
#ifdef REAL_UNIX_SYSTEM
	"UNIX",
#endif
#if SLANG_HAS_FLOAT
	"SLANG_DOUBLE_TYPE",
#endif
	NULL
     };

   if (-1 == _SLregister_types ()) return -1;

   if ((-1 == SLadd_intrin_fun_table(SLang_Basic_Table, NULL))
       || (-1 == SLadd_intrin_var_table (Intrin_Vars, NULL))
       || (-1 == _SLang_init_slstrops ())
       || (-1 == _SLang_init_sltime ())
       || (-1 == _SLstruct_init ())
#if SLANG_HAS_COMPLEX
       || (-1 == _SLinit_slcomplex ())
#endif
#if SLANG_HAS_ASSOC_ARRAYS
       || (-1 == SLang_init_slassoc ())
#endif
       )
     return -1;

   SLadd_global_variable (SLANG_SYSTEM_NAME);

   s = sys_defines;
   while (*s != NULL)
     {
	if (-1 == SLdefine_for_ifdef (*s)) return -1;
	s++;
     }

   /* give temp global variables $0 --> $9 */
   name[2] = 0; name[0] = '$';
   for (i = 0; i < 10; i++)
     {
	name[1] = (char) (i + '0');
	SLadd_global_variable (name);
     }

   SLang_init_case_tables ();

   /* Now add a couple of macros */
   SLang_load_string (".(_NARGS 1 - Sprintf error)verror");
   SLang_load_string (".(_NARGS 1 - Sprintf message)vmessage");

   if (SLang_Error)
     return -1;

   return 0;
}

/*}}}*/

int SLang_set_argc_argv (int argc, char **argv)
{
   static int this_argc;
   static char **this_argv;
   int i;

   if (argc < 0) argc = 0;
   this_argc = argc;

   if (NULL == (this_argv = (char **) SLmalloc ((argc + 1) * sizeof (char *))))
     return -1;
   memset ((char *) this_argv, 0, sizeof (char *) * (argc + 1));

   for (i = 0; i < argc; i++)
     {
	if (NULL == (this_argv[i] = SLang_create_slstring (argv[i])))
	  goto return_error;
     }

   if (-1 == SLadd_intrinsic_variable ("__argc", (VOID_STAR)&this_argc,
				       SLANG_INT_TYPE, 1))
     goto return_error;

   if (-1 == SLang_add_intrinsic_array ("__argv", SLANG_STRING_TYPE, 1,
					(VOID_STAR) this_argv, 1, argc))
     goto return_error;

   return 0;

   return_error:
   for (i = 0; i < argc; i++)
     SLang_free_slstring (this_argv[i]);   /* NULL ok */
   SLfree ((char *) this_argv);

   return -1;
}
