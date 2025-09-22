class TopicAverages {
  final double? selfAvg;
  final double? attendingAvg;
  final int selfCount;
  final int attendingCount;
  const TopicAverages({this.selfAvg, this.attendingAvg, this.selfCount = 0, this.attendingCount = 0});
}

class ResidentMetricsView {
  final int totalShifts;
  final int completedShifts; // where either side is done
  final double completionPct;
  final double? avgSelf;
  final double? avgAttending;
  final int residentCompletedCount;
  final int pendingCount;
  final double? pgyPercentile; // optional heavy
  final Map<String, TopicAverages> topicAvgs; // topicId -> avgs
  final List<ResidentSuggestion> suggestions;

  const ResidentMetricsView({
    required this.totalShifts,
    required this.completedShifts,
    required this.completionPct,
    required this.avgSelf,
    required this.avgAttending,
    required this.residentCompletedCount,
    required this.pendingCount,
    required this.pgyPercentile,
    required this.topicAvgs,
    required this.suggestions,
  });
}

class ResidentSuggestion {
  final String text;
  final DateTime? timestamp;
  final String? author;
  const ResidentSuggestion({required this.text, this.timestamp, this.author});
}

