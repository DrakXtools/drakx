#ifndef _MATH_H
#define _MATH_H

#include <sys/cdefs.h>

#define M_E		2.7182818284590452354	/* e */
#define M_LOG2E		1.4426950408889634074	/* log_2 e */
#define M_LOG10E	0.43429448190325182765	/* log_10 e */
#define M_LN2		0.69314718055994530942	/* log_e 2 */
#define M_LN10		2.30258509299404568402	/* log_e 10 */
#define M_PI		3.14159265358979323846	/* pi */
#define M_PI_2		1.57079632679489661923	/* pi/2 */
#define M_PI_4		0.78539816339744830962	/* pi/4 */
#define M_1_PI		0.31830988618379067154	/* 1/pi */
#define M_2_PI		0.63661977236758134308	/* 2/pi */
#define M_2_SQRTPI	1.12837916709551257390	/* 2/sqrt(pi) */
#define M_SQRT2		1.41421356237309504880	/* sqrt(2) */
#define M_SQRT1_2	0.70710678118654752440	/* 1/sqrt(2) */

#define M_El		2.7182818284590452353602874713526625L  /* e */
#define M_LOG2El	1.4426950408889634073599246810018922L  /* log_2 e */
#define M_LOG10El	0.4342944819032518276511289189166051L  /* log_10 e */
#define M_LN2l		0.6931471805599453094172321214581766L  /* log_e 2 */
#define M_LN10l		2.3025850929940456840179914546843642L  /* log_e 10 */
#define M_PIl		3.1415926535897932384626433832795029L  /* pi */
#define M_PI_2l		1.5707963267948966192313216916397514L  /* pi/2 */
#define M_PI_4l		0.7853981633974483096156608458198757L  /* pi/4 */
#define M_1_PIl		0.3183098861837906715377675267450287L  /* 1/pi */
#define M_2_PIl		0.6366197723675813430755350534900574L  /* 2/pi */
#define M_2_SQRTPIl	1.1283791670955125738961589031215452L  /* 2/sqrt(pi) */
#define M_SQRT2l	1.4142135623730950488016887242096981L  /* sqrt(2) */
#define M_SQRT1_2l	0.7071067811865475244008443621048490L  /* 1/sqrt(2) */

double sin(double d) __THROW __attribute__((__const__));
double cos(double d) __THROW __attribute__((__const__));
double tan(double d) __THROW __attribute__((__const__));

double sinh(double d) __THROW __attribute__((__const__));
double cosh(double d) __THROW __attribute__((__const__));
double tanh(double d) __THROW __attribute__((__const__));

double asin(double d) __THROW __attribute__((__const__));
double acos(double d) __THROW __attribute__((__const__));
double atan(double d) __THROW __attribute__((__const__));

double asinh(double d) __THROW __attribute__((__const__));
double acosh(double d) __THROW __attribute__((__const__));
double atanh(double d) __THROW __attribute__((__const__));

double exp(double d) __THROW __attribute__((__const__));
double log(double d) __THROW __attribute__((__const__));
double log10(double d) __THROW __attribute__((__const__));

double pow(double x, double y) __THROW __attribute__((__const__));

#endif
