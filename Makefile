APP := build/KindleToPDF.app

.PHONY: app test run clean

app:
	./scripts/build-app.sh

test:
	swift test

# Opens the existing bundle; builds it first only if it is missing
# (rebuilding re-signs the app, which may reset its TCC permissions).
run:
	@test -d $(APP) || $(MAKE) app
	open $(APP)

clean:
	rm -rf .build build
