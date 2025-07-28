DESTDIR=$(HOME)/.local/bin

SCRIPTS=add_sources debarchiver.pl fix-repo InsertableOrderedDict.py insert_source_lines.py print_debarchiver_config.pl update-repo update-repo.json

install:
	cp $(SCRIPTS) "$(DESTDIR)"

.PHONY: install
