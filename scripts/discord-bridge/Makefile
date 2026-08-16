CC = x86_64-w64-mingw32-gcc
CFLAGS = -O2 -Wall -Wextra
TARGET := WhiskyDiscordBridge.exe
RESOURCES := ../../WhiskyKit/Sources/WhiskyKit/Discord/Resources

all: $(TARGET)

$(TARGET): bridge.c
	$(CC) $(CFLAGS) -mwindows -static -s -o $@ $<

install: $(TARGET)
	mkdir -p $(RESOURCES)
	cp $(TARGET) $(RESOURCES)/$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all install clean
