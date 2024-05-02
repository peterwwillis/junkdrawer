all: README.md

README.md:
	./make-readme.sh > README.md

clean:
	rm -f README.md
