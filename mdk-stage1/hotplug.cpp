/*
 * Firmware loader
 * Base on hotplug2 code (GPL v2) (http://code.google.com/p/hotplug2/)
 * Copyright stepan@davidovic.cz, iSteve <isteve@bofh.cz> Tomas Janousek <tomi@nomi.cz>
 */

#include <sys/types.h>
#include <sys/param.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

/**
 * Function supplementing 'echo > file'
 *
 * @1 File to be written to
 * @2 Data to be written
 * @3 Data size
 *
 * Returns: 0 on success, -1 on failure.
 */
static int echo_to_file(const char *filename, const char *data, size_t size) {
        FILE *fp;
        size_t written;

        fp = fopen(filename, "w");
        if (fp == NULL)
                return -1;
        written = fwrite(data, size, 1, fp);
        fclose(fp);

        return (written == size) ? 0 : -1;
}


int hotplug_main(int argc, char **argv) {
        char buffer[1024];
        char *devpath;
        char *firmware;
        char firmware_path[PATH_MAX];
        char sysfs_path_loading[PATH_MAX];
        char sysfs_path_data[PATH_MAX];
        int rv;
        FILE *infp, *outfp;
        size_t inlen, outlen;

        devpath = getenv("DEVPATH");
        if (devpath == NULL)
                return -1;

        firmware = getenv("FIRMWARE");
        if (firmware == NULL)
                return -1;

        if (snprintf(sysfs_path_loading, PATH_MAX, "/sysfs%s/loading", devpath) >= PATH_MAX)
                return -1;
        if (snprintf(sysfs_path_data, PATH_MAX, "/sysfs%s/data", devpath) >= PATH_MAX)
                return -1;
        if (snprintf(firmware_path, PATH_MAX, "%s/%s", argv[0], firmware) >= PATH_MAX)
                return -1;

        echo_to_file(sysfs_path_loading, "1\n", 2);

        infp = fopen(firmware_path, "r");
        if (infp == NULL) {
                echo_to_file(sysfs_path_loading, "0\n", 2);
                return -1;
        }
        outfp = fopen(sysfs_path_data, "w");
        if (outfp == NULL) {
                fclose(infp);
                echo_to_file(sysfs_path_loading, "0\n", 2);
                return -1;
        }

        rv = 0;
        while ((inlen = fread(buffer, 1, 1024, infp)) > 0) {
                outlen = fwrite(buffer, 1, inlen, outfp);
                if (outlen != inlen) {
                        rv = -1;
                        break;
                }
        }

        fclose(infp);

        echo_to_file(sysfs_path_loading, "0\n", 2);

	return rv;
}
