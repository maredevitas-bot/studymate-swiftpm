// StudyMate/Features/Analytics/AnalyticsTabView.swift
import SwiftUI
import SwiftData
import Charts

struct AnalyticsTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var subjects: [Subject]
    @Query(sort: \PlanEntry.date) private var entries: [PlanEntry]

    var weakSubjects: [Subject] {
        subjects
            .filter { $0.averageScore != nil && $0.averageScore! < 70 }
            .sorted { $0.averageScore! < $1.averageScore! }
    }

    var completionRate: Double {
        let total = entries.count
        guard total > 0 else { return 0 }
        return Double(entries.filter(\.isCompleted).count) / Double(total) * 100
    }

    var subjectsWithScore: [Subject] {
        subjects.filter { $0.averageScore != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if subjects.isEmpty {
                    ContentUnavailableView("데이터 없음",
                        systemImage: "chart.bar",
                        description: Text("과목을 추가하고 퀴즈를 풀면\n분석 결과가 표시됩니다"))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            GroupBox("플래너 달성률") {
                                HStack {
                                    Text("\(Int(completionRate))%")
                                        .font(.largeTitle).bold()
                                    Spacer()
                                    Text("\(entries.filter(\.isCompleted).count) / \(entries.count) 완료")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)

                            if !subjectsWithScore.isEmpty {
                                GroupBox("과목별 평균 점수") {
                                    Chart(subjectsWithScore) { subject in
                                        BarMark(
                                            x: .value("점수", subject.averageScore ?? 0),
                                            y: .value("과목", subject.name)
                                        )
                                        .foregroundStyle((subject.averageScore ?? 0) < 70 ? Color.red : Color.blue)
                                        .annotation(position: .trailing) {
                                            Text("\(Int(subject.averageScore ?? 0))점")
                                                .font(.caption)
                                        }
                                    }
                                    .chartXScale(domain: 0...100)
                                    .frame(height: CGFloat(subjectsWithScore.count * 44 + 20))
                                }
                                .padding(.horizontal)
                            }

                            if !weakSubjects.isEmpty {
                                GroupBox("취약 과목 (70점 미만)") {
                                    ForEach(weakSubjects) { subject in
                                        HStack {
                                            Circle()
                                                .fill(Color(hex: subject.colorHex))
                                                .frame(width: 10, height: 10)
                                            Text(subject.displayTitle)
                                            Spacer()
                                            Text("\(Int(subject.averageScore ?? 0))점")
                                                .foregroundStyle(.red).bold()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 700)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("분석")
        }
    }
}
