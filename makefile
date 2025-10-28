TARGET = socks
SRC = socks.c

all:
	$(CC) -o $(TARGET) $(SRC)

run: all
	./$(TARGET)

clean:
	rm -f $(TARGET)

test:
	./test.sh

.PHONY: all run clean test
