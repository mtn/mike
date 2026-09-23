DERIVED_DATA := .build/XcodeDerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/Mike.app
SIGNING_IDENTITY ?= Apple Development: michaeltnoronha@gmail.com (NEE55QD8MR)

.PHONY: app open test

app:
	xcodegen generate
	xcodebuild \
		-project Mike.xcodeproj \
		-scheme Mike \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=macOS,arch=arm64' \
		build \
		CODE_SIGNING_ALLOWED=NO
	codesign --force --deep --sign '$(SIGNING_IDENTITY)' $(APP)

open: app
	open -a '$(CURDIR)/$(APP)'

test:
	swift format lint --recursive --strict Package.swift App Sources Tests
	swift test
