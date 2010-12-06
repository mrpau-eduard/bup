OS:=$(shell uname | sed 's/[-_].*//')
CFLAGS=-Wall -g -O2 -Werror $(PYINCLUDE) -g
ifneq ($(OS),CYGWIN)
  CFLAGS += -fPIC
endif
SHARED=-shared
SOEXT:=.so

ifeq (${OS},Darwin)
  MACHINE:=$(shell arch)
  CFLAGS += -arch $(MACHINE)
  SHARED = -dynamiclib
endif
ifeq ($(OS),CYGWIN)
  LDFLAGS += -L/usr/bin
  EXT:=.exe
  SOEXT:=.dll
endif

default: all

all: bup Documentation/all

bup: lib/bup/_version.py lib/bup/_helpers$(SOEXT) cmds

Documentation/all: bup

INSTALL=install
PYTHON=python
MANDIR=$(DESTDIR)/usr/share/man
DOCDIR=$(DESTDIR)/usr/share/doc/bup
BINDIR=$(DESTDIR)/usr/bin
LIBDIR=$(DESTDIR)/usr/lib/bup
install: all
	$(INSTALL) -d $(MANDIR)/man1 $(DOCDIR) $(BINDIR) \
		$(LIBDIR)/bup $(LIBDIR)/cmd $(LIBDIR)/tornado \
		$(LIBDIR)/web $(LIBDIR)/web/static
	[ ! -e Documentation/.docs-available ] || \
	  $(INSTALL) -m 0644 \
		Documentation/*.1 \
		$(MANDIR)/man1
	[ ! -e Documentation/.docs-available ] || \
	  $(INSTALL) -m 0644 \
		Documentation/*.html \
		$(DOCDIR)
	$(INSTALL) -m 0755 bup $(BINDIR)
	$(INSTALL) -m 0755 \
		cmd/bup-* \
		$(LIBDIR)/cmd
	$(INSTALL) -m 0644 \
		lib/bup/*.py \
		$(LIBDIR)/bup
	$(INSTALL) -m 0755 \
		lib/bup/*$(SOEXT) \
		$(LIBDIR)/bup
	$(INSTALL) -m 0644 \
		lib/tornado/*.py \
		$(LIBDIR)/tornado
	$(INSTALL) -m 0644 \
		lib/web/static/* \
		$(LIBDIR)/web/static/
	$(INSTALL) -m 0644 \
		lib/web/*.html \
		$(LIBDIR)/web/
%/all:
	$(MAKE) -C $* all

%/clean:
	$(MAKE) -C $* clean

lib/bup/_helpers$(SOEXT): \
		lib/bup/bupsplit.c lib/bup/_helpers.c lib/bup/csetup.py
	@rm -f $@
	cd lib/bup && $(PYTHON) csetup.py build
	cp lib/bup/build/*/_helpers$(SOEXT) lib/bup/

.PHONY: lib/bup/_version.py
lib/bup/_version.py:
	rm -f $@ $@.new
	./format-subst.pl $@.pre >$@.new
	mv $@.new $@

runtests: all runtests-python runtests-cmdline

runtests-python:
	$(PYTHON) wvtest.py $(wildcard t/t*.py lib/*/t/t*.py)

runtests-cmdline: all
	t/test.sh

stupid:
	PATH=/bin:/usr/bin $(MAKE) test

test: all
	./wvtestrun $(MAKE) PYTHON=$(PYTHON) runtests

check: test

%: %.o
	$(CC) $(CFLAGS) (LDFLAGS) -o $@ $^ $(LIBS)

bup: main.py
	rm -f $@
	ln -s $< $@

cmds: \
    $(patsubst cmd/%-cmd.py,cmd/bup-%,$(wildcard cmd/*-cmd.py)) \
    $(patsubst cmd/%-cmd.sh,cmd/bup-%,$(wildcard cmd/*-cmd.sh))

cmd/bup-%: cmd/%-cmd.py
	rm -f $@
	ln -s $*-cmd.py $@

%: %.py
	rm -f $@
	ln -s $< $@

bup-%: cmd-%.sh
	rm -f $@
	ln -s $< $@

cmd/bup-%: cmd/%-cmd.sh
	rm -f $@
	ln -s $*-cmd.sh $@

%.o: %.c
	gcc -c -o $@ $< $(CPPFLAGS) $(CFLAGS)
	
# update the local 'man' and 'html' branches with pregenerated output files, for
# people who don't have pandoc (and maybe to aid in google searches or something)
export-docs: Documentation/all
	git update-ref refs/heads/man origin/man '' 2>/dev/null || true
	git update-ref refs/heads/html origin/html '' 2>/dev/null || true
	GIT_INDEX_FILE=gitindex.tmp; export GIT_INDEX_FILE; \
	rm -f $${GIT_INDEX_FILE} && \
	git add -f Documentation/*.1 && \
	git update-ref refs/heads/man \
		$$(echo "Autogenerated man pages for $$(git describe)" \
		    | git commit-tree $$(git write-tree --prefix=Documentation) \
				-p refs/heads/man) && \
	rm -f $${GIT_INDEX_FILE} && \
	git add -f Documentation/*.html && \
	git update-ref refs/heads/html \
		$$(echo "Autogenerated html pages for $$(git describe)" \
		    | git commit-tree $$(git write-tree --prefix=Documentation) \
				-p refs/heads/html)

# push the pregenerated doc files to origin/man and origin/html
push-docs: export-docs
	git push origin man html

# import pregenerated doc files from origin/man and origin/html, in case you
# don't have pandoc but still want to be able to install the docs.
import-docs: Documentation/clean
	git archive origin/html | (cd Documentation; tar -xvf -)
	git archive origin/man | (cd Documentation; tar -xvf -)

clean: Documentation/clean
	rm -f *.o lib/*/*.o *.so lib/*/*.so *.dll *.exe \
		.*~ *~ */*~ lib/*/*~ lib/*/*/*~ \
		*.pyc */*.pyc lib/*/*.pyc lib/*/*/*.pyc \
		bup bup-* cmd/bup-* lib/bup/_version.py randomgen memtest \
		out[12] out2[tc] tags[12] tags2[tc]
	rm -rf *.tmp t/*.tmp lib/*/*/*.tmp build lib/bup/build
