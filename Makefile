DESTDIR=$(HOME)/.local/bin

SCRIPTS=add-sources debarchiver.pl fix-repo InsertableOrderedDict.py insert_source_lines.py print_debarchiver_config.pl update-repo update-repo.json

install:
	cp $(SCRIPTS) "$(DESTDIR)"
	ln -s debarchiver.pl "$(DESTDIR)"/debarchiver

.PHONY: install
