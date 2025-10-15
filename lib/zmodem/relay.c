/*
 * Simple relay to connect sz_test and rz_test bidirectionally
 * Creates two pipes for bidirectional communication
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <string.h>
#include <fcntl.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <testfile>\n", argv[0]);
        return 1;
    }

    int tx_to_rx[2];  // sz_test stdout -> rz_test stdin
    int rx_to_tx[2];  // rz_test stdout -> sz_test stdin

    if (pipe(tx_to_rx) < 0 || pipe(rx_to_tx) < 0) {
        perror("pipe");
        return 1;
    }

    // Increase pipe buffer size to 1MB to avoid deadlocks with large transfers
    // F_SETPIPE_SZ is Linux-specific
    #ifdef F_SETPIPE_SZ
    int ret1 = fcntl(tx_to_rx[0], F_SETPIPE_SZ, 1024 * 1024);
    int ret2 = fcntl(tx_to_rx[1], F_SETPIPE_SZ, 1024 * 1024);
    fprintf(stderr, "[RELAY] Set pipe buffer: ret=%d/%d\n", ret1, ret2);
    fcntl(rx_to_tx[0], F_SETPIPE_SZ, 1024 * 1024);
    fcntl(rx_to_tx[1], F_SETPIPE_SZ, 1024 * 1024);
    #else
    fprintf(stderr, "[RELAY] F_SETPIPE_SZ not available\n");
    #endif

    // Fork receiver first
    pid_t rx_pid = fork();
    if (rx_pid < 0) {
        perror("fork");
        return 1;
    }

    if (rx_pid == 0) {
        // Child: rz_test
        close(tx_to_rx[1]);  // Close write end of incoming pipe
        close(rx_to_tx[0]);  // Close read end of outgoing pipe

        dup2(tx_to_rx[0], STDIN_FILENO);   // Read from sz_test
        dup2(rx_to_tx[1], STDOUT_FILENO);  // Write to sz_test

        // Also redirect stderr to a file for debugging
        FILE *log = fopen("rx_debug.log", "w");
        if (log) {
            dup2(fileno(log), STDERR_FILENO);
            setbuf(stderr, NULL);  // Unbuffered
        }

        close(tx_to_rx[0]);
        close(rx_to_tx[1]);

        execl("./rz_test", "rz_test", NULL);
        perror("execl rz_test");
        exit(1);
    }

    // Parent: close rx_pid's pipe ends since we won't use them
    close(tx_to_rx[0]);  // rx reads from here
    close(rx_to_tx[1]);  // rx writes to here

    // Give receiver time to start
    usleep(200000);  // 200ms

    // Fork sender
    pid_t tx_pid = fork();
    if (tx_pid < 0) {
        perror("fork");
        return 1;
    }

    if (tx_pid == 0) {
        // Child: sz_test
        dup2(rx_to_tx[0], STDIN_FILENO);   // Read from rz_test
        dup2(tx_to_rx[1], STDOUT_FILENO);  // Write to rz_test

        // Also redirect stderr to a file for debugging
        FILE *log = fopen("tx_debug.log", "w");
        if (log) {
            dup2(fileno(log), STDERR_FILENO);
            setbuf(stderr, NULL);  // Unbuffered
        }

        close(rx_to_tx[0]);
        close(tx_to_rx[1]);

        execl("./sz_test", "sz_test", argv[1], NULL);
        perror("execl sz_test");
        exit(1);
    }

    // Parent: close tx_pid's pipe ends since we won't use them
    close(rx_to_tx[0]);  // tx reads from here
    close(tx_to_rx[1]);  // tx writes to here

    // Wait for both children
    int status;
    waitpid(tx_pid, &status, 0);
    int tx_exit = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

    waitpid(rx_pid, &status, 0);
    int rx_exit = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

    if (tx_exit == 0 && rx_exit == 0) {
        printf("Transfer complete!\n");
        return 0;
    } else {
        fprintf(stderr, "Transfer failed (TX=%d, RX=%d)\n", tx_exit, rx_exit);
        return 1;
    }
}
