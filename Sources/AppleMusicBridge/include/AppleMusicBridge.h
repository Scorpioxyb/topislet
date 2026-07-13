#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
TopIsletAppleMusicCopySnapshot(
    pid_t processIdentifier,
    BOOL includeArtwork,
    NSError **error
)
NS_SWIFT_NOTHROW;

FOUNDATION_EXPORT BOOL TopIsletAppleMusicPerformAction(
    pid_t processIdentifier,
    NSString *action,
    NSString * _Nullable expectedPersistentIdentifier,
    NSString * _Nullable expectedFallbackSignature,
    double normalizedProgress,
    NSError **error
) NS_SWIFT_NOTHROW;

NS_ASSUME_NONNULL_END
