# Storefront

A small SwiftUI app with Today and Search tabs.

## Download an unsigned IPA

The GitHub Actions workflow builds the app on macOS whenever code is pushed to `main`.
To start a build manually, open the repository's **Actions** tab, choose **Build unsigned iOS IPA**, and select **Run workflow**. When the run completes, download the `Storefront-unsigned-ipa` artifact.

The IPA is unsigned and cannot be installed directly on a standard iPhone. It must be signed with a valid Apple provisioning profile before installation.

## Local build

On macOS with Xcode and XcodeGen installed, run:

```sh
xcodegen generate
xcodebuild -project Storefront.xcodeproj -scheme Storefront -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
