/* Copyright (c) 1998, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */
#include "slinclud.h"

#include "slang.h"
#include "_slang.h"

static SLKeyMap_List_Type *Keymap_List;

int SLkp_init (void)
{
   char esc_seq[10];
   int i;

   if (NULL == (Keymap_List = SLang_create_keymap ("_SLKeypad", NULL)))
     return -1;

   esc_seq[1] = 0;
   for (i = 1; i < 256; i++)
     {
	esc_seq[0] = (char) i;
	SLkm_define_keysym (esc_seq, i, Keymap_List);
     }

   /* Now add most common ones. */
#ifndef IBMPC_SYSTEM
   SLkm_define_keysym ("^@", 0, Keymap_List);

   SLkm_define_keysym ("\033[A", SL_KEY_UP, Keymap_List);
   SLkm_define_keysym ("\033OA", SL_KEY_UP, Keymap_List);
   SLkm_define_keysym ("\033[B", SL_KEY_DOWN, Keymap_List);
   SLkm_define_keysym ("\033OB", SL_KEY_DOWN, Keymap_List);
   SLkm_define_keysym ("\033[C", SL_KEY_RIGHT, Keymap_List);
   SLkm_define_keysym ("\033OC", SL_KEY_RIGHT, Keymap_List);
   SLkm_define_keysym ("\033[D", SL_KEY_LEFT, Keymap_List);
   SLkm_define_keysym ("\033OD", SL_KEY_LEFT, Keymap_List);
   SLkm_define_keysym ("\033[2~", SL_KEY_IC, Keymap_List);
   SLkm_define_keysym ("\033[7~", SL_KEY_HOME, Keymap_List);
   SLkm_define_keysym ("\033[5~", SL_KEY_PPAGE, Keymap_List);
   SLkm_define_keysym ("\033[6~", SL_KEY_NPAGE, Keymap_List);
   SLkm_define_keysym ("\033[8~", SL_KEY_END, Keymap_List);
   SLkm_define_keysym ("\033[3~", SL_KEY_DELETE, Keymap_List);
#else
   /* Note: This will not work if SLgetkey_map_to_ansi (1) has
    * been called.
    */
   SLkm_define_keysym ("^@\x48", SL_KEY_UP, Keymap_List );
   SLkm_define_keysym ("^@\x50", SL_KEY_DOWN, Keymap_List );
   SLkm_define_keysym ("^@\x4d", SL_KEY_RIGHT, Keymap_List );
   SLkm_define_keysym ("^@\x4b", SL_KEY_LEFT, Keymap_List );
   SLkm_define_keysym ("^@\x47", SL_KEY_HOME, Keymap_List );
   SLkm_define_keysym ("^@\x49", SL_KEY_PPAGE, Keymap_List );
   SLkm_define_keysym ("^@\x51", SL_KEY_NPAGE, Keymap_List );
   SLkm_define_keysym ("^@\x4f", SL_KEY_END, Keymap_List );
   SLkm_define_keysym ("^@\x52", SL_KEY_IC, Keymap_List );
   SLkm_define_keysym ("^@\x53", SL_KEY_DELETE, Keymap_List );
   
   SLkm_define_keysym ("\xE0\x48", SL_KEY_UP, Keymap_List );
   SLkm_define_keysym ("\xE0\x50", SL_KEY_DOWN, Keymap_List );
   SLkm_define_keysym ("\xE0\x4d", SL_KEY_RIGHT, Keymap_List );
   SLkm_define_keysym ("\xE0\x4b", SL_KEY_LEFT, Keymap_List );
   SLkm_define_keysym ("\xE0\x47", SL_KEY_HOME, Keymap_List );
   SLkm_define_keysym ("\xE0\x49", SL_KEY_PPAGE, Keymap_List );
   SLkm_define_keysym ("\xE0\x51", SL_KEY_NPAGE, Keymap_List );
   SLkm_define_keysym ("\xE0\x4f", SL_KEY_END, Keymap_List );
   SLkm_define_keysym ("\xE0\x52", SL_KEY_IC, Keymap_List );
   SLkm_define_keysym ("\xE0\x53", SL_KEY_DELETE, Keymap_List );

    strcpy (esc_seq, "^@ ");	       /* guarantees esc_seq[3] = 0. */

    for (i = 0x3b; i < 0x45; i++)
      {
	 esc_seq [2] = i;
	 SLkm_define_keysym (esc_seq, SL_KEY_F(i - 0x3a), Keymap_List);
      }
   esc_seq[2] = 0x57; SLkm_define_keysym (esc_seq, SL_KEY_F(11), Keymap_List);
   esc_seq[2] = 0x58; SLkm_define_keysym (esc_seq, SL_KEY_F(12), Keymap_List);
#endif

#ifdef REAL_UNIX_SYSTEM
   strcpy (esc_seq, "^(kX)");
   for (i = 0; i <= 9; i++)
     {
	esc_seq[3] = '0' + i;
	SLkm_define_keysym (esc_seq, SL_KEY_F(i), Keymap_List);
     }
   SLkm_define_keysym ("^(k;)", SL_KEY_F(10), Keymap_List);

   SLkm_define_keysym ("^(ku)", SL_KEY_UP, Keymap_List);
   SLkm_define_keysym ("^(kd)", SL_KEY_DOWN, Keymap_List);
   SLkm_define_keysym ("^(kl)", SL_KEY_LEFT, Keymap_List);
   SLkm_define_keysym ("^(kr)", SL_KEY_RIGHT, Keymap_List);
   SLkm_define_keysym ("^(kP)", SL_KEY_PPAGE, Keymap_List);
   SLkm_define_keysym ("^(kN)", SL_KEY_NPAGE, Keymap_List);
   SLkm_define_keysym ("^(kh)", SL_KEY_HOME, Keymap_List);
   SLkm_define_keysym ("^(@7)", SL_KEY_END, Keymap_List);
   SLkm_define_keysym ("^(K1)", SL_KEY_A1, Keymap_List);
   SLkm_define_keysym ("^(K3)", SL_KEY_A3, Keymap_List);
   SLkm_define_keysym ("^(K2)", SL_KEY_B2, Keymap_List);
   SLkm_define_keysym ("^(K4)", SL_KEY_C1, Keymap_List);
   SLkm_define_keysym ("^(K5)", SL_KEY_C3, Keymap_List);
   SLkm_define_keysym ("^(%0)", SL_KEY_REDO, Keymap_List);
   SLkm_define_keysym ("^(&8)", SL_KEY_UNDO, Keymap_List);
   SLkm_define_keysym ("^(kb)", SL_KEY_BACKSPACE, Keymap_List);
   SLkm_define_keysym ("^(@8)", SL_KEY_ENTER, Keymap_List);
   SLkm_define_keysym ("^(kD)", SL_KEY_DELETE, Keymap_List);
#endif

   if (SLang_Error)
     return -1;
   return 0;
}

int SLkp_getkey (void)
{
   SLang_Key_Type *key;

   key = SLang_do_key (Keymap_List, (int (*)(void)) SLang_getkey);
   if ((key == NULL) || (key->type != SLKEY_F_KEYSYM))
     {
	SLang_flush_input ();
	return SL_KEY_ERR;
     }

   return key->f.keysym;
}

int SLkp_define_keysym (char *keystr, unsigned int keysym)
{
   if (SLkm_define_keysym (keystr, keysym, Keymap_List) < 0)
     return -1;

   return 0;
}

#if 0
int main (int argc, char **argv)
{
   int ch;

   SLtt_get_terminfo ();

   if (-1 == SLkp_init ())
     return 1;

   SLang_init_tty (-1, 0, 0);

   while ('q' != (ch = SLkp_getkey ()))
     {
	fprintf (stdout, "Keycode = %d\r\n", ch);
	fflush (stdout);
     }

   SLang_reset_tty ();

   return 0;
}
#endif

