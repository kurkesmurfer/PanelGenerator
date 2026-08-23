.PHONY: build release run app selftest demo clean

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

demo: selftest
	@echo "Demo assets refreshed in Docs/"

clean:
	swift package clean
	rm -rf PanelGenerator.app
