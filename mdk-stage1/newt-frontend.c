/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */


/*
 * Each different frontend must implement all functions defined in frontend.h
 */


#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <sys/time.h>
#include "newt/newt.h"

#include <probing.h>

#include "frontend.h"

void init_frontend(char * welcome_msg)
{
	int i;
	for (i=0; i<38; i++) printf("\n");
	newtInit();
	newtCls();

	if (welcome_msg[0]) {
		char *msg;
		int cols, rows;
		newtGetScreenSize(&cols, &rows);
		asprintf(&msg, " %-*s", cols - 1, welcome_msg);
		newtDrawRootText(0, 0, msg);
		free(msg);
		newtPushHelpLine(" <Alt-F1> for here, <Alt-F3> to see the logs, <Alt-F4> for kernel msg");
	}
	newtRefresh();
}


void finish_frontend(void)
{
	newtFinished();
}


void verror_message(char *msg, va_list ap)
{
	newtWinMessagev("Error", "Ok", msg, ap);
}

void vinfo_message(char *msg, va_list ap)
{
	newtWinMessagev("Notice", "Ok", msg, ap);
}


void vwait_message(char *msg, va_list ap)
{
	int width, height;
	char * title = "Please wait...";
	newtComponent c, f;
	newtGrid grid;
	char * buf = NULL;
	char * flowed;
	int size = 0;
	int i = 0;
	
	do {
		size += 1000;
		if (buf) free(buf);
		buf = malloc(size);
		i = vsnprintf(buf, size, msg, ap);
	} while (i >= size || i == -1);

	flowed = newtReflowText(buf, 60, 5, 5, &width, &height);
	
	c = newtTextbox(-1, -1, width, height, NEWT_TEXTBOX_WRAP);
	newtTextboxSetText(c, flowed);

	grid = newtCreateGrid(1, 1);
	newtGridSetField(grid, 0, 0, NEWT_GRID_COMPONENT, c, 0, 0, 0, 0, 0, 0);
	newtGridWrappedWindow(grid, title);

	free(flowed);
	free(buf);

	f = newtForm(NULL, NULL, 0);
	newtFormAddComponent(f, c);

	newtDrawForm(f);
	newtRefresh();
	newtFormDestroy(f);
}

void remove_wait_message(void)
{
	newtPopWindow();
}


static newtComponent form = NULL, scale = NULL;
static int size_progress;
static int actually_drawn;
static char * msg_progress;

void init_progression_raw(char *msg, int size)
{
	size_progress = size;
	if (size) {
		actually_drawn = 0;
		newtCenteredWindow(70, 5, "Please wait...");
		form = newtForm(NULL, NULL, 0);
		newtFormAddComponent(form, newtLabel(1, 1, msg));
		scale = newtScale(1, 3, 68, size);
		newtFormAddComponent(form, scale);
		newtDrawForm(form);
		newtRefresh();
	}
	else {
		wait_message(msg);
		msg_progress = msg;
	}
}

void update_progression_raw(int current_size)
{
	if (size_progress) {
		if (current_size <= size_progress)
			newtScaleSet(scale, current_size);
		newtRefresh();
	}
	else {
		struct timeval t;
		int time;
		static int last_time = -1;
		gettimeofday(&t, NULL);
		time = t.tv_sec*3 + t.tv_usec/300000;
		if (time != last_time) {
			char msg_prog_final[500];
			sprintf(msg_prog_final, "%s (%d bytes read) ", msg_progress, current_size);
			remove_wait_message();
			wait_message(msg_prog_final);
		}
		last_time = time;
	}
}

void end_progression_raw(void)
{
	if (size_progress) {
		newtPopWindow();
		newtFormDestroy(form);
	}
	else
		remove_wait_message();
}


enum return_type ask_from_list_index(char *msg, char ** elems, char ** elems_comments, int * answer)
{
	char * items[50000];
	int rc;

	if (elems_comments) {
	    int i;

	    i = 0;
	    while (elems && *elems) {
		    int j = (*elems_comments) ? strlen(*elems_comments) : 0;
		    items[i] = malloc(sizeof(char) * (strlen(*elems) + j + 4));
		    strcpy(items[i], *elems);
		    if (*elems_comments) {
			    strcat(items[i], " (");
			    strcat(items[i], *elems_comments);
			    strcat(items[i], ")");
		    }
		    elems_comments++;
		    i++;
		    elems++;
	    }
	    items[i] = NULL;
	}

	rc = newtWinMenu("Please choose...", msg, 52, 5, 5, 7, elems_comments ? items : elems, answer, "Ok", "Cancel", NULL);

	if (rc == 2)
		return RETURN_BACK;

	return RETURN_OK;
}

enum return_type ask_yes_no(char *msg)
{
	int rc;

	rc = newtWinTernary("Please answer...", "Yes", "No", "Back", msg);

	if (rc == 1)
		return RETURN_OK;
	else if (rc == 3)
		return RETURN_BACK;
	else return RETURN_ERROR;
}


static void (*callback_real_function)(char ** strings) = NULL;

static void default_callback(newtComponent co __attribute__ ((unused)), void * data)
{
	newtComponent * entries = data;
	char * strings[50], ** ptr;

	if (!callback_real_function)
		return;

	ptr = strings;
	while (entries && *entries) {
		*ptr = newtEntryGetValue(*entries);
		entries++;
		ptr++;
	}

	callback_real_function(strings);

	ptr = strings;
	entries = data;
	while (entries && *entries) {
		newtEntrySet(*entries, strdup(*ptr), 1);
		entries++;
		ptr++;
	}
}

/* only supports up to 50 buttons and entries -- shucks! */
static int mynewtWinEntries(char * title, char * text, int suggestedWidth, int flexDown, 
			    int flexUp, int dataWidth, void (*callback_func)(char ** strings),
			    struct newtWinEntry * items, char * button1, ...) {
	newtComponent buttons[50], result, form, textw;
	newtGrid grid, buttonBar, subgrid;
	int numItems;
	int rc, i;
	int numButtons;
	char * buttonName;
	newtComponent entries[50];

	va_list args;
	
	textw = newtTextboxReflowed(-1, -1, text, suggestedWidth, flexDown,
				    flexUp, 0);
	
	for (numItems = 0; items[numItems].text; numItems++); 
	
	buttonName = button1, numButtons = 0;
	va_start(args, button1);
	while (buttonName) {
		buttons[numButtons] = newtButton(-1, -1, buttonName);
		numButtons++;
		buttonName = va_arg(args, char *);
	}
	
	va_end(args);
	
	buttonBar = newtCreateGrid(numButtons, 1);
	for (i = 0; i < numButtons; i++) {
		newtGridSetField(buttonBar, i, 0, NEWT_GRID_COMPONENT, 
				 buttons[i],
				 i ? 1 : 0, 0, 0, 0, 0, 0);
	}

	if (callback_func) {
		callback_real_function = callback_func;
		entries[numItems] = NULL;
	}
	else
		callback_real_function = NULL;
	
	subgrid = newtCreateGrid(2, numItems);
	for (i = 0; i < numItems; i++) {
		newtComponent entr = newtEntry(-1, -1, items[i].value ? 
					       *items[i].value : NULL, dataWidth,
					       items[i].value, items[i].flags);

		newtGridSetField(subgrid, 0, i, NEWT_GRID_COMPONENT,
				 newtLabel(-1, -1, items[i].text),
				 0, 0, 0, 0, NEWT_ANCHOR_LEFT, 0);
		newtGridSetField(subgrid, 1, i, NEWT_GRID_COMPONENT,
				 entr,
				 1, 0, 0, 0, 0, 0);
		if (callback_func) {
			entries[i] = entr;
			newtComponentAddCallback(entr, default_callback, entries);
		}
	}
	
	
	grid = newtCreateGrid(1, 3);
	form = newtForm(NULL, 0, 0);
	newtGridSetField(grid, 0, 0, NEWT_GRID_COMPONENT, textw, 
			 0, 0, 0, 0, NEWT_ANCHOR_LEFT, 0);
	newtGridSetField(grid, 0, 1, NEWT_GRID_SUBGRID, subgrid, 
			 0, 1, 0, 0, 0, 0);
	newtGridSetField(grid, 0, 2, NEWT_GRID_SUBGRID, buttonBar, 
			 0, 1, 0, 0, 0, NEWT_GRID_FLAG_GROWX);
	newtGridAddComponentsToForm(grid, form, 1);
	newtGridWrappedWindow(grid, title);
	newtGridFree(grid, 1);
	
	result = newtRunForm(form);
	
	for (rc = 0; rc < numItems; rc++)
		*items[rc].value = strdup(*items[rc].value);
	
	for (rc = 0; result != buttons[rc] && rc < numButtons; rc++);
	if (rc == numButtons) 
		rc = 0; /* F12 */
	else 
		rc++;
	
	newtFormDestroy(form);
	newtPopWindow();
	
	return rc;
}


enum return_type ask_from_entries(char *msg, char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings))
{
	struct newtWinEntry entries[50];
	int j, i = 0;
	int rc;
	char ** already_answers = NULL;

	while (questions && *questions) {
		entries[i].text = *questions;
		entries[i].flags = NEWT_FLAG_SCROLL | (!strcmp(*questions, "Password") ? NEWT_FLAG_PASSWORD : 0);
		i++;
		questions++;
	}
	entries[i].text = NULL;
	entries[i].value = NULL;

	if (*answers == NULL)
		*answers = (char **) malloc(sizeof(char *) * i);
	else
		already_answers = *answers;

	for (j = 0 ; j < i ; j++) {
		entries[j].value = &((*answers)[j]);
		if (already_answers && *already_answers) {
			*(entries[j].value) = *already_answers;
			already_answers++;
		} else
			*(entries[j].value) = NULL;
	}

	rc = mynewtWinEntries("Please fill in entries...", msg, 52, 5, 5, entry_size, callback_func, entries, "Ok", "Cancel", NULL); 

	if (rc == 3)
		return RETURN_BACK;
	if (rc != 1)
		return RETURN_ERROR;
	
	return RETURN_OK;
}


void suspend_to_console(void) { newtSuspend(); }
void resume_from_suspend(void) { newtResume(); }
