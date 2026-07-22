#import "AppleMusicBridge.h"

@import AppKit;
@import ImageIO;
@import ScriptingBridge;

static NSString * const TopIsletAppleMusicErrorDomain = @"io.github.scorpioxyb.topislet.apple-music";

@interface TopIsletAppleMusicErrorDelegate : NSObject <SBApplicationDelegate>
@property(nonatomic, strong, nullable) NSError *lastError;
@end

@implementation TopIsletAppleMusicErrorDelegate

- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error {
    self.lastError = error;
    return nil;
}

@end

static NSError *TopIsletAppleMusicError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:TopIsletAppleMusicErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL TopIsletValidateTarget(pid_t processIdentifier, NSError **error) {
    NSRunningApplication *application = [NSRunningApplication
        runningApplicationWithProcessIdentifier:processIdentifier];
    BOOL valid = application != nil
        && !application.terminated
        && [application.bundleIdentifier isEqualToString:@"com.apple.Music"];
    if (!valid && error != NULL) {
        *error = TopIsletAppleMusicError(
            -600,
            @"绑定的 Apple Music 进程已退出或被替换。"
        );
    }
    return valid;
}

static SBApplication *TopIsletApplication(
    pid_t processIdentifier,
    TopIsletAppleMusicErrorDelegate **delegate,
    NSError **error
) {
    if (!TopIsletValidateTarget(processIdentifier, error)) {
        return nil;
    }
    SBApplication *application = [SBApplication
        applicationWithProcessIdentifier:processIdentifier];
    if (application == nil) {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(
                -600,
                @"无法连接绑定的 Apple Music 进程。"
            );
        }
        return nil;
    }
    TopIsletAppleMusicErrorDelegate *errorDelegate =
        [[TopIsletAppleMusicErrorDelegate alloc] init];
    application.delegate = errorDelegate;
    *delegate = errorDelegate;
    return application;
}

static SBApplication *TopIsletMetadataApplication(
    pid_t processIdentifier,
    TopIsletAppleMusicErrorDelegate **delegate,
    NSError **error
) {
    if (!TopIsletValidateTarget(processIdentifier, error)) {
        return nil;
    }
    // Music 1.6.5 can return the radio station placeholder when its Apple
    // Event address uses a kernel PID. Bundle addressing returns the actual
    // current track. The PID checks before and after the read still bind the
    // snapshot to the exact running Music instance.
    SBApplication *application = [SBApplication
        applicationWithBundleIdentifier:@"com.apple.Music"];
    if (application == nil || !application.running) {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(
                -600,
                @"无法连接已运行的 Apple Music 进程。"
            );
        }
        return nil;
    }
    TopIsletAppleMusicErrorDelegate *errorDelegate =
        [[TopIsletAppleMusicErrorDelegate alloc] init];
    application.delegate = errorDelegate;
    *delegate = errorDelegate;
    return application;
}

static id TopIsletPropertyValue(
    SBObject *object,
    AEKeyword propertyCode,
    TopIsletAppleMusicErrorDelegate *delegate,
    NSError **error
) {
    if (delegate.lastError != nil) {
        return nil;
    }
    id value = [[object propertyWithCode:propertyCode] get];
    if (delegate.lastError != nil && error != NULL) {
        *error = delegate.lastError;
    }
    return value;
}

static NSString *TopIsletString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return value == nil ? @"" : [value description];
}

static NSNumber *TopIsletNumber(id value) {
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static OSType TopIsletEnumCode(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value unsignedIntValue];
    }
    if ([value isKindOfClass:[NSAppleEventDescriptor class]]) {
        return [value enumCodeValue];
    }
    return 0;
}

static NSString *TopIsletPlaybackState(OSType stateCode) {
    switch (stateCode) {
        case 'kPSP':
        case 'kPSF':
        case 'kPSR':
            return @"playing";
        case 'kPSp':
            return @"paused";
        case 'kPSS':
            return @"stopped";
        default:
            return @"unknown";
    }
}

static NSData *TopIsletArtworkData(
    SBObject *track,
    TopIsletAppleMusicErrorDelegate *delegate
) {
    static const NSUInteger maximumArtworkBytes = 8 * 1024 * 1024;
    if (delegate.lastError != nil) {
        return nil;
    }
    SBElementArray *artworks = [track elementArrayWithCode:'cArt'];
    if (delegate.lastError != nil || artworks.count == 0) {
        delegate.lastError = nil;
        return nil;
    }

    SBObject *artwork = [artworks objectAtIndex:0];
    id rawValue = TopIsletPropertyValue(artwork, 'pRaw', delegate, NULL);
    if (delegate.lastError != nil) {
        delegate.lastError = nil;
        return nil;
    }
    NSData *data = nil;
    if ([rawValue isKindOfClass:[NSData class]]) {
        data = rawValue;
    } else if ([rawValue isKindOfClass:[NSAppleEventDescriptor class]]) {
        data = [(NSAppleEventDescriptor *)rawValue data];
    }
    if (data.length == 0 || data.length > maximumArtworkBytes) {
        return nil;
    }
    CGImageSourceRef imageSource = CGImageSourceCreateWithData(
        (__bridge CFDataRef)data,
        NULL
    );
    if (imageSource == NULL || CGImageSourceGetCount(imageSource) == 0) {
        if (imageSource != NULL) {
            CFRelease(imageSource);
        }
        return nil;
    }
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(
        imageSource,
        0,
        NULL
    );
    CFRelease(imageSource);
    if (properties == NULL) {
        return nil;
    }
    NSNumber *pixelWidth = (__bridge NSNumber *)CFDictionaryGetValue(
        properties,
        kCGImagePropertyPixelWidth
    );
    NSNumber *pixelHeight = (__bridge NSNumber *)CFDictionaryGetValue(
        properties,
        kCGImagePropertyPixelHeight
    );
    double width = pixelWidth.doubleValue;
    double height = pixelHeight.doubleValue;
    CFRelease(properties);
    if (!isfinite(width)
        || !isfinite(height)
        || width <= 0
        || height <= 0
        || width > 8192
        || height > 8192) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (image == nil) {
        return nil;
    }
    return data;
}

NSDictionary<NSString *, id> *TopIsletAppleMusicCopySnapshot(
    pid_t processIdentifier,
    BOOL includeArtwork,
    NSError **error
) {
    TopIsletAppleMusicErrorDelegate *delegate = nil;
    SBApplication *application = TopIsletMetadataApplication(
        processIdentifier,
        &delegate,
        error
    );
    if (application == nil) {
        return nil;
    }

    id stateValue = TopIsletPropertyValue(application, 'pPlS', delegate, error);
    if (delegate.lastError != nil) {
        return nil;
    }
    NSString *state = TopIsletPlaybackState(TopIsletEnumCode(stateValue));
    if ([state isEqualToString:@"stopped"]) {
        if (!TopIsletValidateTarget(processIdentifier, error)) {
            return nil;
        }
        return @{
            @"persistentIdentifier": @"",
            @"title": @"",
            @"artist": @"",
            @"album": @"",
            @"artworkData": [NSNull null],
            @"duration": [NSNull null],
            @"elapsedTime": [NSNull null],
            @"state": state
        };
    }

    SBObject *track = [application propertyWithCode:'pTrk'];
    NSString *firstIdentifier = TopIsletString(
        TopIsletPropertyValue(track, 'pPIS', delegate, error)
    );
    if (delegate.lastError != nil) {
        return nil;
    }
    NSString *title = TopIsletString(
        TopIsletPropertyValue(track, 'pnam', delegate, error)
    );
    NSString *artist = TopIsletString(
        TopIsletPropertyValue(track, 'pArt', delegate, error)
    );
    NSString *album = TopIsletString(
        TopIsletPropertyValue(track, 'pAlb', delegate, error)
    );
    NSNumber *duration = TopIsletNumber(
        TopIsletPropertyValue(track, 'pDur', delegate, error)
    );
    NSNumber *elapsedTime = TopIsletNumber(
        TopIsletPropertyValue(application, 'pPos', delegate, error)
    );
    if (delegate.lastError != nil) {
        return nil;
    }
    NSData *artworkData = includeArtwork
        ? TopIsletArtworkData(track, delegate)
        : nil;
    NSString *finalIdentifier = TopIsletString(
        TopIsletPropertyValue(track, 'pPIS', delegate, error)
    );
    if (delegate.lastError != nil) {
        return nil;
    }
    if (firstIdentifier.length == 0
        || ![firstIdentifier isEqualToString:finalIdentifier]) {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(
                409,
                @"Apple Music 在读取过程中切换了歌曲，已丢弃混合快照。"
            );
        }
        return nil;
    }
    if (!TopIsletValidateTarget(processIdentifier, error)) {
        return nil;
    }

    return @{
        @"persistentIdentifier": firstIdentifier,
        @"title": title,
        @"artist": artist,
        @"album": album,
        @"artworkData": artworkData ?: [NSNull null],
        @"duration": duration ?: [NSNull null],
        @"elapsedTime": elapsedTime ?: [NSNull null],
        @"state": state
    };
}

static NSString *TopIsletFallbackSignature(NSDictionary<NSString *, id> *snapshot) {
    return [NSString stringWithFormat:@"%@\x1f%@\x1f%@",
        TopIsletString(snapshot[@"title"]),
        TopIsletString(snapshot[@"artist"]),
        TopIsletString(snapshot[@"album"])];
}

BOOL TopIsletAppleMusicPerformAction(
    pid_t processIdentifier,
    NSString *action,
    NSString *expectedPersistentIdentifier,
    NSString *expectedFallbackSignature,
    double normalizedProgress,
    NSError **error
) {
    TopIsletAppleMusicErrorDelegate *delegate = nil;
    SBApplication *application = TopIsletApplication(
        processIdentifier,
        &delegate,
        error
    );
    if (application == nil) {
        return NO;
    }

    NSDictionary<NSString *, id> *snapshot = TopIsletAppleMusicCopySnapshot(
        processIdentifier,
        NO,
        error
    );
    if (snapshot == nil) {
        return NO;
    }
    NSString *currentIdentifier = TopIsletString(snapshot[@"persistentIdentifier"]);
    if (expectedPersistentIdentifier.length > 0
        && ![expectedPersistentIdentifier isEqualToString:currentIdentifier]) {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(409, @"Apple Music 当前歌曲已变化。");
        }
        return NO;
    }
    if (expectedPersistentIdentifier.length == 0
        && expectedFallbackSignature.length > 0
        && ![expectedFallbackSignature isEqualToString:TopIsletFallbackSignature(snapshot)]) {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(409, @"Apple Music 当前歌曲已变化。");
        }
        return NO;
    }

    delegate.lastError = nil;
    if ([action isEqualToString:@"playPause"]) {
        [application sendEvent:'hook' id:'PlPs' parameters:0];
    } else if ([action isEqualToString:@"play"]) {
        [application sendEvent:'hook' id:'Play' parameters:0];
    } else if ([action isEqualToString:@"pause"]) {
        [application sendEvent:'hook' id:'Paus' parameters:0];
    } else if ([action isEqualToString:@"previousTrack"]) {
        [application sendEvent:'hook' id:'Prev' parameters:0];
    } else if ([action isEqualToString:@"nextTrack"]) {
        [application sendEvent:'hook' id:'Next' parameters:0];
    } else if ([action isEqualToString:@"seekNormalized"]) {
        NSNumber *duration = TopIsletNumber(snapshot[@"duration"]);
        if (currentIdentifier.length == 0
            || expectedPersistentIdentifier.length == 0
            || duration.doubleValue <= 0
            || !isfinite(normalizedProgress)
            || normalizedProgress < 0
            || normalizedProgress > 1) {
            if (error != NULL) {
                *error = TopIsletAppleMusicError(
                    422,
                    @"Apple Music 当前快照不允许安全跳转进度。"
                );
            }
            return NO;
        }
        [[application propertyWithCode:'pPos']
            setTo:@(duration.doubleValue * normalizedProgress)];
    } else {
        if (error != NULL) {
            *error = TopIsletAppleMusicError(400, @"未知的 Apple Music 控制动作。");
        }
        return NO;
    }

    if (delegate.lastError != nil) {
        if (error != NULL) {
            *error = delegate.lastError;
        }
        return NO;
    }
    return TopIsletValidateTarget(processIdentifier, error);
}
