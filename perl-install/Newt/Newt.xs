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

void
newtWinMenu(title,text,suggestedWidth,flexDown,flexUp,maxListHeight,list,def,buttons, ...)
	char * title;
	char * text;
	int suggestedWidth;
	int flexDown;
	int flexUp;
	int maxListHeight;
	char **list;
	int def;
	char *buttons;
        PPCODE:
	{
	  int button;
#define nb 8
#define a(i) SvPV(ST(i + nb),PL_na)
	  button = newtWinMenu(title, text, suggestedWidth, flexDown, flexUp, maxListHeight, list, &def,
			       items > nb +  0 ? a( 0) : NULL,
			       items > nb +  1 ? a( 1) : NULL,
			       items > nb +  2 ? a( 2) : NULL,
			       items > nb +  3 ? a( 3) : NULL,
			       items > nb +  4 ? a( 4) : NULL,
			       items > nb +  5 ? a( 5) : NULL,
			       items > nb +  6 ? a( 6) : NULL,
			       items > nb +  7 ? a( 7) : NULL,
			       items > nb +  8 ? a( 8) : NULL,
			       items > nb +  9 ? a( 9) : NULL,
			       items > nb + 10 ? a(10) : NULL, 
			       NULL);
#undef a
	  EXTEND(SP, 2);
 	  PUSHs(sv_2mortal(newSViv(button)));
 	  PUSHs(sv_2mortal(newSViv(def)));
	}

MODULE = Newt		PACKAGE = Newt::Component 	PREFIX = newt

void
addCallback(co, callback)
  Newt::Component co;
  SV *callback;
  CODE:
  newtComponentAddCallback(co, componentCallback, callback);

Newt::Component
newtCompactButton(left,top,text)
	int left;
	int top;
	const char * text;

Newt::Component
newtButton(left,top,text)
	int left;
	int top;
	const char * text;

Newt::Component
newtCheckbox(left,top,text,defValue,seq)
	int left;
	int top;
	const char * text;
	char *defValue;
	const char * seq;
  CODE: 
  RETVAL = newtCheckbox(left, top, text, defValue[0], seq, NULL);
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
newtLabel(left,top,text)
	int left;
	int top;
	const char * text;

void
newtLabelSetText(co,text)
	Newt::Component co;
	const char * text;

Newt::Component
newtVerticalScrollbar(left,top,height,normalColorset,thumbColorset)
	int left;
	int top;
	int height;
	int normalColorset;
	int thumbColorset;

void
newtScrollbarSet(co,where,total)
	Newt::Component co;
	int where;
	int total;

Newt::Component
newtListbox(left,top,height,flags)
	int left;
	int top;
	int height;
	int flags;

char *
newtListboxGetCurrent(co)
	Newt::Component co;

void
newtListboxSetCurrent(co,indice)
	Newt::Component co;
	int indice;

void
newtListboxSetWidth(co,width)
	Newt::Component co;
	int width;

int
newtListboxAddEntry(co,text)
	Newt::Component co;
	const char * text;
CODE:
	RETVAL = newtListboxAddEntry(co, text, text);
OUTPUT:
	RETVAL

Newt::Component
newtTextboxReflowed(left,top,text,width,flexDown,flexUp,flags)
	int left;
	int top;
	char * text;
	int width;
	int flexDown;
	int flexUp;
	int flags;

Newt::Component
newtTextbox(left,top,width,height,flags)
	int left;
	int top;
	int width;
	int height;
	int flags;

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
newtEntry(left,top,initialValue,width,flag)
	int left;
	int top;
	const char * initialValue;
	int width;
        int flag;
	CODE:
	{
		char *result;
		RETVAL = newtEntry(left,top,initialValue,width,&result,flag);
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
HCloseStacked(first, ...)
	Newt::Component first;
     CODE:
	{
	  int i;
#define a(i) (newtComponent)SvIV((SV*)SvRV( ST(i) ))
          RETVAL =
	     newtGridHCloseStacked(
                           items >  0 ? 1 : 0, items >  0 ? a( 0) : NULL, 
			   items >  1 ? 1 : 0, items >  1 ? a( 1) : NULL, 
			   items >  2 ? 1 : 0, items >  2 ? a( 2) : NULL, 
			   items >  3 ? 1 : 0, items >  3 ? a( 3) : NULL, 
			   items >  4 ? 1 : 0, items >  4 ? a( 4) : NULL, 
			   items >  5 ? 1 : 0, items >  5 ? a( 5) : NULL, 
			   items >  6 ? 1 : 0, items >  6 ? a( 6) : NULL, 
			   items >  7 ? 1 : 0, items >  7 ? a( 7) : NULL, 
			   items >  8 ? 1 : 0, items >  8 ? a( 8) : NULL, 
			   items >  9 ? 1 : 0, items >  9 ? a( 9) : NULL, 
			   items > 10 ? 1 : 0, items > 10 ? a(10) : NULL,  
			   NULL);
#undef a
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
newtGridGetSize(grid,width,height)
	Newt::Grid grid;
	int * width;
	int * height;

void
newtGridWrappedWindow(grid,title)
	Newt::Grid grid;
	char * title;
	
void
newtGridAddComponentsToForm(grid,form,recurse)
	Newt::Grid grid;
	Newt::Component form;
	int recurse;

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
