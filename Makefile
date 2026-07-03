# usbliter8_boot
#
# Builds against whatever libusb-1.0 you already have installed
# (brew install libusb / MSYS2 mingw-w64-x86_64-libusb), then BUNDLES the
# shared library right next to the binary and rewrites the binary's load
# path to look for it there instead of the Homebrew/MSYS2 path.
#
# Result: a folder you can copy anywhere / to another Mac or PC and run
# without brew, pacman, or Python installed on that machine.
#
#   macOS:            brew install libusb   (if not already)  -> make
#   Windows (MSYS2):  pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-libusb make
#                     (from the "MSYS2 MinGW64" shell)          -> make
#
#   macOS universal (arm64 + x86_64):  see the 'universal' target below.

TARGET = usbliter8_boot
SRC    = usbliter8_boot.c

UNAME_S := $(shell uname -s 2>/dev/null)

ifneq (,$(findstring MINGW,$(UNAME_S)))
  OUT = $(TARGET).exe
else
  OUT = $(TARGET)
endif

CC      ?= cc
CFLAGS  += -O2 -Wall $(shell pkg-config --cflags libusb-1.0)
LDFLAGS += $(shell pkg-config --libs libusb-1.0)

# avoid needing libgcc_s_seh-1.dll on the target Windows machine
ifneq (,$(findstring MINGW,$(UNAME_S)))
  LDFLAGS += -static-libgcc
endif

all: $(OUT) bundle

$(OUT): $(SRC)
	$(CC) $(CFLAGS) -o $(OUT) $(SRC) $(LDFLAGS)

# --- make it portable: copy the dylib/dll next to the binary -------------

bundle:
ifeq ($(UNAME_S),Darwin)
	@DEP_PATH=$$(otool -L $(OUT) | grep -o '[^ ]*libusb-1\.0[^ ]*\.dylib' | head -1); \
	if [ -z "$$DEP_PATH" ]; then echo "warning: libusb dependency not found via otool, skipping bundle"; exit 0; fi; \
	if [ -f "$$DEP_PATH" ]; then SRC_PATH="$$DEP_PATH"; \
	else \
	  LIBDIR=$$(pkg-config --variable=libdir libusb-1.0 2>/dev/null); \
	  SRC_PATH=$$(ls "$$LIBDIR"/libusb-1.0*.dylib 2>/dev/null | grep -v '\.la$$' | head -1); \
	fi; \
	if [ -z "$$SRC_PATH" ] || [ ! -f "$$SRC_PATH" ]; then \
	  echo "warning: could not locate the actual libusb .dylib on disk, skipping bundle"; \
	  echo "  (binary references: $$DEP_PATH -- that path/symlink seems missing)"; \
	  exit 0; \
	fi; \
	LIBUSB_NAME=$$(basename "$$SRC_PATH"); \
	cp "$$SRC_PATH" "./$$LIBUSB_NAME"; \
	chmod +w "./$$LIBUSB_NAME"; \
	install_name_tool -change "$$DEP_PATH" "@executable_path/$$LIBUSB_NAME" $(OUT); \
	install_name_tool -id "@executable_path/$$LIBUSB_NAME" "./$$LIBUSB_NAME"; \
	echo "bundled $$LIBUSB_NAME next to $(OUT) -- copy both files together, portable now"
else ifneq (,$(findstring MINGW,$(UNAME_S)))
	@DLL_PATH=$$(ldd $(OUT) | grep -o '[^ ]*libusb-1\.0[^ ]*\.dll' | head -1); \
	if [ -z "$$DLL_PATH" ]; then echo "warning: libusb-1.0.dll not found via ldd, skipping bundle"; exit 0; fi; \
	cp "$$DLL_PATH" .; \
	echo "bundled $$(basename $$DLL_PATH) next to $(OUT) -- copy both files together, portable now"
else
	@echo "bundle step only implemented for macOS/Windows targets"
endif

# --- Universal (arm64 + x86_64) build, macOS only -------------------------
#
# One-time setup on your Mac (needs internet -- run these yourself once):
#   softwareupdate --install-rosetta --agree-to-license
#   arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#   arch -x86_64 /usr/local/bin/brew install libusb
#
# (this installs a second, Intel/Rosetta Homebrew at /usr/local, alongside
#  your normal arm64 Homebrew at /opt/homebrew -- both can coexist)
#
# Then just:  make universal

ARM64_BREW = /opt/homebrew/bin/brew
X86_BREW   = /usr/local/bin/brew

universal:
	@if [ "$(UNAME_S)" != "Darwin" ]; then echo "error: universal target is macOS-only"; exit 1; fi
	@if [ ! -x $(ARM64_BREW) ] || [ ! -x $(X86_BREW) ]; then \
	  echo "error: need both /opt/homebrew (arm64) and /usr/local (x86_64/Rosetta) Homebrew."; \
	  echo "See the setup commands in the comment above the 'universal' target in this Makefile."; \
	  exit 1; \
	fi
	@set -e; \
	SDKROOT=$$(xcrun --sdk macosx --show-sdk-path); \
	ARM64_PREFIX=$$($(ARM64_BREW) --prefix libusb); \
	X86_PREFIX=$$(arch -x86_64 $(X86_BREW) --prefix libusb); \
	if [ -z "$$ARM64_PREFIX" ] || [ -z "$$X86_PREFIX" ]; then \
	  echo "error: libusb not installed for one of the two architectures."; \
	  echo "  arm64:  $(ARM64_BREW) install libusb"; \
	  echo "  x86_64: arch -x86_64 $(X86_BREW) install libusb"; \
	  exit 1; \
	fi; \
	echo "SDK: $$SDKROOT"; \
	echo "arm64  libusb: $$ARM64_PREFIX"; \
	echo "x86_64 libusb: $$X86_PREFIX"; \
	xcrun clang -O2 -Wall -arch arm64  -isysroot "$$SDKROOT" -I$$ARM64_PREFIX/include/libusb-1.0 -o $(TARGET)_arm64  $(SRC) -L$$ARM64_PREFIX/lib -lusb-1.0; \
	xcrun clang -O2 -Wall -arch x86_64 -isysroot "$$SDKROOT" -I$$X86_PREFIX/include/libusb-1.0   -o $(TARGET)_x86_64 $(SRC) -L$$X86_PREFIX/lib -lusb-1.0; \
	lipo -create $(TARGET)_arm64 $(TARGET)_x86_64 -output $(TARGET); \
	rm -f $(TARGET)_arm64 $(TARGET)_x86_64; \
	lipo -create $$ARM64_PREFIX/lib/libusb-1.0.0.dylib $$X86_PREFIX/lib/libusb-1.0.0.dylib -output ./libusb-1.0.0.dylib; \
	chmod +w ./libusb-1.0.0.dylib; \
	install_name_tool -change $$ARM64_PREFIX/lib/libusb-1.0.0.dylib @executable_path/libusb-1.0.0.dylib $(TARGET) 2>/dev/null || true; \
	install_name_tool -change $$X86_PREFIX/lib/libusb-1.0.0.dylib  @executable_path/libusb-1.0.0.dylib $(TARGET) 2>/dev/null || true; \
	install_name_tool -id @executable_path/libusb-1.0.0.dylib ./libusb-1.0.0.dylib; \
	echo "done -- universal binary + universal dylib:"; \
	lipo -info $(TARGET); \
	lipo -info ./libusb-1.0.0.dylib

clean:
	rm -f $(TARGET) $(TARGET).exe $(TARGET)_arm64 $(TARGET)_x86_64 libusb-1.0*.dylib libusb-1.0*.dll

.PHONY: all bundle universal clean
