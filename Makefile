PREFIX = /usr/local

upd-r-pkg: upd-r-pkg.sh get-updates.R output-pkgbuild.R
	cat upd-r-pkg.sh > $@
	echo 'exit 0' >> $@
	echo '#EOF' >> $@
	tar czf - get-updates.R output-pkgbuild.R >> $@
	chmod +x $@

test: upd-r-pkg.sh
	shellcheck -s sh upd-r-pkg.sh

clean:
	rm -f upd-r-pkg

install: upd-r-pkg
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f upd-r-pkg $(DESTDIR)$(PREFIX)/bin
	chmod 744 $(DESTDIR)$(PREFIX)/bin/upd-r-pkg

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/upd-r-pkg

.PHONY: test clean install uninstall
