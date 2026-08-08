# ROZZA iOS builds on GitHub

The simulator workflow builds and tests every push to `main`, then publishes `ROZZA-Simulator.app.zip`. That artifact only runs in an iOS Simulator.

The unsigned workflow builds for real iPhone hardware and publishes `ROZZA-Unsigned.ipa`. It contains no certificate or provisioning profile. It must be re-signed by an authorized sideloading/signing service before iOS will install it.

The signed workflow creates `ROZZA-iPhone-Signed.ipa` for a physical iPhone. Apple requires a matching certificate and provisioning profile; GitHub Actions cannot bypass that platform requirement.

## Required GitHub Actions secrets

- `IOS_P12_BASE64`: base64-encoded Apple signing certificate (`.p12`)
- `IOS_P12_PASSWORD`: password used to export that certificate
- `IOS_PROFILE_BASE64`: base64-encoded matching `.mobileprovision`
- `IOS_KEYCHAIN_PASSWORD`: random password used only for the temporary CI keychain
- `IOS_TEAM_ID`: Apple Developer Team ID
- `IOS_BUNDLE_ID`: bundle identifier contained in the provisioning profile

No signing material or provider credentials belong in Git. The bundled `rozza2.html` interface does not use a localhost backend. Optional backend credentials are deployed as server environment variables listed in `backend/.env.example`.

Without Apple Developer signing assets, use the simulator artifact or download the unsigned IPA for re-signing. An unsigned IPA cannot be installed directly on stock iOS.
