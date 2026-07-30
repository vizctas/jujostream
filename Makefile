SHELL = cmd.exe

# JujoStream Android Build Makefile
.DEFAULT_GOAL := help

# Intercept command line argument for cbuild {version}
ifeq (cbuild,$(firstword $(MAKECMDGOALS)))
  VERSION := $(word 2,$(MAKECMDGOALS))
  ifeq ($(VERSION),)
    $(error Version is required. Example: make cbuild 1.1.13)
  endif
  TAG := client-$(VERSION)
  $(eval $(VERSION):;@:)
endif

# Intercept command line argument for Grelease client-{version}
ifeq (Grelease,$(firstword $(MAKECMDGOALS)))
  VERSION_ARG := $(word 2,$(MAKECMDGOALS))
  ifeq ($(VERSION_ARG),)
    LATEST_CLIENT_TAG := $(shell git tag --list "client-[0-9]*" --sort=-v:refname | powershell -NoProfile -Command "$$input | Select-Object -First 1")
    ifeq ($(LATEST_CLIENT_TAG),)
      VERSION := 1.0.0
    else
      VERSION := $(shell powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bump_client_version.ps1 -LatestTag $(LATEST_CLIENT_TAG))
    endif
  else
    VERSION := $(patsubst client-%,%,$(VERSION_ARG))
    $(eval $(VERSION_ARG):;@:)
  endif
  TAG := client-$(VERSION)
endif

# Supabase Credentials
SUPABASE_URL ?= https://faadppubtdxjnnvubnsi.supabase.co
SUPABASE_PUBLISHABLE_KEY ?= sb_publishable_xSfpJSBypMPXXCWeeYBgVQ_U6gu57NH

# Release config
GITHUB_REPO ?= vizctas/Jujo.StreamServer.Releases
RELEASE_DIST ?= dist
RELEASE_NOTES ?= JujoStream client release $(TAG)

# Dart defines
DART_DEFINES = --dart-define=SUPABASE_URL=$(SUPABASE_URL) \
               --dart-define=SUPABASE_PUBLISHABLE_KEY=$(SUPABASE_PUBLISHABLE_KEY)
PATCH_BUILT_IN_KOTLIN = powershell -NoProfile -ExecutionPolicy Bypass -File scripts/patch_flutter_plugins_built_in_kotlin.ps1


#flutter run apk --release --dart-define=SUPABASE_URL=$(SUPABASE_URL) --dart-define=SUPABASE_PUBLISHABLE_KEY=$(SUPABASE_PUBLISHABLE_KEY)


# Derived from TAG (e.g. client-1.1.13 or v1.1.13)
APP_VERSION    = $(patsubst client-%,%,$(patsubst v%,%,$(TAG)))
RELEASE_DIR    = $(RELEASE_DIST)/$(TAG)
APK_SRC        = build/app/outputs/flutter-apk/app-release.apk
AAB_SRC        = build/app/outputs/bundle/release/app-release.aab
# The whole Release folder is the Windows app, not just the .exe: the runner
# needs flutter_windows.dll, every plugin DLL, and data/ — which holds app.so,
# the AOT snapshot carrying the --dart-define values. Shipping the bare exe
# produced a 626 KB download that cannot start.
WIN_SRC_DIR    = build/windows/x64/runner/Release
APK_NAME       = JujoStream-$(TAG)-android.apk
AAB_NAME       = JujoStream-$(TAG)-android.aab
ZIP_NAME       = JujoStream-$(TAG)-windows-x64.zip
APK_OUT        = $(RELEASE_DIR)/$(APK_NAME)
AAB_OUT        = $(RELEASE_DIR)/$(AAB_NAME)
ZIP_OUT        = $(RELEASE_DIR)/$(ZIP_NAME)
SHA_OUT        = $(RELEASE_DIR)/SHA256SUMS.txt

.PHONY: help setup-android-deps verify-android-keystore validate-release-tag build-apk build-aab release-apk release-apk-dry-run clean cbuild Grelease

help:
	@echo "JujoStream Android Automation Makefile"
	@echo "======================================="
	@echo "Available commands:"
	@echo "  make setup-android-deps      - Init submodules + build OpenSSL & libopus for Android"
	@echo "  make verify-android-keystore - Validate Android release keystore without printing secrets"
	@echo "  make build-apk               - Build release APK with Supabase config"
	@echo "  make build-aab               - Build release AAB (Play Store) with Supabase config"
	@echo "  make cbuild {version}        - Full pipeline build & release with tag client-{version}"
	@echo "  make release-apk TAG=v1.1.13"
	@echo "                               - Build APK and publish GitHub release"
	@echo "  make release-apk-dry-run TAG=v1.1.13"
	@echo "                               - Print release commands without publishing"
	@echo "  make clean                   - Clean build artifacts"

# Android NDK path (auto-detected or override with: make setup-android-deps ANDROID_NDK_HOME=...)
ANDROID_NDK_HOME ?= $(LOCALAPPDATA)/Android/Sdk/ndk/28.2.13676358
# MSYS2 path version of the repo root (e.g. /c/Users/...)
CURDIR_MSYS = $(subst \,/,$(subst C:,/c,$(CURDIR)))
NDK_HOME_MSYS = $(subst \,/,$(subst C:,/c,$(ANDROID_NDK_HOME)))

setup-android-deps:
	git submodule update --init --recursive android/app/src/main/cpp/moonlight-common-c
	C:/msys64/usr/bin/bash.exe -l -c "cd '$(CURDIR_MSYS)' && ANDROID_NDK_HOME='$(NDK_HOME_MSYS)' NDK_HOME='' bash setup_native_deps.sh"

verify-android-keystore:
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify_android_keystore.ps1

validate-release-tag:
	powershell -NoProfile -Command "if ('$(TAG)' -notmatch '^(?:client-|v)\d+\.\d+\.\d+$$') { Write-Error \"TAG must match client-X.Y.Z or vX.Y.Z. Got: $(TAG)\"; exit 1 }"

rapk:
	flutter build apk --release $(DART_DEFINES)

build-apk: verify-android-keystore
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update_app_version.ps1 $(APP_VERSION)
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build apk --release $(DART_DEFINES)

build-aab: verify-android-keystore
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update_app_version.ps1 $(APP_VERSION)
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build appbundle --release $(DART_DEFINES)
	@echo "AAB built: $(AAB_SRC)"

release-apk-dry-run: validate-release-tag
	@echo "Version:         $(APP_VERSION)"
	@echo "Repo:            $(GITHUB_REPO)"
	@echo "APK output:      $(APK_OUT)"
	@echo "AAB output:      $(AAB_OUT)"
	@echo "Build APK:       flutter build apk --release $(DART_DEFINES)"
	@echo "Build AAB:       flutter build appbundle --release $(DART_DEFINES)"
	@echo "Git tag:         git tag $(TAG) && git push origin $(TAG)"
	@echo "GH release:      gh release create $(TAG) \"$(APK_OUT)\" \"$(AAB_OUT)\" \"$(SHA_OUT)\" --repo $(GITHUB_REPO) --title \"JujoStream $(TAG)\" --notes \"$(RELEASE_NOTES)\""

$(RELEASE_DIR): validate-release-tag
	powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path '$(RELEASE_DIR)' | Out-Null"

$(RELEASE_DIR)/build-all: validate-release-tag $(RELEASE_DIR) verify-android-keystore
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update_app_version.ps1 $(APP_VERSION)
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build apk --release $(DART_DEFINES)
	flutter build appbundle --release $(DART_DEFINES)
	flutter build windows --release $(DART_DEFINES)
	powershell -NoProfile -Command "Copy-Item -LiteralPath '$(APK_SRC)' -Destination '$(APK_OUT)' -Force"
	powershell -NoProfile -Command "Copy-Item -LiteralPath '$(AAB_SRC)' -Destination '$(AAB_OUT)' -Force"
	powershell -NoProfile -Command "if (-not (Test-Path -LiteralPath '$(WIN_SRC_DIR)/data/app.so')) { throw 'Windows build is incomplete: data/app.so is missing.' }"
	powershell -NoProfile -Command "if (Test-Path -LiteralPath '$(ZIP_OUT)') { Remove-Item -LiteralPath '$(ZIP_OUT)' -Force }; Compress-Archive -Path '$(WIN_SRC_DIR)/*' -DestinationPath '$(ZIP_OUT)'"
	powershell -NoProfile -Command "Set-Content -LiteralPath '$(SHA_OUT)' -Value @(((Get-FileHash -Algorithm SHA256 -LiteralPath '$(APK_OUT)').Hash.ToLowerInvariant() + '  $(APK_NAME)'), ((Get-FileHash -Algorithm SHA256 -LiteralPath '$(ZIP_OUT)').Hash.ToLowerInvariant() + '  $(ZIP_NAME)')) -Encoding ascii"
	powershell -NoProfile -Command "New-Item -ItemType File -Path '$(RELEASE_DIR)/build-all' -Force | Out-Null"

$(APK_OUT): $(RELEASE_DIR)/build-all

$(SHA_OUT): $(RELEASE_DIR)/build-all

release-apk: validate-release-tag $(SHA_OUT)
	git tag -f $(TAG)
	set GIT_TERMINAL_PROMPT=0&& git push origin $(TAG) -f
	gh release create $(TAG) "$(APK_OUT)" "$(AAB_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --title "JujoStream $(TAG)" --notes "$(RELEASE_NOTES)" 2>NUL || \
	gh release upload $(TAG) "$(APK_OUT)" "$(AAB_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --clobber

Grelease: validate-release-tag $(RELEASE_DIR)/build-all
	git tag -f $(TAG)
	set GIT_TERMINAL_PROMPT=0&& git push origin $(TAG) -f
	gh release create $(TAG) "$(APK_OUT)" "$(ZIP_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --title "JujoStream $(TAG)" --notes "$(RELEASE_NOTES)" 2>NUL || \
	gh release upload $(TAG) "$(APK_OUT)" "$(ZIP_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --clobber

cbuild: release-apk
	@echo "Build and release completed for version $(VERSION) with tag $(TAG)"

clean:
	flutter clean
	powershell -NoProfile -Command "if (Test-Path 'dist') { Remove-Item -Recurse -Force 'dist' }"
