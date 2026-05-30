# JujoStream Android Build Makefile
.DEFAULT_GOAL := help

# Supabase Credentials
SUPABASE_URL ?= https://faadppubtdxjnnvubnsi.supabase.co
SUPABASE_PUBLISHABLE_KEY ?= sb_publishable_xSfpJSBypMPXXCWeeYBgVQ_U6gu57NH

# Release config
GITHUB_REPO ?= vizctas/jujostream
RELEASE_DIST ?= dist
RELEASE_NOTES ?= JujoStream Android release $(TAG)

# Dart defines
DART_DEFINES = --dart-define=SUPABASE_URL=$(SUPABASE_URL) \
               --dart-define=SUPABASE_PUBLISHABLE_KEY=$(SUPABASE_PUBLISHABLE_KEY)
PATCH_BUILT_IN_KOTLIN = powershell -NoProfile -ExecutionPolicy Bypass -File scripts/patch_flutter_plugins_built_in_kotlin.ps1

# Derived from TAG (e.g. v1.1.13)
APP_VERSION    = $(patsubst v%,%,$(TAG))
RELEASE_DIR    = $(RELEASE_DIST)/$(TAG)
APK_SRC        = build/app/outputs/flutter-apk/app-release.apk
AAB_SRC        = build/app/outputs/bundle/release/app-release.aab
APK_NAME       = JujoStream-$(TAG)-android.apk
AAB_NAME       = JujoStream-$(TAG)-android.aab
APK_OUT        = $(RELEASE_DIR)/$(APK_NAME)
AAB_OUT        = $(RELEASE_DIR)/$(AAB_NAME)
SHA_OUT        = $(RELEASE_DIR)/SHA256SUMS.txt

.PHONY: help setup-android-deps verify-android-keystore build-apk build-aab release-apk release-apk-dry-run clean

help:
	@echo "JujoStream Android Automation Makefile"
	@echo "======================================="
	@echo "Available commands:"
	@echo "  make setup-android-deps     - Init submodules + build OpenSSL & libopus for Android"
	@echo "  make verify-android-keystore - Validate Android release keystore without printing secrets"
	@echo "  make build-apk              - Build release APK with Supabase config"
	@echo "  make build-aab              - Build release AAB (Play Store) with Supabase config"
	@echo "  make release-apk TAG=v1.1.13"
	@echo "                              - Build APK and publish GitHub release"
	@echo "  make release-apk-dry-run TAG=v1.1.13"
	@echo "                              - Print release commands without publishing"
	@echo "  make clean                  - Clean build artifacts"

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

build-apk: verify-android-keystore
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build apk --release $(DART_DEFINES)

build-aab: verify-android-keystore
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build appbundle --release $(DART_DEFINES)
	@echo "AAB built: $(AAB_SRC)"

release-apk-dry-run:
	@if [ -z "$(TAG)" ]; then echo "TAG is required. Example: make release-apk TAG=v1.1.13"; exit 1; fi
	@case "$(TAG)" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "TAG must look like v1.1.13. Got: $(TAG)"; exit 1;; esac
	@echo "Version:         $(APP_VERSION)"
	@echo "Repo:            $(GITHUB_REPO)"
	@echo "APK output:      $(APK_OUT)"
	@echo "AAB output:      $(AAB_OUT)"
	@echo "Build APK:       flutter build apk --release $(DART_DEFINES)"
	@echo "Build AAB:       flutter build appbundle --release $(DART_DEFINES)"
	@echo "Git tag:         git tag $(TAG) && git push origin $(TAG)"
	@echo "GH release:      gh release create $(TAG) \"$(APK_OUT)\" \"$(AAB_OUT)\" \"$(SHA_OUT)\" --repo $(GITHUB_REPO) --title \"JujoStream $(TAG)\" --notes \"$(RELEASE_NOTES)\""

$(RELEASE_DIR):
	powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path '$(RELEASE_DIR)' | Out-Null"

$(APK_OUT): $(RELEASE_DIR) verify-android-keystore
	flutter clean
	flutter pub get
	$(PATCH_BUILT_IN_KOTLIN)
	flutter build apk --release $(DART_DEFINES)
	flutter build appbundle --release $(DART_DEFINES)
	powershell -NoProfile -Command "Copy-Item -LiteralPath '$(APK_SRC)' -Destination '$(APK_OUT)' -Force"
	powershell -NoProfile -Command "Copy-Item -LiteralPath '$(AAB_SRC)' -Destination '$(AAB_OUT)' -Force"

$(SHA_OUT): $(APK_OUT)
	powershell -NoProfile -Command "Set-Content -LiteralPath '$(SHA_OUT)' -Value @(((Get-FileHash -Algorithm SHA256 -LiteralPath '$(APK_OUT)').Hash.ToLowerInvariant() + '  $(APK_NAME)'), ((Get-FileHash -Algorithm SHA256 -LiteralPath '$(AAB_OUT)').Hash.ToLowerInvariant() + '  $(AAB_NAME)')) -Encoding ascii"

release-apk: $(SHA_OUT)
	@if [ -z "$(TAG)" ]; then echo "TAG is required. Example: make release-apk TAG=v1.1.13"; exit 1; fi
	@case "$(TAG)" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "TAG must look like v1.1.13. Got: $(TAG)"; exit 1;; esac
	git tag $(TAG)
	git push origin $(TAG)
	if gh release view $(TAG) --repo $(GITHUB_REPO) >/dev/null 2>&1; then \
		gh release upload $(TAG) "$(APK_OUT)" "$(AAB_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --clobber; \
	else \
		gh release create $(TAG) "$(APK_OUT)" "$(AAB_OUT)" "$(SHA_OUT)" --repo $(GITHUB_REPO) --title "JujoStream $(TAG)" --notes "$(RELEASE_NOTES)"; \
	fi

clean:
	flutter clean
	powershell -NoProfile -Command "if (Test-Path 'dist') { Remove-Item -Recurse -Force 'dist' }"
