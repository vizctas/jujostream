class ComputerDetails {
  String uuid;
  String name;
  String localAddress;
  String remoteAddress;
  String manualAddress;
  String macAddress;
  int httpsPort;
  int configHttpsPort;
  int externalPort;
  String serverCert;
  ComputerState state;
  PairState pairState;
  int runningGameId;
  String activeAddress;
  String rawAppList;
  String serverVersion;
  String gfeVersion;
  int serverCodecModeSupport;
  String gpuName;
  String encoderName;
  bool serverAbrActive;
  bool pairStatusFromHttps = false;
  bool isCloud = false;

  ComputerDetails({
    this.uuid = '',
    this.name = 'Unknown',
    this.localAddress = '',
    this.remoteAddress = '',
    this.manualAddress = '',
    this.macAddress = '',
    this.httpsPort = 47984,
    this.configHttpsPort = 0,
    this.externalPort = 47989,
    this.serverCert = '',
    this.state = ComputerState.unknown,
    this.pairState = PairState.notPaired,
    this.runningGameId = 0,
    this.activeAddress = '',
    this.rawAppList = '',
    this.serverVersion = '7.1.431.-1',
    this.gfeVersion = '',
    this.serverCodecModeSupport = 15,
    this.gpuName = '',
    this.encoderName = '',
    this.serverAbrActive = false,
    this.isCloud = false,
  });

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'localAddress': localAddress,
    'remoteAddress': remoteAddress,
    'manualAddress': manualAddress,
    'macAddress': macAddress,
    'httpsPort': httpsPort,
    'configHttpsPort': configHttpsPort,
    'externalPort': externalPort,
    'serverCert': serverCert,
    'state': state.index,
    'pairState': pairState.index,
    'runningGameId': runningGameId,
    'activeAddress': activeAddress,
    'serverVersion': serverVersion,
    'gfeVersion': gfeVersion,
    'serverCodecModeSupport': serverCodecModeSupport,
    'gpuName': gpuName,
    'encoderName': encoderName,
    'serverAbrActive': serverAbrActive,
    'isCloud': isCloud,
  };

  /// Reads an enum by index without throwing on an out-of-range value.
  /// A stale index from an older build must not take a saved server down.
  static T _enumAt<T>(List<T> values, Object? index, T fallback) {
    if (index is! int || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  factory ComputerDetails.fromJson(Map<String, dynamic> json) {
    return ComputerDetails(
      uuid: json['uuid'] ?? '',
      name: json['name'] ?? 'Unknown',
      localAddress: json['localAddress'] ?? '',
      remoteAddress: json['remoteAddress'] ?? '',
      manualAddress: json['manualAddress'] ?? '',
      macAddress: json['macAddress'] ?? '',
      httpsPort: json['httpsPort'] ?? 47984,
      configHttpsPort: json['configHttpsPort'] ?? 0,
      externalPort: json['externalPort'] ?? 47989,
      serverCert: json['serverCert'] ?? '',
      state: _enumAt(
        ComputerState.values,
        json['state'],
        ComputerState.unknown,
      ),
      pairState: _enumAt(
        PairState.values,
        json['pairState'],
        PairState.notPaired,
      ),
      runningGameId: json['runningGameId'] ?? 0,
      activeAddress: json['activeAddress'] ?? '',
      serverVersion: json['serverVersion'] ?? '7.1.431.-1',
      gfeVersion: json['gfeVersion'] ?? '',
      serverCodecModeSupport: json['serverCodecModeSupport'] ?? 15,
      gpuName: json['gpuName'] ?? '',
      encoderName: json['encoderName'] ?? '',
      serverAbrActive: json['serverAbrActive'] ?? false,
      isCloud: json['isCloud'] ?? false,
    );
  }

  bool get isReachable => state == ComputerState.online;
  bool get isPaired => pairState == PairState.paired;

  /// nvhttp HTTPS port, never zero. Cloud-synced records land here with
  /// `httpsPort = 0` until the first successful /serverinfo fills it in.
  int get effectiveHttpsPort => httpsPort > 0 ? httpsPort : 47984;
}

enum ComputerState { online, offline, unknown }

enum PairState { notPaired, paired, pinRequired, alreadyInProgress, failed }
