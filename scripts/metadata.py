import plistlib
import sys
from pathlib import Path

contents = Path(sys.argv[1])
minimum = sys.argv[2]
name = "7zip"
identifier = "com.finderarchiver.mac"
common = {
    "CFBundleName": name,
    "CFBundleSupportedPlatforms": ["MacOSX"],
    "CFBundleShortVersionString": "0.1.1",
    "CFBundleVersion": "2",
    "LSMinimumSystemVersion": minimum,
}

app = {
    **common,
    "CFBundleIdentifier": identifier,
    "CFBundlePackageType": "APPL",
    "CFBundleExecutable": "FinderArchiver",
    "CFBundleURLTypes": [
        {"CFBundleURLName": identifier, "CFBundleURLSchemes": ["finderarchiver-dispatch"]}
    ],
    "LSApplicationCategoryType": "public.app-category.utilities",
    "NSHighResolutionCapable": True,
}
extension = {
    **common,
    "CFBundleDisplayName": name,
    "CFBundleIdentifier": identifier + ".finder",
    "CFBundlePackageType": "XPC!",
    "CFBundleExecutable": "FinderExtension",
    "NSExtension": {
        "NSExtensionPointIdentifier": "com.apple.FinderSync",
        "NSExtensionPrincipalClass": "FinderExtension",
    },
}

for folder, metadata in [(contents, app), (contents / "PlugIns/FinderExtension.appex/Contents", extension)]:
    with (folder / "Info.plist").open("wb") as file:
        plistlib.dump(metadata, file)
