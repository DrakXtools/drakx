/*
 * Copyright 2005 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include "ka.h"
#include <sys/mount.h>
#include "mount.h"
#include <sys/wait.h>
#include <dirent.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#include "config-stage1.h"
#include "frontend.h"
#include "log.h"
#include "tools.h"

struct in_addr next_server = { 0 };

#if 0
static void save_stuff_for_rescue(void) 
{
  copy_file("/etc/resolv.conf", STAGE2_LOCATION "/etc/resolv.conf", NULL);
}
#endif

static void my_pause(void) {
	unsigned char t;
	fflush(stdout);
	read(0, &t, 1);
}

static enum return_type ka_wait_for_stage2(int count)
{
	char * ramdisk = "/dev/ram3"; /* warning, verify that this file exists in the initrd*/
	char * ka_launch[] = { "/ka/ka-d-client", "-w","-s","getstage2","-e","(cd /tmp/stage2; tar --extract  --read-full-records --same-permissions --numeric-owner --sparse --file - )", NULL }; /* The command line for ka_launch */
	char * mkfs_launch[] = { "/sbin/mke2fs", ramdisk, NULL}; /* The mkfs command for formating the ramdisk */

	log_message("KA: Preparing to receive stage 2....");
	int pida, wait_status;

	if (!(pida = fork())) { /* Forking current process for running mkfs */
		    close(1);
		    close(2);
		execv(mkfs_launch[0], mkfs_launch); /* Formating the ramdisk */
		printf("KA: Can't execute %s\n<press Enter>\n", mkfs_launch[0]);
		my_pause();
		return KAERR_CANTFORK;
	}
	while (wait4(-1, &wait_status, 0, NULL) != pida) {}; /* Waiting the end of mkfs */

	if (my_mount(ramdisk, STAGE2_LOCATION, "ext2", 1)) {/* Trying to mount the ramdisk */
		return RETURN_ERROR;
	}

	log_message("KA: Waiting for stage 2....");
	wait_message("Waiting for rescue from KA server (Try %d/%d)", count, KA_MAX_RETRY);
	pid_t pid;          /* Process ID of the child process */
	pid_t wpid;         /* Process ID from wait() */
	int status;         /* Exit status from wait() */

	pid = fork();
	if ( pid == -1 ) {
		fprintf(stderr, "%s: Failed to fork()\n", strerror(errno));
		exit(13);
	} else if ( pid == 0 ) {
	  //	  close(2);
		execv(ka_launch[0], ka_launch);
	} else {
		// wpid = wait(&status);   /* Child's exit status */
		wpid = wait4(-1, &status, 0, NULL);
		if ( wpid == -1 ) {
			fprintf(stderr,"%s: wait()\n", strerror(errno));
			return RETURN_ERROR;
		} else if ( wpid != pid )
			abort();
		else {
			if ( WIFEXITED(status) ) {
				printf("Exited: $? = %d\n", WEXITSTATUS(status));
			} else if ( WIFSIGNALED(status) ) {
				printf("Signal: %d%s\n", WTERMSIG(status), WCOREDUMP(status) ? " with core file." : "");
			}
		}
	}

	remove_wait_message();
	return RETURN_OK;
	//  if (!(pid = fork())) { /* Froking current process for running ka-deploy (client side) */
	//  close(1); /* Closing stdout */
	//  close(2); /* Closing stderr */
	//  execve(ka_launch[0], ka_launch,grab_env()); /* Running ka-deploy (client side) */
	//  printf("KA: Can't execute %s\n<press Enter>\n", ka_launch[0]);
	//  log_message("KA: Can't execute %s\n<press Enter>\n", ka_launch[0]);
	//  my_pause();
	//  return KAERR_CANTFORK;
	//}

	//while (wait4(-1, &wait_status, 0, NULL) != pid) {}; /* Waiting the end of duplication */
	//  log_message("kalaunch ret %d\n", WIFEXITED(wait_status));
	//  remove_wait_message();
	//sleep(100000);
	//  return RETURN_OK;
}

enum return_type perform_ka(void) {
	enum return_type results;
	int server_failure = 1; /* Number of time we've failed to find a ka server */
	FILE *f = fopen ("/ka/tftpserver","w");

	if (f != NULL) {
		/* Writing the NEXT_SERVER value of the DHCP Request in the /ka/tftpserver file */
		fprintf(f,"%s\n",inet_ntoa(next_server));
		fclose(f);
	}

	log_message("KA: Trying to retrieve stage2 from server");
	log_message("KA: ka_wait_for_stage2");
	do {
		/* We are trying to get a valid stage 2 (rescue) */
		results=ka_wait_for_stage2(server_failure);
		if (results != RETURN_OK) {
			return results;
		} else {
			/* Trying to open STAGE2_LOCATION/ka directory */
			char dir[255] = STAGE2_LOCATION;
			strcat(dir,"/ka");
			DIR *dp = opendir(dir);

			/* Does the STAGE2_LOCATION/ka directory exists ? = Does the rescue with ka well downloaded ?*/
			if (!dp) {
				log_message("KA: Server not found !");
				/* Be sure that the STAGE2_LOCATION isn't mounted after receiving a wrong rescue */
				if (umount (STAGE2_LOCATION)) {
					log_perror("KA: Unable to umount STAGE2");
				}
				int cpt;

				if (server_failure++ == KA_MAX_RETRY){
					/* if the KA server can't be reach KA_MAX_RETRY times */
					char * reboot_launch[] = { "/sbin/reboot", NULL};
					for (cpt=5; cpt>0; cpt--) {
						wait_message("!!! Can't reach a valid KA server !!! (Rebooting in %d sec)",cpt);
						sleep (1);
					}
					/* Rebooting the computer to avoid infinite loop on ka mode */
					execv(reboot_launch[0], reboot_launch);
				}

				for (cpt=5; cpt>0; cpt--) {
					wait_message("KA server not found ! (Try %d/%d in %d sec)",server_failure,KA_MAX_RETRY,cpt);
					log_message("Ka not found %d/%d", server_failure,KA_MAX_RETRY);
					sleep (1);
				}
				remove_wait_message();
				/* We should try another time*/
				results=RETURN_BACK;
				continue;
			}

			if (dp) {
				log_message("KA: Stage 2 downloaded successfully");
				closedir(dp); /* Closing the /ka directory */
				server_failure=1; /* Resetting server_failure */
				results = RETURN_OK;
			}
		}

		log_message("KA: Preparing chroot");
		return RETURN_OK;

		//    if (IS_RESCUE) { /* if we are in rescue mode */
		//      save_stuff_for_rescue(); /* Saving resolve.conf */
		//      if (umount (STAGE2_LOCATION)) { /* Unmounting STAGE2 elseif kernel can't mount it ! */
		// log_perror("KA: Unable to umount STAGE2");
		// return RETURN_ERROR;
		//      }
		//    }
	} while (results == RETURN_BACK);

	//  method_name = strdup("ka");
	return RETURN_OK;
}
