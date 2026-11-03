# iTools

An iOS 16+ app for exploring tools and community repositories, sharing IPA files with a compatible sideloading app, and checking basic IPA indicators. The app icon is in `App/Assets.xcassets`.

## Build an unsigned IPA on GitHub

The **Build iTools** GitHub Actions workflow runs when changes are pushed to `main`. To run it manually, open the repository's **Actions** tab, choose **Build iTools**, and select **Run workflow**. Download the `iTools-unsigned-ipa` artifact when the build completes.

The IPA is unsigned. Sign it with an authorized signing method before installing it on a device.

## Configure Supabase

The account and community repository features require a Supabase project. Set `supabaseURL` and the public anon key in `ITConfig` in `App/iTools.swift`, then run the setup SQL at the bottom of that file in the Supabase SQL Editor. Do not put a service-role key or account password in the app.

The built-in Nyxian and LiveContainer + SideStore entries also expect `Nyxian.ipa` and `LiveContainer+SideStore.ipa` to be added to the app target's Copy Bundle Resources. Those IPA files are not included in this repository.

## Local build

On macOS with Xcode and XcodeGen installed, run:

```sh
xcodegen generate
xcodebuild -project iTools.xcodeproj -scheme iTools -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
