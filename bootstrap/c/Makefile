CC ?= cc
ATSFLAGS := -D_ATS_CCOMP_HEADER_NONE_ -D_ATS_CCOMP_EXCEPTION_NONE_ -D_ATS_CCOMP_PRELUDE_NONE_ -D_ATS_CCOMP_RUNTIME_NONE_ -include _bats_native_runtime.h -I_bats_native_stubs

%_debug.o: %.c
	$(CC) -c -o $@ $< -g -O0 $(ATSFLAGS)

%_release.o: %.c
	$(CC) -c -o $@ $< -O2 $(ATSFLAGS)

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

PREFIX ?= $(HOME)/.bats

install: release/bats
	mkdir -p $(PREFIX)/bin
	cp release/bats $(PREFIX)/bin/bats.new
	mv -f $(PREFIX)/bin/bats.new $(PREFIX)/bin/bats

clean:
	rm -f *.o
	rm -rf debug release
