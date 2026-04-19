class GameCollection {
  final int? id;
  final String name;
  final int colorValue;
  final Set<int> appIds;

  const GameCollection({
    this.id,
    required this.name,
    this.colorValue = 0xFF533483,
    this.appIds = const {},
  });

  GameCollection copyWith({
    int? id,
    String? name,
    int? colorValue,
    Set<int>? appIds,
  }) => GameCollection(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    appIds: appIds ?? this.appIds,
  );
}
