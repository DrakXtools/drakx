#include "vesamode.h"
#ident "$Id$"

/* Known standard VESA modes. */
struct vesa_mode_t known_vesa_modes[] = {
	/* VESA 1.0/1.1 ? */
	{0x100,	640, 400, 256,	"640x400x256"},
	{0x101,	640, 480, 256,	"640x480x256"},
	{0x102,	800, 600, 16,	"800x600x16"},
	{0x103,	800, 600, 256,	"800x600x256"},
	{0x104,	1024, 768, 16,	"1024x768x16"},
	{0x105,	1024, 768, 256,	"1024x768x256"},
	{0x106,	1280, 1024, 16,	"1280x1024x16"},
	{0x107,	1280, 1024, 256,"1280x1024x256"},
	{0x108,	80, 60, 16,	"80x60 (text)"},
	{0x109,	132, 25, 16,	"132x25 (text)"},
	{0x10a,	132, 43, 16,	"132x43 (text)"},
	{0x10b,	132, 50, 16,	"132x50 (text)"},
	{0x10c,	132, 60, 16,	"132x60 (text)"},
	/* VESA 1.2+ */
	{0x10d,	320, 200, 32768,	"320x200x32k"},
	{0x10e,	320, 200, 65536,	"320x200x64k"},
	{0x10f,	320, 200, 16777216,	"320x200x16m"},
	{0x110,	640, 480, 32768,	"640x480x32k"},
	{0x111,	640, 480, 65536,	"640x480x64k"},
	{0x112,	640, 480, 16777216,	"640x480x16m"},
	{0x113,	800, 600, 32768,	"800x600x32k"},
	{0x114,	800, 600, 65536,	"800x600x64k"},
	{0x115,	800, 600, 16777216,	"800x600x16m"},
	{0x116,	1024, 768, 32768,	"1024x768x32k"},
	{0x117,	1024, 768, 65536,	"1024x768x64k"},
	{0x118,	1024, 768, 16777216,	"1024x768x16m"},
	{0x119,	1280, 1024, 32768,	"1280x1024x32k"},
	{0x11a,	1280, 1024, 65536,	"1280x1024x64k"},
	{0x11b,	1280, 1024, 16777216,	"1280x1024x16m"},
	/* VESA 2.0+ */
	{0x120,	1600, 1200, 256,	"1600x1200x256"},
	{0x121,	1600, 1200, 32768,	"1600x1200x32k"},
	{0x122,	1600, 1200, 65536,	"1600x1200x64k"},
	{    0,    0,    0, 0,		""},
};

struct vesa_timing_t known_vesa_timings[] = {
	/* Source: VESA Monitor Timing Specifications 1.0 rev 0.8 */
	{ 640,  350, 85,  31.500, { 640, 32,  64,  96,  350,32, 3, 60},
	  hsync_pos, vsync_neg, 37.861,  85.080},

	{ 640,  400, 85,  31.500, { 640, 32,  64,  96,  400, 1, 3, 41},
	  hsync_neg, vsync_pos, 37.861,  85.080},

	{ 720,  400, 85,  35.500, { 720, 36, 72,  108,  400, 1, 3, 42},
	  hsync_neg, vsync_pos, 37.861,  85.080},

	{ 640,  480, 60,  25.175, { 640,  8,  96,  40,  480, 2, 2, 25},
	 hsync_neg, vsync_neg,  31.469,  59.940},
	{ 640,  480, 72,  31.500, { 640, 16,  40, 120,  480, 1, 3, 20},
	 hsync_neg, vsync_neg,  37.861,  72.809},
	{ 640,  480, 75,  31.500, { 640, 16,  64, 120,  480, 1, 3, 16},
	 hsync_neg, vsync_neg,  37.500,  75.000},
	{ 640,  480, 85,  36.000, { 640, 56,  56,  80,  480, 1, 3, 25},
	 hsync_neg, vsync_neg,  43.269,  85.008},

	{ 800,  600, 56,  36.000, { 800, 24,  72, 128,  600, 1, 2, 22},
	 hsync_pos, vsync_pos,  35.156,  56.250},
	{ 800,  600, 60,  40.000, { 800, 40, 128,  88,  600, 1, 4, 23},
	 hsync_pos, vsync_pos,  37.879,  60.317},
	{ 800,  600, 72,  50.000, { 800, 56, 120,  64,  600,37, 6, 23},
	 hsync_pos, vsync_pos,  48.077,  72.188},
	{ 800,  600, 75,  49.500, { 800, 16,  80, 160,  600, 1, 3, 21},
	 hsync_pos, vsync_pos,  46.875,  75.000},
	{ 800,  600, 85,  56.250, { 800, 32,  64, 152,  600, 1, 3, 27},
	 hsync_pos, vsync_pos,  53.674,  85.061},

	{1024,  768, 43,  44.900, {1024,  8, 176,  56,  768, 0, 4, 20},
	 hsync_pos, vsync_pos,  35.522,  86.957},
	{1024,  768, 60,  65.000, {1024, 24, 136, 160,  768, 3, 6, 29},
	 hsync_neg, vsync_neg,  48.363,  60.004},
	{1024,  768, 70,  75.000, {1024, 24, 136, 144,  768, 3, 6, 29},
	 hsync_neg, vsync_neg,  56.476,  70.069},
	{1024,  768, 75,  78.750, {1024, 16,  96, 176,  768, 1, 3, 28},
	 hsync_pos, vsync_pos,  60.023,  75.029},
	{1024,  768, 85,  94.500, {1024, 48,  96, 208,  768, 1, 3, 36},
	 hsync_pos, vsync_pos,  68.677,  84.997},

	{1152,  864, 70,  94.200, {1152, 32,  96, 192,  864, 1, 3, 46},
	 hsync_pos, vsync_pos,   0.000,   0.000},
	{1152,  864, 75, 108.000, {1152, 64, 128, 256,  864, 1, 3, 32},
	 hsync_pos, vsync_pos,  67.500,  75.000},
	{1152,  864, 85, 121.500, {1152, 64, 128, 224,  864, 1, 3, 43},
	 hsync_pos, vsync_pos,   0.000,   0.000},

	{1280,  960, 60, 108.000, {1280, 96, 112, 312,  960, 1, 3, 36},
	 hsync_pos, vsync_pos,  60.000,  60.000},
	{1280,  960, 85, 148.500, {1280, 64, 160, 224,  960, 1, 3, 47},
	 hsync_pos, vsync_pos,  85.398,  85.002},

	{1280, 1024, 60, 108.000, {1280, 48, 112, 248, 1024, 1, 3, 38},
	 hsync_pos, vsync_pos,  63.981,  60.020},
	{1280, 1024, 75, 135.000, {1280, 16, 144, 248, 1024, 1, 3, 38},
	 hsync_pos, vsync_pos,  79.976,  75.025},
	{1280, 1024, 85, 157.500, {1280, 64, 160, 224, 1024, 1, 3, 44},
	 hsync_pos, vsync_pos,  91.146,  85.024},

	{1600, 1200, 60, 162.000, {1600, 64, 192, 304, 1200, 1, 3, 46},
	 hsync_pos, vsync_pos,  75.000,  60.000},
	{1600, 1200, 65, 175.500, {1600, 64, 192, 304, 1200, 1, 3, 46},
	 hsync_pos, vsync_pos,  81.250,  65.000},
	{1600, 1200, 70, 189.000, {1600, 64, 192, 304, 1200, 1, 3, 46},
	 hsync_pos, vsync_pos,  87.500,  70.000},
	{1600, 1200, 75, 202.500, {1600, 64, 192, 304, 1200, 1, 3, 46},
	 hsync_pos, vsync_pos,  93.750,  75.000},
	{1600, 1200, 85, 229.500, {1600, 64, 192, 304, 1200, 1, 3, 46},
	 hsync_pos, vsync_pos, 106.250,  85.000},

	{1792, 1344, 60, 204.750, {1792,128, 200, 328, 1344, 1, 3, 46},
	 hsync_neg, vsync_pos,  83.640,  60.000},
	{1792, 1344, 75, 261.000, {1792, 96, 216, 352, 1344, 1, 3, 69},
	 hsync_neg, vsync_pos, 106.270,  74.997},

	{1856, 1392, 60, 218.250, {1856, 96, 224, 352, 1392, 1, 3, 43},
	 hsync_neg, vsync_pos,  86.333,  59.995},
	{1856, 1392, 75, 288.000, {1856,128, 224, 352, 1392, 1, 3,104},
	 hsync_neg, vsync_pos, 112.500,  75.000},

	{1920, 1440, 60, 234.000, {1920,128, 208, 344, 1440, 1, 3, 56},
	 hsync_neg, vsync_pos,  90.000,  60.000},
	{1920, 1440, 75, 297.000, {1920,144, 224, 352, 1440, 1, 3, 56},
	 hsync_neg, vsync_pos, 112.500,  75.000},

	{   0,    0,  0,   0.000, {   0,  0,   0,   0,    0, 0, 0,  0},
	 000000000, 000000000,   0.000,   0.000},
};
