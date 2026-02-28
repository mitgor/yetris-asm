# yetris-asm Makefile
# AArch64 Assembly Tetris for macOS Apple Silicon

PACKAGE  = yetris-asm
BIN_DIR  = bin
EXE      = $(BIN_DIR)/$(PACKAGE)
SOURCES  = $(wildcard *.s)
OBJECTS  = $(SOURCES:.s=.o)
SDK_PATH = $(shell xcrun --show-sdk-path)

# Verbose mode: make V=1
ifdef V
MUTE =
else
MUTE = @
endif

all: $(EXE)
	# Build successful!

%.o: %.s
	# Assembling $<...
	$(MUTE)as -o $@ $<

$(EXE): $(OBJECTS) | $(BIN_DIR)
	# Linking...
	$(MUTE)ld -o $@ $(OBJECTS) -lncurses -lSystem \
		-syslibroot $(SDK_PATH) -arch arm64 \
		-dead_strip

$(BIN_DIR):
	$(MUTE)mkdir -p $(BIN_DIR)

run: all
	$(MUTE)./$(EXE)

strip: all
	# Creating stripped binary...
	$(MUTE)cp $(EXE) $(EXE)-stripped
	$(MUTE)strip -x $(EXE)-stripped
	@echo "Stripped binary: $(EXE)-stripped"
	@ls -la $(EXE) $(EXE)-stripped

clean:
	# Cleaning...
	$(MUTE)rm -f $(OBJECTS) $(EXE) $(EXE)-stripped

profile: all
	# Recording 10-second Time Profiler trace...
	xcrun xctrace record \
		--template 'Time Profiler' \
		--time-limit 10s \
		--output yetris-profile.trace \
		--launch -- ./$(EXE)

.PHONY: all run strip clean profile
