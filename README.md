# iTools

An iOS 15+ app for discovering Apple-device apps, browsing community GitHub repositories, and following installation guides. App download links can point to GitHub release assets or shared Google Drive files.

## Build an unsigned IPA on GitHub

The **CI iTools** GitHub Actions workflow builds the simulator app and an unsigned iOS IPA when changes are pushed to `main`. To run it manually, open the repository's **Actions** tab, choose **CI iTools**, and select **Run workflow**. Open a successful run and download the `iTools-unsigned-ipa` artifact.

The IPA is unsigned. Sign it with an authorized signing method before installing it on a device. The GitHub Actions artifact is temporary and may require signing in to GitHub to download.

## GitHub connection and assets

First launch offers optional GitHub and appearance setup, which can be skipped. GitHub repository creation and catalogue updates require the user's own Personal Access Token, which the app stores in Keychain. To publish, select the target repository and grant the token `Contents: Read and write`; iTools checks actual repository write access before editing. Listings take a public HTTPS download URL, with the IPA hosted on a GitHub release or shared Google Drive file. Public repositories without an iTools app catalogue are also checked for IPA assets in GitHub Releases. Each repository is limited to 1,000 apps. Husk is included in iTools Official. Drive folder links are not supported. Do not embed a token or shared password in the app. Source submissions open an issue in this repository for review.

Add `SideStore.png`, `AltStore.png`, `LiveContainer.png`, and `Nyxian.png` to the asset catalog. Add `Nyxian.ipa` to Copy Bundle Resources if the bundled Nyxian download is desired. These files are not included in this repository.

## Local build

On macOS with Xcode and XcodeGen installed, run:

```sh
xcodegen generate
xcodebuild -project iTools.xcodeproj -scheme iTools -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
