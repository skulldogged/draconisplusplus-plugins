/**
 * @file now_playing_macos.mm
 * @brief macOS-specific implementation for Now Playing plugin
 *
 * This file contains the Objective-C++ code for fetching now playing
 * information via the macOS MediaRemote private framework.
 *
 * Note: On macOS 15.4+, Apple restricted MediaRemote access to binaries
 * with a com.apple.* signing identifier. The build system handles this
 * by codesigning the binary with a spoofed identifier at install time.
 */

#ifdef __APPLE__

  #import <Foundation/Foundation.h>
  #include <condition_variable>
  #import <dispatch/dispatch.h>
  #include <memory>
  #include <mutex>

  #include <Drac++/Utils/Error.hpp>

  #include "now_playing_types.hpp"

using namespace draconis::utils::types;
using namespace draconis::utils::error;
using enum DracErrorCode;

namespace now_playing::macos {
  // Forward-declare the function pointer type for the private MediaRemote API.
  using MRMediaRemoteGetNowPlayingInfoFn =
    void (*)(dispatch_queue_t queue, void (^handler)(NSDictionary* information));

  namespace {
    /**
     * @brief Fetch now playing info using native MediaRemote API
     */
    auto fetchViaNativeApi() -> Result<MediaData> {
      // Since MediaRemote.framework is private, we cannot link against it directly.
      // Instead, it must be loaded at runtime using CFURL and CFBundle.
      static const auto bundle = [] {
        CFURLRef urlRef = CFURLCreateWithFileSystemPath(
          kCFAllocatorDefault,
          CFSTR("/System/Library/PrivateFrameworks/MediaRemote.framework"),
          kCFURLPOSIXPathStyle,
          false
        );

        if (!urlRef)
          return std::unique_ptr<const void, decltype(&CFRelease)>(nullptr, &CFRelease);

        // Create a bundle from the URL
        CFBundleRef bundleRef = CFBundleCreate(kCFAllocatorDefault, urlRef);
        CFRelease(urlRef);
        return std::unique_ptr<const void, decltype(&CFRelease)>(bundleRef, &CFRelease);
      }();

      if (!bundle)
        ERR(ApiUnavailable, "Failed to create bundle for MediaRemote.framework");

      // Get a pointer to the MRMediaRemoteGetNowPlayingInfo function from the bundle.
      auto mrMediaRemoteGetNowPlayingInfo = std::bit_cast<MRMediaRemoteGetNowPlayingInfoFn>(
        CFBundleGetFunctionPointerForName(static_cast<CFBundleRef>(bundle.get()), CFSTR("MRMediaRemoteGetNowPlayingInfo"))
      );

      if (!mrMediaRemoteGetNowPlayingInfo) {
        ERR(ApiUnavailable, "Failed to get MRMediaRemoteGetNowPlayingInfo function pointer");
      }

      // The copied block retains this state even if its callback arrives after
      // our deadline. No callback writes into expired stack storage.
      struct RequestState {
        std::mutex                mutex;
        std::condition_variable   completed;
        Option<Result<MediaData>> result;
      };
      const auto state = std::make_shared<RequestState>();

      mrMediaRemoteGetNowPlayingInfo(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^(NSDictionary* information) {
          Result<MediaData> result;
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

          {
            const std::lock_guard lock(state->mutex);
            state->result = std::move(result);
          }
          state->completed.notify_one();
        }
      );

      std::unique_lock lock(state->mutex);
      if (!state->completed.wait_for(lock, std::chrono::seconds(3), [&] { return state->result.has_value(); }))
        ERR(Timeout, "MediaRemote request timed out");
      return std::move(*state->result);
    }
  } // namespace

  auto fetchNowPlaying() -> Result<MediaData> {
    @autoreleasepool {
      return fetchViaNativeApi();
    }
  }
} // namespace now_playing::macos

#endif // __APPLE__
