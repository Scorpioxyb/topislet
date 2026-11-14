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
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.timerState.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timeText(model.timerState.remaining))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.timerState.isRunning ? "专注计时中" : "计时器已暂停")
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.white.opacity(0.1)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.notification.source)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(model.notification.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.62))
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
