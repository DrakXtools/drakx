all: mar

clean:
	rm -f *.o mar

FLAGS = -Wall -Werror -O1 -fomit-frame-pointer -c

mar: mar-frontend.o mar-extract-only.o
	gcc -o mar mar-frontend.o mar-extract-only.o -lz

mar-frontend.o: mar-frontend.c mar.h
	gcc $(FLAGS) mar-frontend.c

mar-extract-only.o: mar-extract-only.c mar-extract-only.h mar.h
	gcc $(FLAGS) mar-extract-only.c