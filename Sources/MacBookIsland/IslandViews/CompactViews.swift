import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct CompactMusic: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AlbumArt(track: model.music.track, size: 25)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.music.track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white)
                    Text(model.music.track.artist)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactLeadingWingWidth, height: model.topBandHeight, alignment: .leading)

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)

            HStack(spacing: 9) {
                ProgressPill(
                    progress: model.music.progress,
                    width: 54,
                    accentColor: model.musicAccentColor
                )

                StatusDot(
                    isActive: model.statusWaveIsActive,
                    accentColor: model.statusWaveColor
                )
                .frame(width: 10, height: 10)
            }
            .padding(.trailing, 10)
            .frame(width: model.compactTrailingWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.music.track.title)，\(model.music.track.artist)")
        .onTapGesture {
            model.requestIslandMode(.expanded)
        }
    }
}

struct CompactTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(timeText(model.timerState.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    ProgressPill(progress: model.timerState.progress, width: 96)
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", size: 27) {
                    model.toggleTimer()
                }
                .help(model.timerState.isRunning ? "暂停计时" : "开始计时")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}

struct CompactNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Circle().fill(Color.white.opacity(0.1)))

                    if model.notification.count > 1 {
                        Text("\(model.notification.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(Color.white))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.notification.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: "xmark", size: 27) {
                    model.dismissNotification()
                }
                .help("关闭提醒")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}
