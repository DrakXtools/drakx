/* file intrinsics for S-Lang */
/* Copyright (c) 1992, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

#include "slinclud.h"

#if defined(__unix__) || (defined (__os2__) && defined (__EMX__))
# include <sys/types.h>
#endif

#ifdef HAVE_IO_H
# include <io.h>		       /* for chmod */
#endif

#if defined(__BORLANDC__)
# include <process.h>
# include <dos.h>
#endif

#ifdef HAVE_FCNTL_H
# include <fcntl.h>
#endif
#ifdef HAVE_SYS_FCNTL_H
# include <sys/fcntl.h>
#endif

#ifdef __unix__
# include <sys/file.h>
#endif

#if defined(__BORLANDC__)
# include <dir.h>
#endif

#if defined(_MSC_VER)
# include <io.h>
#endif

#if defined(__DECC) && defined(VMS)
# include <unixio.h>
# include <unixlib.h>
#endif

#ifdef VMS
# include <stat.h>
#else
# include <sys/stat.h>
#endif

#if defined(VMS)
# define USE_LISTDIR_INTRINSIC	0
#else
# define USE_LISTDIR_INTRINSIC	1
#endif

#if USE_LISTDIR_INTRINSIC

#if defined(__WIN32__)
# include <windows.h>
#else
# if defined(__OS2__) && defined(__IBMC__)
#  define INCL_DOS
#  define INCL_ERRORS
#  include <os2.h>
#  include <direct.h>
#  include <ctype.h>
# else
#  ifdef HAVE_DIRENT_H
#   include <dirent.h>
#  else
#   ifdef HAVE_DIRECT_H
#    include <direct.h>
#   else
#    define dirent direct
#    define NEED_D_NAMLEN
#    if HAVE_SYS_NDIR_H
#     include <sys/ndir.h>
#    endif
#    if HAVE_SYS_DIR_H
#     include <sys/dir.h>
#    endif
#    if HAVE_NDIR_H
#     include <ndir.h>
#    endif
#   endif
#  endif
# endif
#endif

#endif				       /* USE_LISTDIR_INTRINSIC */

#include <errno.h>

#include "slang.h"
#include "_slang.h"

static int push_stat_struct (struct stat *st, int opt_attrs)
{
   char *field_names [12];
   unsigned char field_types[12];
   VOID_STAR field_values [12];
   int int_values [12];
   unsigned int i;

   field_names [0] = "st_dev"; int_values [0] = (int) st->st_dev;
   field_names [1] = "st_ino"; int_values [1] = (int) st->st_ino;
   field_names [2] = "st_mode"; int_values [2] = (int) st->st_mode;
   field_names [3] = "st_nlink"; int_values [3] = (int) st->st_nlink;
   field_names [4] = "st_uid"; int_values [4] = (int) st->st_uid;
   field_names [5] = "st_gid"; int_values [5] = (int) st->st_gid;
   field_names [6] = "st_rdev"; int_values [6] = (int) st->st_rdev;
   field_names [7] = "st_size"; int_values [7] = (int) st->st_size;
   field_names [8] = "st_atime"; int_values [8] = (int) st->st_atime;
   field_names [9] = "st_mtime"; int_values [9] = (int) st->st_mtime;
   field_names [10] = "st_ctime"; int_values [10] = (int) st->st_ctime;

   field_names [11] = "st_opt_attrs"; int_values[11] = opt_attrs;

   for (i = 0; i < 12; i++)
     {
	field_types [i] = SLANG_INT_TYPE;
	field_values [i] = (VOID_STAR) (int_values + i);
     }

   return SLstruct_create_struct (12, field_names, field_types, field_values);
}

static void stat_cmd (char *file)
{
   struct stat st;
   int status;
   int opt_attrs;

   status = stat (file, &st);

#if defined(__MSDOS__) || defined(__WIN32__)
   if (status == -1)
     {
	unsigned int len = strlen (file);
	if (len && ((file[len-1] == '\\') || (file[len-1] == '/')))
	  {
	     file = SLmake_nstring (file, len-1);
	     if (file == NULL)
	       return;

	     status = stat (file, &st);
	     SLfree (file);
	  }
     }
#endif
   if (status == -1)
     {
	_SLerrno_errno = errno;
	SLang_push_null ();
	return;
     }

#ifdef __WIN32__
   opt_attrs = GetFileAttributes (file);
#else
   opt_attrs = 0;
#endif

   push_stat_struct (&st, opt_attrs);
}

static void lstat_cmd (char *file)
{
#ifdef HAVE_LSTAT
   struct stat st;
   int opt_attrs;

   if (-1 == lstat (file, &st))
     {
	_SLerrno_errno = errno;
	SLang_push_null ();
	return;
     }

#ifdef __WIN32__
   opt_attrs = GetFileAttributes (file);
#else
   opt_attrs = 0;
#endif
   
   push_stat_struct (&st, opt_attrs);
#else
   stat_cmd (file);
#endif
}

/* Well, it appears that on some systems, these are not defined.  Here I
 * provide them.  These are derived from the Linux stat.h file.
 */

#ifdef __os2__
# ifdef __IBMC__
/* IBM VA3 doesn't declare S_IFMT */
#  define	S_IFMT	(S_IFDIR | S_IFCHR | S_IFREG)
# endif
#endif

#ifndef S_ISLNK
# ifdef S_IFLNK
#   define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
# else
#   define S_ISLNK(m) 0
# endif
#endif

#ifndef S_ISREG
# ifdef S_IFREG
#   define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
# else
#   define S_ISREG(m) 0
# endif
#endif

#ifndef S_ISDIR
# ifdef S_IFDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
# else
#   define S_ISDIR(m) 0
# endif
#endif

#ifndef S_ISCHR
# ifdef S_IFCHR
#   define S_ISCHR(m) (((m) & S_IFMT) == S_IFCHR)
# else
#   define S_ISCHR(m) 0
# endif
#endif

#ifndef S_ISBLK
# ifdef S_IFBLK
#   define S_ISBLK(m) (((m) & S_IFMT) == S_IFBLK)
# else
#   define S_ISBLK(m) 0
# endif
#endif

#ifndef S_ISFIFO
# ifdef S_IFIFO
#   define S_ISFIFO(m) (((m) & S_IFMT) == S_IFIFO)
# else
#   define S_ISFIFO(m) 0
# endif
#endif

#ifndef S_ISSOCK
# ifdef S_IFSOCK
#   define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)
# else
#   define S_ISSOCK(m) 0
# endif
#endif

static char stat_is_cmd (char *what, int *mode_ptr)
{
   int ret;
   int st_mode = *mode_ptr;

   if (!strcmp (what, "sock")) ret = S_ISSOCK(st_mode);
   else if (!strcmp (what, "fifo")) ret = S_ISFIFO(st_mode);
   else if (!strcmp (what, "blk")) ret = S_ISBLK(st_mode);
   else if (!strcmp (what, "chr")) ret = S_ISCHR(st_mode);
   else if (!strcmp (what, "dir")) ret = S_ISDIR(st_mode);
   else if (!strcmp (what, "reg")) ret = S_ISREG(st_mode);
   else if (!strcmp (what, "lnk")) ret = S_ISLNK(st_mode);
   else
     {
	SLang_verror (SL_INVALID_PARM, "stat_is: Unrecognized type: %s", what);
	return -1;
     }

   return (char) (ret != 0);
}

#ifdef HAVE_READLINK
static void readlink_cmd (char *s)
{
   char buf[2048];
   int n;

   n = readlink (s, buf, sizeof (buf)-1);
   if (n == -1)
     {
	_SLerrno_errno = errno;
	s = NULL;
     }
   else
     {
	buf[n] = 0;
	s = buf;
     }

   (void) SLang_push_string (s);
}
#endif

static int chmod_cmd (char *file, int *mode)
{
   if (-1 == chmod(file, (mode_t) *mode))
     {
	_SLerrno_errno = errno;
	return -1;
     }
   return 0;
}

#ifdef HAVE_CHOWN
static int chown_cmd (char *file, int *owner, int *group)
{
   int ret;

   if (-1 == (ret = chown(file, (uid_t) *owner, (gid_t) *group)))
     _SLerrno_errno = errno;
   return ret;
}
#endif

/* add trailing slash to dir */
static void fixup_dir (char *dir)
{
#ifndef VMS
   int n;

   if ((n = strlen(dir)) > 1)
     {
	n--;
#if defined(IBMPC_SYSTEM)
      if ( dir[n] != '/' && dir[n] != '\\' )
      	strcat(dir, "\\" );
#else
      if (dir[n] != '/' )
      	strcat(dir, "/" );
#endif
     }
#endif /* !VMS */
}

static void slget_cwd (void)
{
   char cwd[1024];
   char *p;

#ifndef HAVE_GETCWD
   p = getwd (cwd);
#else
# if defined (__EMX__)
   p = _getcwd2(cwd, 1022);	       /* includes drive specifier */
# else
   p = getcwd(cwd, 1022);	       /* djggp includes drive specifier */
# endif
#endif

   if (p == NULL)
     {
	_SLerrno_errno = errno;
	SLang_push_null ();
	return;
     }

#ifndef VMS
#ifdef __GO32__
   /* You never know about djgpp since it favors unix */
     {
	char ch;
	p = cwd;
	while ((ch = *p) != 0)
	  {
	     if (ch == '/') *p = '\\';
	     p++;
	  }
     }
#endif
   fixup_dir (cwd);
#endif
   SLang_push_string (cwd);
}

static int chdir_cmd (char *s)
{
   int ret;

   while (-1 == (ret = chdir (s)))
     {
#ifdef EINTR
	if (errno == EINTR)
	  continue;
#endif
	_SLerrno_errno = errno;
	break;
     }
   return ret;
}

#ifdef VMS
static int remove_cmd (char *);
/* If the file looks like xxx, then change it to xxx.dir.  If
 * it looks like A:[B.xxx] then change it to A:[B]xxx.dir.
 */

static char *vms_convert_dirspec_to_vms_dir (char *str)
{
   char *s;
   char *version;
   unsigned int len;
   char *dot;

   len = strlen (str);

   version = strchr (str, ';');
   if (version == NULL)
     version = str + len;
   /* version points to the version of the input string */

   
   if (NULL == (s = SLmalloc (len + 8)))/* allow extra space to work with */
     return NULL;

   len = (unsigned int) (version - str);
   strncpy (s, str, len);
   s[len] = 0;
   str = s;
   
   /* Lowercase the whole thing */
   while (*s != 0)
     {
	*s = LOWER_CASE(*s);
	s++;
     }

   if ((s > str)
       && (s[-1] != ']'))
     {
	if ((s >= str + 4)
	    && (0 == strcmp (s - 4, ".dir")))
	  s -= 4;
	goto add_dir_version;
     }

   /* Check for one of two possibilities:
    * 
    *     dev:[x]   --> dev:x
    *     dev:[a.x] --> dev:[a]x
    */
   
   if (NULL == (dot = strchr (str, '.')))
     {
	/* First possibility */
	if (NULL == (s = strchr (str, '[')))
	  return str;		       /* let someone else figure this out */
	while (s[1] != ']')
	  {
	     s[0] = s[1];
	     s++;
	  }
	*s = 0;
	goto add_dir_version;
     }
   
   while (NULL != (s = strchr (dot + 1, '.')))
     dot = s;
   
   *dot = ']';
   s = str + (len - 1);
   
   /* Drop */

   add_dir_version:
   strcpy (s, ".dir");
   strcpy (s+4, version);
   return str;
}
#endif

static int rmdir_cmd (char *s)
{
#ifdef VMS
   int status;

   if (NULL == (s = vms_convert_dirspec_to_vms_dir (s)))
     return -1;
   
   status = remove_cmd (s);
   SLfree (s);
   
   return status;

#else
   int ret;

   while (-1 == (ret = rmdir (s)))
     {
#ifdef EINTR
	if (errno == EINTR)
	  continue;
#endif
	_SLerrno_errno = errno;
	break;
     }
   return ret;
#endif
}

static int remove_cmd (char *s)
{
   int ret;
#ifdef VMS
# define REMOVE delete
#else
# ifdef REAL_UNIX_SYSTEM
#  define REMOVE unlink
# else
#  define REMOVE remove
# endif
#endif

   while (-1 == (ret = REMOVE (s)))
     {
#ifdef EINTR
	if (errno == EINTR)
	  continue;
#endif
	_SLerrno_errno = errno;
	break;
     }
   return ret;
}

static int rename_cmd (char *oldpath, char *newpath)
{
   int ret;
   while (-1 == (ret = rename (oldpath, newpath)))
     {
#ifdef EINTR
	if (errno == EINTR)
	  continue;
#endif
	_SLerrno_errno = errno;
	break;
     }
   return ret;
}

static int mkdir_cmd (char *s, int *mode_ptr)
{
   int ret;

   (void) mode_ptr;
   errno = 0;

#if defined (__MSDOS__) && !defined(__GO32__)
# define MKDIR(x,y) mkdir(x)
#else
# if defined (__os2__) && !defined (__EMX__)
#  define MKDIR(x,y) mkdir(x)
# else
#  if defined (__WIN32__) && !defined (__CYGWIN32__)
#   define MKDIR(x,y) mkdir(x)
#  else
#   define MKDIR mkdir
#  endif
# endif
#endif

   while (-1 == (ret = MKDIR(s, *mode_ptr)))
     {
#ifdef EINTR
	if (errno == EINTR)
	  continue;
#endif
	_SLerrno_errno = errno;
	break;
     }
   return ret;
}

#ifdef HAVE_MKFIFO
static int mkfifo_cmd (char *path, int *mode)
{
   if (-1 == mkfifo (path, *mode))
     {
	_SLerrno_errno = errno;
	return -1;
     }
   return 0;
}
#endif

#if USE_LISTDIR_INTRINSIC

static void free_dir_list (char **list, unsigned int num)
{
   unsigned int i;

   if (list == NULL)
     return;

   for (i = 0; i < num; i++)
     SLang_free_slstring (list[i]);
   SLfree ((char *) list);
}

#if defined(__WIN32__) || defined(__os2__) && defined(__IBMC__)
static int build_dirlist (char *file, char *opt, char ***listp, unsigned int *nump, unsigned int *maxnum)
{
# ifdef __WIN32__
   DWORD status;
   HANDLE h;
   WIN32_FIND_DATA fd;
# else
   APIRET rc;
   FILESTATUS3 status;
   HDIR h;
   FILEFINDBUF3 fd;
   ULONG cFileNames;
# endif
   char *pat;
   unsigned int len;
   char **list;
   unsigned int num;
   unsigned int max_num;
   int hok;

   /* If an option is present, assume ok to list hidden files.  Later
    * I will formalize this.
    */
   hok = (opt != NULL);

# ifdef __WIN32__
   status = GetFileAttributes (file);
# else
   rc = DosQueryPathInfo(file, FIL_STANDARD, &status, sizeof(FILESTATUS3));
# endif


# ifdef __WIN32__
   if (status == (DWORD)-1)
     {
	_SLerrno_errno = ENOENT;
	return -1;
     }
   if (0 == (status & FILE_ATTRIBUTE_DIRECTORY))
     {
	_SLerrno_errno = ENOTDIR;
	return -1;
     }
# else
   if ((rc != 0) || (status.attrFile & FILE_DIRECTORY) == 0)
     {
	/* ENOTDIR isn't defined in VA3. */
	_SLerrno_errno = ENOENT;
	return -1;
     }
# endif

   len = strlen (file);
   pat = SLmalloc (len + 3);
   if (pat == NULL)
     return -1;

   strcpy (pat, file);
   file = pat;
   while (*file != 0)
     {
	if (*file == '/') *file = '\\';
	file++;
     }

   if (len && (pat[len-1] != '\\'))
     {
	pat[len] = '\\';
	len++;
     }
   pat[len++] = '*';
   pat[len] = 0;

   num = 0;
   max_num = 50;
   list = (char **)SLmalloc (max_num * sizeof(char *));
   if (list == NULL)
     {
	SLfree (pat);
	return -1;
     }

# ifdef __WIN32__
   h = FindFirstFile(pat, &fd);
   if (h == INVALID_HANDLE_VALUE)
     {
	if (ERROR_NO_MORE_FILES != GetLastError())
	  {
	     SLfree (pat);
	     SLfree ((char *)list);
	     return -1;
	  }
     }
# else
   h = HDIR_CREATE;
   cFileNames = 1;
   rc = DosFindFirst(pat, &h, FILE_READONLY | FILE_DIRECTORY |
		     FILE_ARCHIVED, &fd, sizeof(fd), &cFileNames, FIL_STANDARD);
   if (rc != 0)
     {
	if (rc != ERROR_NO_MORE_FILES)
	  {
	     SLfree (pat);
	     SLfree ((char *)list);
	     return -1;
	  }
     }
# endif   
   else while (1)
     {
	/* Do not include hidden files in the list.  Also, do not
	 * include "." and ".." entries.
	 */
#ifdef __WIN32__
	file = fd.cFileName;
#else
	file = fd.achName;
#endif
	if (
#ifdef __WIN32__
	    (hok || (0 == (fd.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN)))
#else
	    (hok || (0 == (fd.attrFile & FILE_HIDDEN)))
#endif
	    && ((*file != '.')
		|| ((0 != strcmp (file, "."))
		    && (0 != strcmp (file, "..")))))
	  {
	     if (num == max_num)
	       {
		  char **new_list;

		  max_num += 100;
		  new_list = (char **)SLrealloc ((char *)list, max_num * sizeof (char *));
		  if (new_list == NULL)
		    goto return_error;

		  list = new_list;
	       }

	     file = SLang_create_slstring (file);
	     if (file == NULL)
	       goto return_error;

	     list[num] = file;
	     num++;
	  }

#ifdef __WIN32__
	if (FALSE == FindNextFile(h, &fd))
	  {
	     if (ERROR_NO_MORE_FILES == GetLastError())
	       {
		  FindClose (h);
		  break;
	       }

	     _SLerrno_errno = errno;
	     FindClose (h);
	     goto return_error;
	  }
#else
        cFileNames = 1;
        rc = DosFindNext(h, &fd, sizeof(fd), &cFileNames);
        if (rc != 0)
	  {
	     if (rc == ERROR_NO_MORE_FILES)
	       {
		  DosFindClose (h);
		  break;
	       }

	     _SLerrno_errno = errno;
	     DosFindClose (h);
	     goto return_error;
	  }
#endif
     }

   SLfree (pat);
   *maxnum = max_num;
   *nump = num;
   *listp = list;
   return 0;

   return_error:
   free_dir_list (list, num);
   SLfree (pat);
   return -1;
}

#else				       /* NOT __WIN32__ */

static int build_dirlist (char *dir, char *opt, char ***listp, unsigned int *nump, unsigned int *maxnum)
{
   DIR *dp;
   struct dirent *ep;
   unsigned int num_files;
   unsigned int max_num_files;
   char **list;

   (void) opt;

   if (NULL == (dp = opendir (dir)))
     {
	_SLerrno_errno = errno;
	return -1;
     }

   num_files = max_num_files = 0;
   list = NULL;
   while (NULL != (ep = readdir (dp)))
     {
	unsigned int len;
	char *name;

	name = ep->d_name;
#  ifdef NEED_D_NAMLEN
	len = ep->d_namlen;
#  else
	len = strlen (name);
#  endif
	if ((*name == '.') && (len <= 2))
	  {
	     if (len == 1) continue;
	     if (name [1] == '.') continue;
	  }

	if (num_files == max_num_files)
	  {
	     char **new_list;

	     max_num_files += 100;
	     if (NULL == (new_list = (char **) SLrealloc ((char *)list, max_num_files * sizeof(char *))))
	       goto return_error;

	     list = new_list;
	  }

	if (NULL == (list[num_files] = SLang_create_nslstring (name, len)))
	  goto return_error;

	num_files++;
     }

   closedir (dp);
   *nump = num_files;
   *maxnum = max_num_files;
   *listp = list;
   return 0;

   return_error:
   if (dp != NULL)
     closedir (dp);
   free_dir_list (list, num_files);
   return -1;
}
# endif				       /* NOT __WIN32__ */

static void listdir_cmd (char *dir, char *opt)
{
   SLang_Array_Type *at;
   unsigned int num_files;
   unsigned int max_num_files;
   int inum_files;
   char **list;

   if (-1 == build_dirlist (dir, opt, &list, &num_files, &max_num_files))
     {
	SLang_push_null ();
	return;
     }
   /* If max_num_files == 0, then num_files == 0 and list == NULL.  
    * The realloc step below will malloc list for us.
    */
   if (num_files + 1 < max_num_files)
     {
	char **new_list;
	if (NULL == (new_list = (char **) SLrealloc ((char *)list, (num_files + 1)* sizeof(char*))))
	  {
	     free_dir_list (list, num_files);
	     SLang_push_null ();
	     return;
	  }
	list = new_list;
     }

   inum_files = (int) num_files;
   if (NULL == (at = SLang_create_array (SLANG_STRING_TYPE, 0, (VOID_STAR) list, &inum_files, 1)))
     {
	free_dir_list (list, num_files);
	SLang_push_null ();
	return;
     }

   /* Allow the array to free this list if push fails */
   if (-1 == SLang_push_array (at, 1))
     SLang_push_null ();
}

static void listdir_cmd_wrap (void)
{
   char *s, *sopt;

   sopt = NULL;
   switch (SLang_Num_Function_Args)
     {
      case 2:
	if (-1 == SLang_pop_slstring (&sopt))
	  return;
      case 1:
	if (-1 == SLang_pop_slstring (&s))
	  {
	     SLang_free_slstring (sopt);
	     return;
	  }
	break;
      default:
	SLang_verror (SL_INVALID_PARM, "usage: listdir (string, [opt-string]");
	return;
     }

   listdir_cmd (s, sopt);
   SLang_free_slstring (s);
   SLang_free_slstring (sopt);
}

#endif				       /* USE_LISTDIR_INTRINSIC */

#ifdef HAVE_UMASK
static int umask_cmd (int *u)
{
   return umask (*u);
}
#endif

static SLang_Intrin_Fun_Type PosixDir_Name_Table [] =
{
#ifdef HAVE_READLINK
   MAKE_INTRINSIC_S("readlink", readlink_cmd, SLANG_VOID_TYPE),
#endif
   MAKE_INTRINSIC_S("lstat_file", lstat_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("stat_file", stat_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_SI("stat_is", stat_is_cmd, SLANG_CHAR_TYPE),
#ifdef HAVE_MKFIFO
   MAKE_INTRINSIC_SI("mkfifo", mkfifo_cmd, SLANG_INT_TYPE),
#endif
#ifdef HAVE_CHOWN
   MAKE_INTRINSIC_SII("chown", chown_cmd, SLANG_INT_TYPE),
#endif
   MAKE_INTRINSIC_SI("chmod", chmod_cmd, SLANG_INT_TYPE),
#ifdef HAVE_UMASK
   MAKE_INTRINSIC_I("umask", umask_cmd, SLANG_INT_TYPE),
#endif
   MAKE_INTRINSIC_0("getcwd", slget_cwd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_SI("mkdir", mkdir_cmd, SLANG_INT_TYPE),
   MAKE_INTRINSIC_S("chdir", chdir_cmd, SLANG_INT_TYPE),
   MAKE_INTRINSIC_S("rmdir", rmdir_cmd, SLANG_INT_TYPE),
   MAKE_INTRINSIC_S("remove", remove_cmd, SLANG_INT_TYPE),
   MAKE_INTRINSIC_SS("rename", rename_cmd, SLANG_INT_TYPE),
#if USE_LISTDIR_INTRINSIC
   MAKE_INTRINSIC("listdir", listdir_cmd_wrap, SLANG_VOID_TYPE, 0),
#endif
   SLANG_END_INTRIN_FUN_TABLE
};

static SLang_IConstant_Type PosixDir_Consts [] =
{
#ifndef S_IRWXU
# define S_IRWXU 00700
#endif
   MAKE_ICONSTANT("S_IRWXU", S_IRWXU),
#ifndef S_IRUSR
# define S_IRUSR 00400
#endif
   MAKE_ICONSTANT("S_IRUSR", S_IRUSR),
#ifndef S_IWUSR
# define S_IWUSR 00200
#endif
   MAKE_ICONSTANT("S_IWUSR", S_IWUSR),
#ifndef S_IXUSR
# define S_IXUSR 00100
#endif
   MAKE_ICONSTANT("S_IXUSR", S_IXUSR),
#ifndef S_IRWXG
# define S_IRWXG 00070
#endif
   MAKE_ICONSTANT("S_IRWXG", S_IRWXG),
#ifndef S_IRGRP
# define S_IRGRP 00040
#endif
   MAKE_ICONSTANT("S_IRGRP", S_IRGRP),
#ifndef S_IWGRP
# define S_IWGRP 00020
#endif
   MAKE_ICONSTANT("S_IWGRP", S_IWGRP),
#ifndef S_IXGRP
# define S_IXGRP 00010
#endif
   MAKE_ICONSTANT("S_IXGRP", S_IXGRP),
#ifndef S_IRWXO
# define S_IRWXO 00007
#endif
   MAKE_ICONSTANT("S_IRWXO", S_IRWXO),
#ifndef S_IROTH
# define S_IROTH 00004
#endif
   MAKE_ICONSTANT("S_IROTH", S_IROTH),
#ifndef S_IWOTH
# define S_IWOTH 00002
#endif
   MAKE_ICONSTANT("S_IWOTH", S_IWOTH),
#ifndef S_IXOTH
# define S_IXOTH 00001
#endif
   MAKE_ICONSTANT("S_IXOTH", S_IXOTH),
#ifdef __WIN32__
   MAKE_ICONSTANT("FILE_ATTRIBUTE_ARCHIVE", FILE_ATTRIBUTE_ARCHIVE),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_COMPRESSED", FILE_ATTRIBUTE_COMPRESSED),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_NORMAL", FILE_ATTRIBUTE_NORMAL),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_DIRECTORY", FILE_ATTRIBUTE_DIRECTORY),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_HIDDEN", FILE_ATTRIBUTE_HIDDEN),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_READONLY", FILE_ATTRIBUTE_READONLY),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_SYSTEM", FILE_ATTRIBUTE_SYSTEM),
   MAKE_ICONSTANT("FILE_ATTRIBUTE_TEMPORARY", FILE_ATTRIBUTE_TEMPORARY),
#endif
   SLANG_END_ICONST_TABLE
};

static int Initialized;

int SLang_init_posix_dir (void)
{
   if (Initialized)
     return 0;

   if ((-1 == SLadd_intrin_fun_table(PosixDir_Name_Table, "__POSIX_DIR__"))
       || (-1 == SLadd_iconstant_table (PosixDir_Consts, NULL))
       || (-1 == _SLerrno_init ()))
     return -1;

   Initialized = 1;

   return 0;
}

