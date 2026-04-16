class ParsedMapLocation {
  const ParsedMapLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class MapsUrlParser {
  Future<ParsedMapLocation?> parse(String rawUrl) async {
    // Placeholder for short-link expansion and lat/lng extraction.
    return null;
  }
}
