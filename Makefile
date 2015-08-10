DC = dmd
DFLAGS = -w -wi

all: debug

debug: DFLAGS += -debug -unittest -g
debug: gibim

release: DFLAGS += -release -O
release: gibim

gibim: gibim.d help.d
	$(DC) $(DFLAGS) -of$@ $^

clean:
	rm -f gibim *.o

.PHONY: all, clean, debug, release
