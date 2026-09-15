require 'yaml'

# The 9.6.1 pub package's CocoaPod version is 0.0.1. Export the actual
# installed package version, not the unrelated framework marketing version.
def write_downloader_compatibility_version(plugin_root)
  version = YAML.load_file(File.join(plugin_root, 'pubspec.yaml')).fetch('version').to_s
  raise 'Invalid background_downloader package version' unless version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[-+][a-zA-Z0-9.-]+)?\z/)

  path = File.join(plugin_root, 'ios/background_downloader/Sources/background_downloader/AnimeWitcherCompatibility.swift')
  File.write(path, "// Generated from installed pubspec.yaml by AnimeWitcher.\npublic let animeWitcherBackgroundDownloaderVersion = \"#{version}\"\n")
end
