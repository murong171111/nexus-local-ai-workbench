import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @EnvironmentObject private var appState: AppState

    private var summary: MenuBarStatusSummary {
        appState.menuBarSummary
    }

    var body: some View {
        Text("Nexus")
            .font(.headline)
        Text(summary.statusLine)
        if let activeStageLine = summary.activeStageLine {
            Text(activeStageLine)
        }
        Text(summary.bridgeMode)

        Divider()

        Button {
            activateApp()
        } label: {
            Label("打开 Nexus / Open Nexus", systemImage: "macwindow")
        }

        Button {
            Task {
                await appState.refreshFromBridge()
            }
        } label: {
            Label(
                appState.isLoading ? "正在刷新 / Refreshing" : "刷新状态 / Refresh",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(appState.isLoading)

        Button {
            Task {
                await appState.runLocalAutomationCheck()
            }
        } label: {
            Label(
                appState.isRunningAutomationCheck ? "检查中 / Checking" : "运行自动化检查 / Run Checks",
                systemImage: "checklist.checked"
            )
        }
        .disabled(appState.isRunningAutomationCheck)

        Button {
            appState.setAutomationScheduleEnabled(!appState.isAutomationScheduleEnabled)
        } label: {
            Label(
                appState.isAutomationScheduleEnabled ? "暂停定期检查 / Pause Schedule" : "启用定期检查 / Enable Schedule",
                systemImage: appState.isAutomationScheduleEnabled ? "pause.circle" : "timer"
            )
        }

        Button {
            Task {
                await appState.setAutomationNotificationsEnabled(!appState.areAutomationNotificationsEnabled)
            }
        } label: {
            Label(
                appState.areAutomationNotificationsEnabled ? "关闭检查通知 / Disable Alerts" : "开启检查通知 / Enable Alerts",
                systemImage: appState.areAutomationNotificationsEnabled ? "bell.slash" : "bell.badge"
            )
        }

        Button {
            copyToPasteboard(summary.clipboardText)
        } label: {
            Label("复制状态摘要 / Copy Summary", systemImage: "doc.on.doc")
        }

        Button {
            openSettings()
        } label: {
            Label("设置 / Settings", systemImage: "gearshape")
        }

        Divider()

        Section("工作台 / Workbench") {
            Text("工作区 \(summary.workspaceCount) · 进行中 \(summary.activeWorkspaceCount)")
            Text("归档 \(summary.archivedWorkspaceCount) · 活跃统计已排除")
            Text("风险 \(summary.riskyWorkspaceCount) · 阻塞 \(summary.blockedWorkspaceCount)")
            Text("任务 \(summary.openTaskCount) · 高优先 \(summary.highPriorityTaskCount)")
            Text("Agent \(summary.agentTaskCount) · 缺失 worktree \(summary.missingWorktreeCount)")
            Text("未提交服务 \(summary.dirtyServiceCount)")
        }

        if let automation = appState.lastAutomationCheck {
            Divider()

            Section("自动化 / Automation") {
                Text(automation.summary)
                Text("状态 \(automation.status) · \(automation.generatedAt)")
                ForEach(automation.signals.prefix(4)) { signal in
                    Text("\(signal.title): \(signal.count)")
                }
            }
        }

        Section("调度 / Schedule") {
            Text(appState.isAutomationScheduleEnabled ? "已启用 · \(appState.automationIntervalMinutes) min" : "未启用")
            Text("最近运行: \(appState.lastAutomationRunAt ?? "None")")
            Text("通知: \(appState.areAutomationNotificationsEnabled ? appState.automationNotificationStatus : "Disabled")")
            Text("提醒级别: \(appState.automationNotificationMinimumStatus.label) · \(appState.automationNotificationCooldownMinutes) min")
            Text("最近提醒: \(appState.lastAutomationNotificationAt ?? "None")")
        }

        if !appState.workspaces.isEmpty {
            Divider()

            Section("最近工作区 / Recent") {
                ForEach(appState.workspaces.prefix(5)) { workspace in
                    Button {
                        appState.select(workspace)
                        activateApp()
                    } label: {
                        Text(workspace.name)
                    }
                }
            }
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("退出 Nexus / Quit", systemImage: "power")
        }
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        activateApp()
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func copyToPasteboard(_ payload: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }
}
