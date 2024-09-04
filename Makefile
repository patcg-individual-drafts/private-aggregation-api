# HTML files that are generated from Markdown sources.
HTML_FROM_MD_TARGETS=README.html README-with-toc.html

.PHONY: all
all: spec.html $(HTML_FROM_MD_TARGETS)

.PHONY: clean
clean:
	-rm spec.html
	-rm $(HTML_FROM_MD_TARGETS)

# Updates Bikeshed's datafiles. Bikeshed automatically updates them if they're
# more than a few days old, but this will ensure you have the latest version.
.PHONY: update
update:
	bikeshed update

spec.html: spec.bs
	bikeshed --die-on=everything spec $< $@

# Autogenerates a table of contents for the README. This can in turn be rendered
# as HTML. This is useful for catching mistakes in the README's handwritten TOC.
README-with-toc.md: README.md
	pandoc -f gfm --toc --toc-depth 6 -s $< -o $@

# Rule for generating HTML from Markdown for a limited set of targets. This uses
# GNU Make "static pattern" syntax.
$(HTML_FROM_MD_TARGETS): %.html : %.md
	pandoc -f gfm -s $< -o $@
