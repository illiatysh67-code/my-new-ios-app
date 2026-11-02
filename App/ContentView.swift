import SwiftUI

struct StoreApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let developer: String
    let category: String
    let symbol: String
    let color: Color
    let summary: String
}

let sampleApps: [StoreApp] = [
    StoreApp(name: "Pixel Notes", developer: "Example Studio", category: "Productivity",
             symbol: "note.text", color: .blue,
             summary: "Fast, simple notes with folders and tags."),
    StoreApp(name: "Trail Log", developer: "Sample Labs", category: "Health & Fitness",
             symbol: "figure.hiking", color: .green,
             summary: "Track hikes, routes, and elevation on your phone."),
    StoreApp(name: "Budget Bee", developer: "Demo Works", category: "Finance",
             symbol: "dollarsign.circle", color: .orange,
             summary: "Simple monthly budgets with clear charts."),
    StoreApp(name: "Sketchpad", developer: "Example Studio", category: "Creative",
             symbol: "pencil.and.scribble", color: .purple,
             summary: "Draw and doodle with a range of brushes."),
    StoreApp(name: "Lumen Music", developer: "Sample Labs", category: "Music",
             symbol: "music.note", color: .pink,
             summary: "Build playlists and discover new tracks.")
]

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "square.stack") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List(sampleApps) { app in
                NavigationLink(value: app) {
                    AppRow(app: app)
                }
            }
            .navigationTitle("Today")
            .navigationDestination(for: StoreApp.self) { app in
                AppDetailView(app: app)
            }
        }
    }
}

struct SearchView: View {
    @State private var query = ""

    var results: [StoreApp] {
        query.isEmpty ? sampleApps : sampleApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { app in
                NavigationLink(value: app) {
                    AppRow(app: app)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Apps and categories")
            .navigationDestination(for: StoreApp.self) { app in
                AppDetailView(app: app)
            }
        }
    }
}

struct AppRow: View {
    let app: StoreApp

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(app.color.gradient)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: app.symbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                Text(app.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Get") {
                // Placeholder: no action in this starter
            }
            .buttonStyle(.bordered)
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

struct AppDetailView: View {
    let app: StoreApp

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(app.color.gradient)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: app.symbol)
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                    )
                    .padding(.top, 24)

                Text(app.name)
                    .font(.title.bold())
                Text(app.developer)
                    .foregroundStyle(.secondary)

                Button("Get") { }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())

                Text(app.summary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}