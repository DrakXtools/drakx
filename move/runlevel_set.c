#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <utmp.h>

int main(int argc, char **argv)
{
	struct utmp utmp;

        if (argc <= 1) {
                fprintf(stderr, "need an argument\n");
                return 1;
        }

	memset(&utmp, 0, sizeof(utmp));
	utmp.ut_type = RUN_LVL;
        utmp.ut_pid = argv[1][0];

	setutent();
	pututline(&utmp);
	endutent();

        return 0;
}
