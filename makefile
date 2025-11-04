TARGET = socks
SRCDIR = src
SRCS = $(SRCDIR)/socks.c
CFLAGS ?=

all:
	$(CC) $(CFLAGS) -Isrc -o $(TARGET) $(SRCS)

run: all
	./$(TARGET)

clean:
	rm -f $(TARGET)

test: all
	@PY_CMD=$${PYTHON_CMD:-} PYTHON_CMD=$${PY_CMD} ./tests/test.sh

.PHONY: all run clean test
