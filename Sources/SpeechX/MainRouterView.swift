import SwiftUI

enum AppRoute {
    case home
    case settings
}

struct MainRouterView: View {
    @ObservedObject var appState: AppState
    let updater: UpdaterManager
    @State private var currentRoute: AppRoute = .home

    var body: some View {
        Group {
            switch currentRoute {
            case .home:
                HomeView(appState: appState, currentRoute: $currentRoute)
            case .settings:
                SettingsPanelView(appState: appState, updater: updater, currentRoute: $currentRoute)
            }
        }
        .frame(minWidth: 1000, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
        .background(Color.vlWindowBg)
    }
}

struct HomeView: View {
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName()
        var options: [String] = []
        
        switch hour {
        case 5..<12:
            options = [
                "Morning, \(name). Ready when you are.",
                "Good morning — let's turn your thoughts into words.",
                "Morning. Let's get to it."
            ]
        case 12..<17:
            options = [
                "Back again, \(name)? Let's keep talking.",
                "Afternoon — say what's on your mind.",
                "Good afternoon. Ready to dictate?"
            ]
        case 17..<22:
            options = [
                "Evening, \(name). Still have things to say?",
                "Good evening. Let's get your words down.",
                "Evening. Keep the ideas flowing."
            ]
        default:
            options = [
                "Up late? Your voice is faster than your fingers right now.",
                "Late night, \(name)? Speak your mind.",
                "Still working? Let's talk it out."
            ]
        }
        
        let neutralOptions = [
            "Hey \(name), speak your mind.",
            "\(name), let's get your words down.",
            "Talk it out, \(name).",
            "Ready to dictate?",
            "Your voice is your best tool."
        ]
        
        options.append(contentsOf: neutralOptions)
        return options.randomElement() ?? "Welcome back, \(name)"
    }
    @ObservedObject var appState: AppState
    @Binding var currentRoute: AppRoute

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(getGreeting())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.vlTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)

            // Stats Row
            HStack(spacing: 20) {
                StatCard(title: "Total Words", value: "\(appState.totalWordsDictated)")
                StatCard(title: "Current Streak", value: "\(appState.currentStreakDays) days")
                StatCard(title: "Avg WPM", value: "\(appState.averageWPM)")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)

            // Recent Activity
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent activity")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.vlTextPrimary)
                    .padding(.horizontal, 40)

                if appState.transcriptHistory.isEmpty {
                    VStack {
                        Spacer()
                        Text("Your recent dictations will appear here")
                            .font(.system(size: 14))
                            .foregroundColor(.vlTextSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(appState.transcriptHistory) { entry in
                                ActivityCard(entry: entry)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            HStack {
                Button(action: {
                    withAnimation { currentRoute = .settings }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.vlTextPrimary)
                        .padding(8)
                        .background(Color.vlCardBg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.vlControlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11))
                    .foregroundColor(.vlTextSecondary)
                    .padding(.leading, 8)

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.vlTextSecondary)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.vlTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.vlCardBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.vlCardBorder, lineWidth: 1)
        )
    }
}

struct ActivityCard: View {
    let entry: TranscriptEntry
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timeString)
                .font(.system(size: 11))
                .foregroundColor(.vlTextSecondary)
            Text(entry.typed)
                .font(.system(size: 14))
                .foregroundColor(.vlTextPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.vlCardBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.vlCardBorder, lineWidth: 1)
        )
    }
}

struct SettingsPanelView: View {
    @ObservedObject var appState: AppState
    let updater: UpdaterManager
    @Binding var currentRoute: AppRoute

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation { currentRoute = .home }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back to Home")
                    }
                    .foregroundColor(.vlTextPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.vlCardBg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.vlControlBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            SettingsView(appState: appState, updater: updater)
        }
    }
}

