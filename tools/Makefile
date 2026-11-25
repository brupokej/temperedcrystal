.PHONY: all clean

CC := gcc
CFLAGS := -O3 -std=c17 -Wall -Wextra -pedantic

tools := \
	bankends \
	gbcpal \
	gfx \
	lzcompress \
	png_dimensions \
	pokemon_animation \
	pokemon_animation_graphics \
	scan_includes

all: $(tools)
	@:

clean:
	$(RM) $(tools) *.o

bankends: bankends.c parsemap.o
	$(CC) $(CFLAGS) -o $@ $^

parsemap.o: parsemap.c parsemap.h
	$(CC) $(CFLAGS) -c -o $@ $<

%: %.c common.h
	$(CC) $(CFLAGS) -o $@ $<
