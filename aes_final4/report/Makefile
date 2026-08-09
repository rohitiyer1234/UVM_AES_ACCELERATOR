# =============================================================================
#  report/Makefile
#
#  Two-pass pdflatex + bibtex build for aes_report.tex.
#  Requires: pdflatex, bibtex (TeX Live, MacTeX, or MikTeX).
# =============================================================================

DOC = aes_report
TEX = $(DOC).tex
BIB = refs.bib

all: $(DOC).pdf

$(DOC).pdf: $(TEX) $(BIB)
	pdflatex -interaction=nonstopmode $(DOC)
	bibtex $(DOC) || true
	pdflatex -interaction=nonstopmode $(DOC)
	pdflatex -interaction=nonstopmode $(DOC)

clean:
	rm -f *.aux *.bbl *.blg *.log *.out *.toc *.lof *.lot *.synctex.gz \
	      *.fls *.fdb_latexmk

distclean: clean
	rm -f $(DOC).pdf
