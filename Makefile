all:
	@echo "Nothing to make."

clean:
	rm -rf core *~ tmpdir

check:
	./get-gauche.sh --force --prefix=tmpdir --version snapshot --auto \
	  && tmpdir/bin/gosh -V

