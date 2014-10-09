//
// "$Id: fl_font.cxx 9325 2012-04-05 05:12:30Z fabien $"
//
// Font selection code for the Fast Light Tool Kit (FLTK).
//
// Copyright 1998-2010 by Bill Spitzak and others.
//
// This library is free software. Distribution and use rights are outlined in
// the file "COPYING" which should have been included with this file.  If this
// file is missing or damaged, see the license at:
//
//     http://www.fltk.org/COPYING.php
//
// Please report all bugs and problems on the following page:
//
//     http://www.fltk.org/str.php
//

#ifdef WIN32
# ifndef WIN32_LEAN_AND_MEAN
#  define WIN32_LEAN_AND_MEAN
# endif
/* We require Windows 2000 features such as GetGlyphIndices */
# if !defined(WINVER) || (WINVER < 0x0500)
#  ifdef WINVER
#   undef WINVER
#  endif
#  define WINVER 0x0500
# endif
# if !defined(_WIN32_WINNT) || (_WIN32_WINNT < 0x0500)
#  ifdef _WIN32_WINNT
#   undef _WIN32_WINNT
#  endif
#  define _WIN32_WINNT 0x0500
# endif
#endif

// Select fonts from the FLTK font table.
#include "flstring.h"
#include "Fl.H"
#include "fl_draw.H"
#include "x.H"
#include "Fl_Font.H"

#include <stdio.h>
#include <stdlib.h>

#if __FLTK_WIN32__
#  include "os/win32/fl_font.cxx"
#elif __FLTK_MACOSX__
#  include "os/osx/fl_font.cxx"
#elif __FLTK_IPHONEOS__
#  include "os/ios/fl_font.cxx"
#elif __FLTK_LINUX__
#if USE_XFT
#  include "os/linux/xft_fl_font.cxx"
#else
#  include "os/linux/x_fl_font.cxx"
#endif
#elif __FLTK_WINCE__
#  include "os/wince/fl_font.cxx"
#else
#error unsupported platform
#endif

double fl_width(const char* c)
{
	if (c) return fl_width(c, (int) strlen(c));
	else return 0.0f;
}

void fl_draw(const char* str, int x, int y)
{
	fl_draw(str, (int) strlen(str), x, y);
}

void fl_draw(int angle, const char* str, int x, int y)
{
	fl_draw(angle, str, (int) strlen(str), x, y);//must be fixed!
}

void fl_text_extents(const char *c, int &dx, int &dy, int &w, int &h)
{
	if (c)  fl_text_extents(c, (int) strlen(c), dx, dy, w, h);
	else {
		w = 0;
		h = 0;
		dx = 0;
		dy = 0;
	}
} // fl_text_extents


void fl_draw(const char* str, int l, float x, float y)
{
#ifdef __APPLE__
	fl_graphics_driver->draw(str, l, x, y);
#else
	fl_draw(str, l, (int)x, (int)y);
#endif
}
//
// End of "$Id: fl_font.cxx 9325 2012-04-05 05:12:30Z fabien $".
//
