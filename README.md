# iTools

An iOS 15+ app for exploring tools and community repositories, sharing IPA files with a compatible sideloading app, and checking basic IPA indicators. The app icon is in `App/Assets.xcassets`.

## Build an unsigned IPA on GitHub

The **CI iTools** GitHub Actions workflow builds the simulator app and an unsigned iOS IPA when changes are pushed to `main`. To run it manually, open the repository's **Actions** tab, choose **CI iTools**, and select **Run workflow**. Open a successful run and download the `iTools-unsigned-ipa` artifact. The app's Home and Settings screens also link to this workflow.

The IPA is unsigned. Sign it with an authorized signing method before installing it on a device. The GitHub Actions artifact is temporary and may require signing in to GitHub to download.

## GitHub connection and assets

Local iTools accounts are stored on the device and do not sync. GitHub repository creation and uploads require the user's own Personal Access Token, which the app stores in Keychain. Do not embed a token or shared password in the app.

Add `SideStore.png`, `AltStore.png`, `LiveContainer.png`, and `Nyxian.png` to the asset catalog. Add `Nyxian.ipa` to Copy Bundle Resources if the bundled Nyxian download is desired. These files are not included in this repository.

## Local build

On macOS with Xcode and XcodeGen installed, run:

```sh
xcodegen generate
xcodebuild -project iTools.xcodeproj -scheme iTools -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
