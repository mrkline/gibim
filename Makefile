DC = dmd

all: debug

debug:
	$(DC) -w -wi -debug -unittest -ofgibim *.d

release:
	$(DC) -w -wi -release -O -ofgibim *.d

clean:
	rm -f gibim *.o

.PHONY: clean, debug, release
