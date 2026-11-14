import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct ExpandedActivityCenter: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("专注计时", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 12)
                Button {
                    model.requestIslandMode(.collapsed, bypassCooldown: true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("收起快捷面板")
                .accessibilityLabel("收起快捷面板")
            }
            .frame(height: 28)

            HStack(spacing: 12) {
                ForEach(FocusTimerPreset.allCases) { preset in
                    Button {
                        model.startTimer(minutes: preset.rawValue)
                    } label: {
                        Text("\(preset.rawValue) 分")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 52, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.09))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("开始 \(preset.title)专注计时")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)

            if model.shouldPresentMusicControlRecovery {
                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isRecoveringMusicControl ? "正在连接播放控制" : "音乐控制暂不可用")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                        Text(model.isRecoveringMusicControl
                            ? "正在重新打开汽水音乐"
                            : (model.musicControlRecoveryNeedsUserAction
                                ? "连接未完成，可再次尝试"
                                : "不会自动打开汽水音乐"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer(minLength: 8)

                    Button {
                        model.recoverCurrentMusicControl()
                    } label: {
                        HStack(spacing: 5) {
                            if model.isRecoveringMusicControl {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(model.isRecoveringMusicControl ? "连接中" : "重启并连接")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecoveringMusicControl)
                    .help(model.isRecoveringMusicControl ? "正在连接汽水音乐播放控制" : "点击会重启一次汽水音乐并连接播放控制；不会自动打开汽水音乐")
                    .accessibilityLabel(model.isRecoveringMusicControl ? "正在连接汽水音乐播放控制" : "重启并连接汽水音乐播放控制")
                }
                .frame(height: 38)
            }

            Divider().overlay(Color.white.opacity(0.08))

            ActivityPermissionRow(
                model: model,
                title: "日历",
                icon: "calendar",
                entityType: .event
            )

            Divider().overlay(Color.white.opacity(0.08))

            ActivityPermissionRow(
                model: model,
                title: "提醒事项",
                icon: "checklist",
                entityType: .reminder
            )
        }
    }
}

private struct ActivityPermissionRow: View {
    @ObservedObject var model: IslandModel
    let title: String
    let icon: String
    let entityType: EKEntityType
    @State private var isRequesting = false

    private var access: EventKitAccessState {
        entityType == .event
            ? model.eventKitStatus.calendarAccess
            : model.eventKitStatus.remindersAccess
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: {
                entityType == .event
                    ? model.appSettings.calendarEventsEnabled
                    : model.appSettings.remindersEnabled
            },
            set: { enabled in
                if entityType == .event {
                    model.appSettings.calendarEventsEnabled = enabled
                } else {
                    model.appSettings.remindersEnabled = enabled
                }
            }
        )
    }

    private var statusText: String {
        guard access.canRead else { return access.displayName }
        return isEnabled.wrappedValue ? "已开启" : "已关闭"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))

            Spacer(minLength: 10)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            if access.canRead {
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(isEnabled.wrappedValue ? "关闭\(title)活动" : "开启\(title)活动")
            } else {
                Button {
                    if access == .notDetermined {
                        isRequesting = true
                        Task {
                            if entityType == .event {
                                await model.requestCalendarAccess()
                            } else {
                                await model.requestRemindersAccess()
                            }
                            isRequesting = false
                        }
                    } else {
                        model.openEventKitPrivacySettings(for: entityType)
                    }
                } label: {
                    Image(systemName: access == .notDetermined ? "arrow.right.circle.fill" : "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .help(access == .notDetermined ? "请求\(title)访问" : "打开\(title)隐私设置")
            }
        }
        .frame(height: 38)
    }
}
