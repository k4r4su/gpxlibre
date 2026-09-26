import SwiftUI

/// Réglages > Tutoriel (it31, point 3) — une page par onglet.
struct TutorialView: View {
    var body: some View {
        List(TutorialContent.pages) { page in
            NavigationLink {
                TutorialPageView(page: page)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).font(.headline)
                        Text(page.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } icon: {
                    Image(systemName: page.systemImage)
                }
            }
        }
        .navigationTitle("Tutoriel")
    }
}

struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        List {
            Section {
                Text(page.summary)
                    .font(.body)
            }
            ForEach(page.topics) { topic in
                Section(topic.title) {
                    ForEach(topic.points, id: \.self) { point in
                        Label {
                            Text(point)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill").font(.system(size: 6))
                        }
                    }
                }
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
