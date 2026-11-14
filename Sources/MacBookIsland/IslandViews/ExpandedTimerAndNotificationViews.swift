import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct ExpandedTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(IslandTheme.Fill.timerRingTrack), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.timerState.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timeText(model.timerState.remaining))
                    .font(IslandTheme.Typeface.timerDisplay)
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.timerState.isRunning ? "专注计时中" : "计时器已暂停")
                    .font(IslandTheme.Typeface.timerStatus)
                    .foregroundStyle(.white)
                ProgressPill(progress: model.timerState.progress, width: 232)
                HStack(spacing: 10) {
                    ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", prominent: true) {
                        model.toggleTimer()
                    }
                    .help(model.timerState.isRunning ? "暂停" : "开始")

                    ControlButton(icon: "arrow.counterclockwise") {
                        model.resetTimer()
                    }
                    .help("重置")

                    ControlButton(icon: "plus") {
                        model.addMinute()
                    }
                    .help("加 1 分钟")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 232, alignment: .leading)

        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ExpandedNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(IslandTheme.Typeface.notificationIcon)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: IslandTheme.Radius.notificationIcon, style: .continuous).fill(Color.white.opacity(IslandTheme.Fill.button)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.notification.source)
                        .font(IslandTheme.Typeface.notificationSource)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.notificationSource))
                    Text(model.notification.title)
                        .font(IslandTheme.Typeface.notificationTitle)
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(IslandTheme.Typeface.notificationBody)
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.notificationBody))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if model.canOpenActiveEventSource {
                    TextButton(title: "打开", systemName: "arrow.up.forward.app") {
                        model.openActiveEventSource()
                    }
                }
                TextButton(title: "关闭", systemName: "xmark") {
                    model.dismissNotification()
                }
                Spacer()
            }
        }
    }
}
