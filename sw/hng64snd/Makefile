# The hng64 sound board emulator. `make bench` builds the native bench; run it from an MSYS2
# MINGW64 shell (Git Bash's make hands mingw g++ an unusable temp directory).
CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wno-sign-compare

CORE = nec_core.cpp v53.cpp l7a1045.cpp board.cpp
HDRS = $(wildcard *.h) $(wildcard nec/*)
OUT  ?= ../../obj_hng64snd

bench: $(OUT)/hng64snd_bench

$(OUT)/hng64snd_bench: $(CORE) bench.cpp $(HDRS)
	mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) -I. -o $@ $(CORE) bench.cpp

.PHONY: bench
