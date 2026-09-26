PATSHOME ?= $(HOME)/.bats/ats2
CC ?= cc

%_debug.o: %.c
	$(CC) -c -o $@ $< -g -O0 -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime

%_release.o: %.c
	$(CC) -c -o $@ $< -O2 -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime

SRCS := $(shell find . -name '*_dats.c') _bats_native_runtime.c
DEBUG_OBJS := $(SRCS:.c=_debug.o)
RELEASE_OBJS := $(SRCS:.c=_release.o)

all: debug/bats release/bats

debug/bats: $(DEBUG_OBJS)
	mkdir -p debug
	$(CC) -o $@ $^ -g -O0

release/bats: $(RELEASE_OBJS)
	mkdir -p release
	$(CC) -o $@ $^ -O2

clean:
	rm -f *.o
	rm -rf debug release
