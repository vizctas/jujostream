class PluginConfig {
  const PluginConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.enabled = false,
    this.settings = const {},
  });

  final String id;
  final String name;
  final String description;
  final PluginCategory category;

  final bool enabled;

  final Map<String, String> settings;

  PluginConfig copyWith({bool? enabled, Map<String, String>? settings}) {
    return PluginConfig(
      id: id,
      name: name,
      description: description,
      category: category,
      enabled: enabled ?? this.enabled,
      settings: settings ?? this.settings,
    );
  }
}

enum PluginCategory {
  metadata,
  extraMetadata,
}
