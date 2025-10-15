// Simple echo test - reads from stdin, writes to stdout
#include <stdio.h>
#include <unistd.h>

int main() {
    fprintf(stderr, "Echo test starting...\n");

    char buf[1024];
    ssize_t n;

    while ((n = read(STDIN_FILENO, buf, sizeof(buf))) > 0) {
        fprintf(stderr, "Read %zd bytes\n", n);
        write(STDOUT_FILENO, buf, n);
        fprintf(stderr, "Wrote %zd bytes\n", n);
    }

    fprintf(stderr, "Echo test done\n");
    return 0;
}
