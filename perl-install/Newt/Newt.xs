#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <newt.h>

static void suspend() {
  newtSuspend();
  raise(SIGTSTP);
  newtResume();
}

static void componentCallback(newtComponent co, void *data) {
  dSP;
  PUSHMARK(SP);
  perl_call_sv((SV *) data, G_DISCARD);
}


typedef newtComponent Newt__Component;
typedef newtGrid Newt__Grid;


MODULE = Newt		PACKAGE = Newt 	PREFIX = newt

void
DESTROY()
	CODE:
	{
		newtFinished();
	}

int
newtInit()

int
newtFinished()

void
newtCls()

void
newtSuspend()

void
newtResume()

int
newtCenteredWindow(width,height,title)
	int width;
	int height;
	const char * title;

void
newtPopWindow()

void
newtRefresh()

void
newtPushHelpLine(text)
	const char * text;

void
newtDrawRootText(row,col,text)
	int row;
	int col;
	const char * text;

void
newtGetScreenSize()
  PPCODE:
{
  int cols, rows;
  newtGetScreenSize(&cols, &rows);
  PUSHs(sv_2mortal(newSViv(cols)));
  PUSHs(sv_2mortal(newSViv(rows)));
}

void
newtSetSuspendCallback()
	CODE:
	{
	  newtSetSuspendCallback(suspend, NULL);
	}


void
newtWinMessage(title,buttonText,text)
	char * title;
	char * buttonText;
	char * text;

int
newtWinChoice(title,button1,button2,text)
	char * title;
	char * button1;
	char * button2;
	char * text;

int
newtWinTernary(title,button1,button2,button3,message)
	char * title;
	char * button1;
	char * button2;
	char * button3;
	char * message;

MODULE = Newt		PACKAGE = Newt::Component 	PREFIX = newt

void
addCallback(co, callback)
  Newt::Component co;
  SV *callback;
  CODE:
  newtComponentAddCallback(co, componentCallback, callback);

Newt::Component
newtCompactButton(text)
	const char * text;
	CODE: 
	RETVAL = newtCompactButton(-1, -1, text);
	OUTPUT:
	RETVAL

Newt::Component
newtButton(text)
	const char * text;
	CODE: 
	RETVAL = newtButton(-1, -1, text);
	OUTPUT:
	RETVAL

Newt::Component
newtCheckbox(text,defValue,seq)
	const char * text;
	char *defValue;
	const char * seq;
	CODE: 
	RETVAL = newtCheckbox(-1, -1, text, defValue[0], seq, NULL);
	OUTPUT:
	RETVAL

int
newtCheckboxGetValue(co)
	Newt::Component co;

void
newtCheckboxSetValue(co, value)
	Newt::Component co;
	char *value;
  CODE: 
  newtCheckboxSetValue(co, value[0]);

Newt::Component
newtLabel(text)
	const char * text;
CODE:
        RETVAL = newtLabel(-1, -1, text);
OUTPUT:
	RETVAL

void
newtLabelSetText(co,text)
	Newt::Component co;
	const char * text;

Newt::Component
newtVerticalScrollbar(height,normalColorset,thumbColorset)
	int height;
	int normalColorset;
	int thumbColorset;
CODE:
        RETVAL = newtVerticalScrollbar(-1, -1, height,normalColorset,thumbColorset);
OUTPUT:
	RETVAL

void
newtScrollbarSet(co,where,total)
	Newt::Component co;
	int where;
	int total;

Newt::Component
newtListbox(height,flags)
	int height;
	int flags;
CODE:
        RETVAL = newtListbox(-1, -1, height, flags);
OUTPUT:
	RETVAL

SV *
newtListboxGetCurrent(co)
	Newt::Component co;
CODE:
        RETVAL = SvREFCNT_inc(newtListboxGetCurrent(co));
OUTPUT:
	RETVAL


void
newtListboxSetCurrent(co,indice)
	Newt::Component co;
	int indice;

void
newtListboxSetWidth(co,width)
	Newt::Component co;
	int width;

int
newtListboxAddEntry(co,text,data)
	Newt::Component co;
	const char * text;
	SV * data;
CODE:
	RETVAL = newtListboxAddEntry(co, text, data);
OUTPUT:
	RETVAL

Newt::Component
newtTextbox(left,top,width,height,want_scroll)
	int left;
	int top;
	int width;
	int height;
	int want_scroll;
	CODE: 
	RETVAL = newtTextbox(left,top,width,height, (want_scroll ? NEWT_FLAG_SCROLL : 0) | NEWT_FLAG_WRAP);
	OUTPUT:
	RETVAL

void
newtTextboxSetText(co,text)
	Newt::Component co;
	const char * text;

void
newtTextboxSetHeight(co,height)
	Newt::Component co;
	int height;

int
newtTextboxGetNumLines(co)
	Newt::Component co;

char *
newtReflowText(text,width,flexDown,flexUp,actualWidth,actualHeight)
	char * text;
	int width;
	int flexDown;
	int flexUp;
	int * actualWidth;
	int * actualHeight;

Newt::Component
newtForm(vertBar,help,flags)
	Newt::Component vertBar;
	const char * help;
	int flags;

void
newtFormSetSize(co)
	Newt::Component co;

Newt::Component
newtFormGetCurrent(co)
	Newt::Component co;

void
newtFormSetBackground(co,color)
	Newt::Component co;
	int color;

void
newtFormSetCurrent(co,subco)
	Newt::Component co;
	Newt::Component subco;

void
newtFormAddComponent(form,co)
	Newt::Component form;
	Newt::Component co;

void
newtFormAddGrid(form,grid,recurse)
	Newt::Component form;
	Newt::Grid grid;
        int recurse;
  CODE:
  newtGridAddComponentsToForm(grid,form,recurse);

void
newtFormSetHeight(co,height)
	Newt::Component co;
	int height;

void
newtFormSetWidth(co,width)
	Newt::Component co;
	int width;

Newt::Component
newtRunForm(form)
	Newt::Component form;

void
newtDrawForm(form)
	Newt::Component form;

Newt::Component
newtEntry(initialValue,width,flag)
	const char * initialValue;
	int width;
        int flag;
	CODE:
	{
		char *result;
		RETVAL = newtEntry(-1, -1, initialValue,width,&result,flag);
	}
	OUTPUT:
	RETVAL

void
newtEntrySet(co,value,cursorAtEnd)
	Newt::Component co;
	const char * value;
	int cursorAtEnd;

char *
newtEntryGetValue(co)
	Newt::Component co;

void
newtFormDestroy(form)
	Newt::Component form;

MODULE = Newt		PACKAGE = Newt::Grid 	PREFIX = newt

Newt::Grid
newtCreateGrid(cols,rows)
	int cols;
	int rows;

Newt::Grid
HCloseStacked3(c1, c2, c3)
	Newt::Component c1;
	Newt::Component c2;
	Newt::Component c3;
     CODE:
	{
	  RETVAL = newtGridHCloseStacked(NEWT_GRID_COMPONENT, c1, NEWT_GRID_COMPONENT, c2, NEWT_GRID_COMPONENT, c3);
	}
OUTPUT:
RETVAL


Newt::Grid
newtGridBasicWindow(text,middle,buttons)
	Newt::Component text;
	Newt::Grid middle;
	Newt::Grid buttons;


Newt::Grid
newtGridSimpleWindow(text,middle,buttons)
	Newt::Component text;
	Newt::Component middle;
	Newt::Grid buttons;

void
newtGridSetField(grid,col,row,type,val,padLeft,padTop,padRight,padBottom,anchor,flags)
	Newt::Grid grid;
	int col;
	int row;
	enum newtGridElement type;
	void * val;
	int padLeft;
	int padTop;
	int padRight;
	int padBottom;
	int anchor;
	int flags;


void
newtGridFree(grid,recurse)
	Newt::Grid grid;
	int recurse;

void
newtGridPlace(grid,left,top)
	Newt::Grid grid;
        int left;
        int top;

void
newtGridGetSize(grid)
	Newt::Grid grid;
 PPCODE:
{
  int width;
  int height;
  newtGridGetSize(grid, &width, &height);
  PUSHs(sv_2mortal(newSViv(width)));
  PUSHs(sv_2mortal(newSViv(height)));
}

void
newtGridWrappedWindow(grid,title)
	Newt::Grid grid;
	char * title;
	
Newt::Grid
newtButtonBar(button1, ...)
	char * button1;
 PPCODE:
	{
	  static newtComponent p[11];
	  int i;
	  EXTEND(SP, items + 1);
#define a(i) (char *)SvPV(ST(i),PL_na)
          PUSHs(sv_setref_pv(sv_newmortal(), "Newt::Grid", 
	     newtButtonBar(items >  0 ? a( 0) : NULL, items >  0 ? &p[ 0] : NULL, 
			   items >  1 ? a( 1) : NULL, items >  1 ? &p[ 1] : NULL, 
			   items >  2 ? a( 2) : NULL, items >  2 ? &p[ 2] : NULL, 
			   items >  3 ? a( 3) : NULL, items >  3 ? &p[ 3] : NULL, 
			   items >  4 ? a( 4) : NULL, items >  4 ? &p[ 4] : NULL, 
			   items >  5 ? a( 5) : NULL, items >  5 ? &p[ 5] : NULL, 
			   items >  6 ? a( 6) : NULL, items >  6 ? &p[ 6] : NULL, 
			   items >  7 ? a( 7) : NULL, items >  7 ? &p[ 7] : NULL, 
			   items >  8 ? a( 8) : NULL, items >  8 ? &p[ 8] : NULL, 
			   items >  9 ? a( 9) : NULL, items >  9 ? &p[ 9] : NULL, 
			   items > 10 ? a(10) : NULL, items > 10 ? &p[10] : NULL,  
			   NULL)));
#undef a
        for (i = 0; i < items; i++) PUSHs(sv_setref_pv(sv_newmortal(), "Newt::Component", p[i]));
	}
