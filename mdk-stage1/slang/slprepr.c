/* Copyright (c) 1996, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

/*--------------------------------*-C-*---------------------------------*
 * File:	slprepr.c
 *
 * preprocessing routines
 */
/*{{{ notes: */
/*
 * various preprocessing tokens supported
 *
 * #ifdef  TOKEN1 TOKEN2 ...
 *	- True if any of TOKEN1 TOKEN2 ... are defined
 *
 * #ifndef TOKEN1 TOKEN2 ...
 *	- True if none of TOKEN1 TOKEN2 ... are defined
 *
 * #iftrue
 * #ifnfalse
 *	- always True
 *
 * #iffalse
 * #ifntrue
 *	- always False
 *
 * #if$ENV
 *	- True if the enviroment variable ENV is set
 *
 * #ifn$ENV
 *	- True if the enviroment variable ENV is not set
 *
 * #if$ENV TOKEN1 TOKEN2 ...
 *	- True if the contents of enviroment variable ENV match
 *	  any of TOKEN1 TOKEN2 ...
 *
 * #ifn$ENV TOKEN1 TOKEN2 ...
 *	- True if the contents of enviroment variable ENV do not match
 *	  any of TOKEN1 TOKEN2 ...
 *
 *	NB: For $ENV, the tokens may contain wildcard characters:
 *		'?' - match any single character
 *		'*' - match any number of characters
 *
 * #elif...
 * #else
 * #endif
 *
 *
 * mj olesen
 *----------------------------------------------------------------------*/
/*}}}*/
/*{{{ includes: */
#include "slinclud.h"

#include "slang.h"
#include "_slang.h"
/*}}}*/

int (*SLprep_exists_hook) (char *, char);
int (*_SLprep_eval_hook) (char *);

/*{{{ SLprep_open_prep (), SLprep_close_prep () */
int SLprep_open_prep (SLPreprocess_Type *pt)
{
   pt->this_level = 0;
   pt->exec_level = 0;
   pt->prev_exec_level = 0;
   pt->comment_char = '%';
   pt->preprocess_char = '#';
   pt->flags = 0;
   return 0;
}

void SLprep_close_prep (SLPreprocess_Type *pt)
{
   (void) pt;
}
/*}}}*/

/*{{{ SLwildcard () */
/*----------------------------------------------------------------------*
 * Does `string' match `pattern' ?
 *
 * '*' in pattern matches any sub-string (including the null string)
 * '?' matches any single char.
 *
 * Code taken from that donated by Paul Hudson <paulh@harlequin.co.uk>
 * to the fvwm project.
 * It is public domain, no strings attached. No guarantees either.
 *----------------------------------------------------------------------*/
static int SLwildcard (char *pattern, char *string)
{
   if (pattern == NULL || *pattern == '\0' || !strcmp (pattern, "*"))
     return 1;
   else if (string == NULL)
     return 0;

   while (*pattern && *string) switch (*pattern)
     {
      case '?':
	/* match any single character */
	pattern++;
	string++;
	break;

      case '*':
	/* see if rest of pattern matches any trailing */
	/* substring of the string. */
	if (*++pattern == '\0')
	  return 1;	/* trailing * must match rest */

	while (*string)
	  {
	     if (SLwildcard (pattern, string)) return 1;
	     string++;
	  }
	return 0;

	/* break; */

      default:
	if (*pattern == '\\')
	  {
	     if (*++pattern == '\0')
	       pattern--;	/* don't skip trailing backslash */
	  }
	if (*pattern++ != *string++) return 0;
	break;
     }

   return ((*string == '\0')
	   && ((*pattern == '\0') || !strcmp (pattern, "*")));
}
/*}}}*/

#if defined(__16_BIT_SYSTEM__)
# define MAX_DEFINES 10
#else
# define MAX_DEFINES 128
#endif

/* The extra one is for NULL termination */
char *_SLdefines [MAX_DEFINES + 1];

int SLdefine_for_ifdef (char *s)	/*{{{*/
{
   unsigned int i;

   for (i = 0; i < MAX_DEFINES; i++)
     {
	char *s1 = _SLdefines [i];

	if (s1 == s)
	  return 0;		       /* already defined (hashed string) */

	if (s1 != NULL)
	  continue;

	s = SLang_create_slstring (s);
	if (s == NULL)
	  return -1;

	_SLdefines[i] = s;
	return 0;
     }
   return -1;
}
/*}}}*/

/*{{{ static functions */
static int is_any_defined(char *buf, char comment)	/*{{{*/
{
   char *sys;
   unsigned int i;

   while (1)
     {
	register char ch;

	/* Skip whitespace */
	while (((ch = *buf) == ' ') || (ch == '\t'))
	  buf++;

	if ((ch == '\n') || (ch == 0) || (ch == comment))
	  return 0;

	i = 0;
	while (NULL != (sys = _SLdefines [i++]))
	  {
	     unsigned int n;

	     if (*sys != ch)
	       continue;

	     n = strlen (sys);
	     if (0 == strncmp (buf, sys, n))
	       {
		  char ch1 = *(buf + n);

		  if ((ch1 == '\n') || (ch1 == 0) ||
		      (ch1 == ' ') || (ch1 == '\t') || (ch1 == comment))
		    return 1;
	       }
	  }

	/* Skip past word */
	while (((ch = *buf) != ' ')
	       && (ch != '\n')
	       && (ch != 0)
	       && (ch != '\t')
	       && (ch != comment))
	  buf++;
     }
}
/*}}}*/

static unsigned char *tokenize (unsigned char *buf, char *token, unsigned int len)
{
   register char *token_end;

   token_end = token + (len - 1);      /* allow room for \0 */

   while ((token < token_end) && (*buf > ' '))
     *token++ = *buf++;

   if (*buf > ' ') return NULL;	/* token too long */

   *token = '\0';

   while ((*buf == ' ') || (*buf == '\t')) buf++;

   return buf;
}

static int is_env_defined (char *buf, char comment)	/*{{{*/
{
   char * env, token [32];

   if ((*buf <= ' ') || (*buf == comment)) return 0;	/* no token */

   if (NULL == (buf = (char *) tokenize ((unsigned char *) buf,
					 token, sizeof (token))))
     return 0;

   if (NULL == (env = getenv (token)))
     return 0;		/* ENV not defined */

   if ((*buf == '\0') || (*buf == '\n') || (*buf == comment))
     return 1;			/* no tokens, but getenv() worked */

   do
     {
	buf = (char *) tokenize ((unsigned char *) buf, token, sizeof (token));
	if (buf == NULL) return 0;

	if (SLwildcard (token, env))
	  return 1;
     }
   while (*buf && (*buf != '\n') && (*buf != comment));

   return 0;
}
/*}}}*/
/*}}}*/

int SLprep_line_ok (char *buf, SLPreprocess_Type *pt)	/*{{{*/
{
   int level, prev_exec_level, exec_level;

   if ((buf == NULL) || (pt == NULL)) return 1;

   if (*buf != pt->preprocess_char)
     {
	if (pt->this_level != pt->exec_level)
	  return 0;

	if (*buf == '\n') return pt->flags & SLPREP_BLANK_LINES_OK;
	if (*buf == pt->comment_char) return pt->flags & SLPREP_COMMENT_LINES_OK;

	return 1;
     }

   level = pt->this_level;
   exec_level = pt->exec_level;
   prev_exec_level = pt->prev_exec_level;

   buf++;

   /* Allow '#!' to pass.  This could be a shell script with something
    like '#! /local/bin/slang'  */
   if ((*buf == '!') && (pt->preprocess_char == '#'))
     return 0;

   /* Allow whitespace as in '#   ifdef'  */
   while ((*buf == ' ') || (*buf == '\t')) buf++;
   if (*buf < 'a') return (level == exec_level);

   if (!strncmp(buf, "endif", 5))
     {
	if (level == exec_level)
	  {
	     exec_level--;
	     prev_exec_level = exec_level;
	  }
	level--;
	if (level < prev_exec_level) prev_exec_level = level;
	goto done;
     }

   if ((buf[0] == 'e') && (buf[1] == 'l'))   /* else, elifdef, ... */
     {
	if ((level == exec_level + 1)
	    && (prev_exec_level != level))
	  {
	     /* We are in position to execute */
	     buf += 2;
	     if ((buf[0] == 's') && (buf[1] == 'e'))
	       {
		  /* "else" */
		  exec_level = level;
		  goto done;
	       }

	     /* drop through to ifdef testing.  First set variable
	      * to values appropriate for ifdef testing.
	      */
	     level--;		       /* now == to exec level */
	  }
	else
	  {
	     if (level == exec_level)
	       {
		  exec_level--;
	       }
	     goto done;
	  }
     }

   if ((buf[0] == 'i') && (buf[1] == 'f'))
     {
	int truth;

	if (level != exec_level)
	  {
	     /* Not interested */
	     level++;
	     goto done;
	  }

	level++;

	buf += 2;
	if (buf[0] == 'n')
	  {
	     truth = 0;
	     buf++;
	  }
	else truth = 1;

	if (!strncmp (buf, "def", 3))
	  truth = (truth == is_any_defined(buf + 3, pt->comment_char));

	else if (!strncmp (buf, "false", 5))
	  truth = !truth;

	else if (*buf == '$')
	  truth = (truth == is_env_defined (buf + 1, pt->comment_char));

	else if (!strncmp (buf, "exists", 6)
		 && (SLprep_exists_hook != NULL))
	  truth = (truth == (*SLprep_exists_hook)(buf + 6, pt->comment_char));

	else if (!strncmp (buf, "eval", 4)
		 && (_SLprep_eval_hook != NULL))
	  truth = (truth == (*_SLprep_eval_hook) (buf + 4));
			   
	else if (0 != strncmp (buf, "true", 4))
	  return 1;		       /* let it bomb */

	if (truth)
	  {
	     exec_level = level;
	     prev_exec_level = exec_level;
	  }
     }
   else return 1;  /* let it bomb. */

   done:

   if (exec_level < 0) return 1;

   pt->this_level = level;
   pt->exec_level = exec_level;
   pt->prev_exec_level = prev_exec_level;
   return 0;
}
/*}}}*/

/*{{{ main() - for testing only */
#if 0
int main ()
{
   char buf[1024];
   SLPreprocess_Type pt;

   SLprep_open_prep (&pt);

   SLdefine_for_ifdef ("UNIX");

   while (NULL != fgets (buf, sizeof (buf) - 1, stdin))
     {
	if (SLprep_line_ok (buf, &pt))
	  {
	     fputs (buf, stdout);
	  }
     }

   SLprep_close_prep (&pt);
   return 0;
}
#endif
/*}}}*/
