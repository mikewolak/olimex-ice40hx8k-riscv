#===============================================================================
# ZMODEM Library Test Makefile
#===============================================================================

CC = gcc
CFLAGS = -Wall -Wextra -O2 -g -I.

# Test programs
TARGETS = sz_test rz_test

.PHONY: all clean test

all: $(TARGETS)

sz_test: sz_test.c zmodem.c zmodem.h
	$(CC) $(CFLAGS) -o sz_test sz_test.c zmodem.c

rz_test: rz_test.c zmodem.c zmodem.h
	$(CC) $(CFLAGS) -o rz_test rz_test.c zmodem.c

# Run tests
test: $(TARGETS)
	@echo "========================================="
	@echo "ZMODEM Protocol Tests"
	@echo "========================================="
	@./test_zmodem.sh

clean:
	rm -f $(TARGETS) *.o test_*.bin received.bin
	@echo "Clean complete"
