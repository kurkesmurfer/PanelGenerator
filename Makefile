.PHONY: build release run app selftest emit demo clean

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

# make emit DOC=Panels/Thing.panelgen OUT=build/Thing
OUT ?= build/emit
emit: build
	@test -n "$(DOC)" || (echo "usage: make emit DOC=<file.panelgen> [OUT=<dir>]"; exit 1)
	.build/debug/PanelGenerator --emit $(DOC) $(OUT)

demo: selftest
	@echo "Demo assets refreshed in Docs/"

clean:
	swift package clean
	rm -rf PanelGenerator.app
