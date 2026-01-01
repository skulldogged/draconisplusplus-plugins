/**
 * @file now_playing_macos.mm
 * @brief macOS-specific implementation for Now Playing plugin
 *
 * This file contains the Objective-C++ code for fetching now playing
 * information via the macOS MediaRemote private framework.
 *
 * On macOS 15.4+, Apple restricted MediaRemote access to only Apple-signed
 * binaries. We fall back to the `media-control` CLI tool if installed.
 */

#ifdef __APPLE__

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#include <array>
#include <cstdio>
#include <memory>

#include <glaze/glaze.hpp>

#include <Drac++/Utils/Error.hpp>

#include "now_playing_types.hpp"

using namespace draconis::utils::types;
using namespace draconis::utils::error;
using enum DracErrorCode;

namespace now_playing::macos {
  // Forward-declare the function pointer type for the private MediaRemote API.
  using MRMediaRemoteGetNowPlayingInfoFn =
    void (*)(dispatch_queue_t queue, void (^handler)(NSDictionary* information));

  // JSON structure for media-control output (must be outside anonymous namespace for glaze)
  struct MediaControlOutput {
    String title;
    String artist;
    String album;
    bool   playing = false;
  };

  namespace {

    /**
     * @brief Check if media-control CLI is available
     */
    auto isMediaControlAvailable() -> bool {
      // Check common installation paths
      static const std::array<const char*, 3> paths = {
        "/opt/homebrew/bin/media-control", // ARM Homebrew
        "/usr/local/bin/media-control",    // Intel Homebrew
        "/usr/bin/media-control"           // System-wide
      };

      for (const auto* path : paths) {
        if (access(path, X_OK) == 0)
          return true;
      }

      return false;
    }

    /**
     * @brief Get the path to media-control CLI
     */
    auto getMediaControlPath() -> Option<String> {
      static const std::array<const char*, 3> paths = {
        "/opt/homebrew/bin/media-control",
        "/usr/local/bin/media-control",
        "/usr/bin/media-control"
      };

      for (const auto* path : paths) {
        if (access(path, X_OK) == 0)
          return String(path);
      }

      return None;
    }

    /**
     * @brief Fetch now playing info using media-control CLI
     * @note This is slower due to process spawning but works on macOS 15.4+
     */
    auto fetchViaMediaControl() -> Result<MediaData> {
      auto pathOpt = getMediaControlPath();

      if (!pathOpt)
        ERR(ApiUnavailable, "media-control CLI not found. Install via: brew install media-control");

      String command = *pathOpt + " get 2>/dev/null";

      std::array<char, 4096> buffer {};
      String                 output;

      std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(command.c_str(), "r"), pclose);

      if (!pipe)
        ERR(IoError, "Failed to execute media-control");

      while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe.get()) != nullptr)
        output += buffer.data();

      // Check for null output (no media playing)
      if (output.empty() || output == "null\n" || output == "null")
        ERR(NotFound, "No media is currently playing");

      // Parse JSON output (skip unknown keys since media-control outputs many fields)
      MediaControlOutput parsed;

      if (auto err = glz::read<glz::opts{ .error_on_unknown_keys = false }>(parsed, output); err)
        ERR(ParseError, "Failed to parse media-control output");

      // Check if we got valid data (title is required)
      if (parsed.title.empty())
        ERR(NotFound, "No media is currently playing");

      MediaData data;
      data.title = parsed.title;

      if (!parsed.artist.empty())
        data.artist = parsed.artist;

      if (!parsed.album.empty())
        data.album = parsed.album;

      return data;
    }

    /**
     * @brief Fetch now playing info using native MediaRemote API
     * @note Only works on macOS < 15.4
     */
    auto fetchViaNativeApi() -> Result<MediaData> {
      // Since MediaRemote.framework is private, we cannot link against it directly.
      // Instead, it must be loaded at runtime using CFURL and CFBundle.
      CFURLRef urlRef = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault,
        CFSTR("/System/Library/PrivateFrameworks/MediaRemote.framework"),
        kCFURLPOSIXPathStyle,
        false
      );

      if (!urlRef)
        ERR(NotFound, "Failed to create CFURL for MediaRemote.framework");

      // Create a bundle from the URL
      CFBundleRef bundleRef = CFBundleCreate(kCFAllocatorDefault, urlRef);
      CFRelease(urlRef);

      if (!bundleRef)
        ERR(ApiUnavailable, "Failed to create bundle for MediaRemote.framework");

      // Get a pointer to the MRMediaRemoteGetNowPlayingInfo function from the bundle.
      auto mrMediaRemoteGetNowPlayingInfo = std::bit_cast<MRMediaRemoteGetNowPlayingInfoFn>(
        CFBundleGetFunctionPointerForName(bundleRef, CFSTR("MRMediaRemoteGetNowPlayingInfo"))
      );

      if (!mrMediaRemoteGetNowPlayingInfo) {
        CFRelease(bundleRef);
        ERR(ApiUnavailable, "Failed to get MRMediaRemoteGetNowPlayingInfo function pointer");
      }

      // A semaphore is used to make this asynchronous call behave synchronously.
      __block Result<MediaData>  result;
      const dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

      mrMediaRemoteGetNowPlayingInfo(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^(NSDictionary* information) {
          if (!information) {
            result = Err(DracError(NotFound, "No media is currently playing"));
          } else {
            MediaData data;

            // Extract the title, artist, and album from the dictionary
            const NSString* const titleNS  = [information objectForKey:@"kMRMediaRemoteNowPlayingInfoTitle"];
            const NSString* const artistNS = [information objectForKey:@"kMRMediaRemoteNowPlayingInfoArtist"];
            const NSString* const albumNS  = [information objectForKey:@"kMRMediaRemoteNowPlayingInfoAlbum"];

            if (titleNS)
              data.title = String([titleNS UTF8String]);

            if (artistNS)
              data.artist = String([artistNS UTF8String]);

            if (albumNS)
              data.album = String([albumNS UTF8String]);

            // If we got no title, consider it as no media playing
            if (!data.title) {
              result = Err(DracError(NotFound, "No media is currently playing"));
            } else {
              result = data;
            }
          }

          dispatch_semaphore_signal(semaphore);
        }
      );

      // Block until the callback signals completion
      dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

      // Note: We intentionally don't release bundleRef here.
      // CFBundleCreate may return a cached bundle, and releasing it
      // could cause issues. The bundle will be cleaned up when the
      // process exits.

      return result;
    }

    /**
     * @brief Check if running on macOS 15.4 or later (where MediaRemote is restricted)
     */
    auto isMediaRemoteRestricted() -> bool {
      static const bool restricted = []() {
        // Get the operating system version
        NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];

        // macOS 15.4+ restricts MediaRemote to Apple-signed binaries
        if (version.majorVersion > 15)
          return true;

        if (version.majorVersion == 15 && version.minorVersion >= 4)
          return true;

        return false;
      }();

      return restricted;
    }
  } // namespace

  auto fetchNowPlaying() -> Result<MediaData> {
    @autoreleasepool {
      // On macOS 15.4+, MediaRemote is restricted to Apple-signed binaries.
      // Use media-control CLI if available, otherwise fall back to native API
      // (which will likely fail but gives a proper error message).
      if (isMediaRemoteRestricted()) {
        if (isMediaControlAvailable())
          return fetchViaMediaControl();

        // media-control not installed, return helpful error
        ERR(
          ApiUnavailable,
          "Now Playing requires 'media-control' on macOS 15.4+. Install via: brew install media-control"
        );
      }

      // On older macOS, use the native MediaRemote API (fast)
      return fetchViaNativeApi();
    }
  }
} // namespace now_playing::macos

#endif // __APPLE__
