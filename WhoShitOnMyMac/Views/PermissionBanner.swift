import SwiftUI

struct PermissionBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            Text("需要完全磁盘访问才能扫全 Library，否则对比会不完整。")
                .font(.callout)
            Spacer()
            Button("打开系统设置") {
                state.permission.openFullDiskAccessSettings()
            }
            Button("重新检测") {
                state.refreshPermissions()
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.25))
    }
}

struct PermissionOnboarding: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("授权说明").font(.title2)
            Text("不授予「完全磁盘访问」时，~/Library 与容器会扫不全，两次快照对比会骗人。卸载其他应用还需要「应用管理」权限。系统不会弹窗，只能在系统设置里勾选本应用。")
            HStack {
                Button("打开完全磁盘访问") {
                    state.permission.openFullDiskAccessSettings()
                }
                Button("打开应用管理") {
                    state.permission.openAppManagementSettings()
                }
                Spacer()
                Button("稍后") {
                    UserDefaults.standard.set(true, forKey: "hasSeenPermissionOnboarding")
                    state.showOnboarding = false
                    state.refreshPermissions()
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
