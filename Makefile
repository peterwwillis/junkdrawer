all: shellcheck README.md

README.md:
	./make-readme.sh > README.md

shellcheck:
	for i in $$(grep -m1 -l -E '#!.*sh$$' * 2>/dev/null) ; do shellcheck -Calways "$$i" ; done

clean:
	rm -f README.md
