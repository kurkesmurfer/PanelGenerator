.PHONY: build release run app selftest emit compare demo clean

build:
	swift build

release:
	swift build -c release

run: build
	.build/debug/PanelGenerator

app: release
	bash Scripts/make-app.sh

selftest: build
	.build/debug/PanelGenerator --selftest Docs

# make emit DOC=Panels/Thing.panelgen OUT=build/Thing [THEME=dark|light|both]
# DOC may also be a folder — every panel in it is emitted, and the plugin's
# widget library is written once across all of them. THEME defaults to
# "auto" (dark always, plus a light SVG only for a document that declares
# one) -- see PIPELINE.md.
OUT ?= build/emit
emit: build
	@test -n "$(DOC)" || (echo "usage: make emit DOC=<file.panelgen|folder> [OUT=<dir>] [THEME=dark|light|both]"; exit 1)
	.build/debug/PanelGenerator --emit $(DOC) $(OUT) $(if $(THEME),--theme $(THEME))

# Does the design still agree with the code? Each side may be a .panelgen, a
# module's .cpp, or an SVG with a components layer.
#   make compare A=~/Development/Muse/vcv/Muse.cpp B=Panels/Muse.panelgen
# NOLABELS=1 skips the label comparison — use it against generated code, which
# carries no labels because PanelGenerator draws them into the panel artwork.
TOL ?= 0.01
compare: build
	@test -n "$(A)" -a -n "$(B)" || (echo "usage: make compare A=<file> B=<file> [TOL=<mm>]"; exit 1)
	.build/debug/PanelGenerator --compare $(A) $(B) --tolerance $(TOL) $(if $(NOLABELS),--no-labels)

demo: selftest
	@echo "Demo assets refreshed in Docs/"

clean:
	swift package clean
	rm -rf PanelGenerator.app
