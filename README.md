# iTools

An iOS app library for discovering apps, checking GitHub releases, and inspecting IPA metadata.
The deployment target is iOS 16.0.

## Download an unsigned IPA

The **Build iTools** GitHub Actions workflow builds the app on macOS whenever code is pushed to `main`.
To start a build manually, open the repository's **Actions** tab, choose **Build iTools**, and select **Run workflow**. When the run completes, download the `iTools-unsigned-ipa` artifact.

The IPA is unsigned and cannot be installed directly on a standard iPhone. It must be signed with a valid Apple provisioning profile before installation.

## Local build

On macOS with Xcode and XcodeGen installed, run:

```sh
xcodegen generate
xcodebuild -project iTools.xcodeproj -scheme iTools -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
