import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const delegate = _AppLocalizationsDelegate();

  static const Map<String, Map<String, String>> _strings = {

    'appTitle': {'en': 'JUJO Stream', 'es': 'JUJO Stream'},
    'settings': {'en': 'Settings', 'es': 'Ajustes'},
    'about': {'en': 'About', 'es': 'Acerca de'},
    'credits': {'en': 'Credits', 'es': 'Créditos'},
    'plugins': {'en': 'Plugins', 'es': 'Plugins'},
    'cancel': {'en': 'Cancel', 'es': 'Cancelar'},
    'retry': {'en': 'Retry', 'es': 'Reintentar'},
    'back': {'en': 'Back', 'es': 'Atrás'},
    'ok': {'en': 'OK', 'es': 'OK'},
    'close': {'en': 'Close', 'es': 'Cerrar'},
    'done': {'en': 'Done', 'es': 'Listo'},
    'save': {'en': 'Save', 'es': 'Guardar'},
    'create': {'en': 'Create', 'es': 'Crear'},
    'remove': {'en': 'Remove', 'es': 'Eliminar'},
    'add': {'en': 'Add', 'es': 'Agregar'},
    'on': {'en': 'On', 'es': 'Activado'},
    'off': {'en': 'Off', 'es': 'Desactivado'},
    'enabled': {'en': 'Enabled', 'es': 'Habilitado'},
    'disabled': {'en': 'Disabled', 'es': 'Deshabilitado'},
    'language': {'en': 'Language', 'es': 'Idioma'},
    'languageName': {'en': 'English', 'es': 'Español'},

    'servers': {'en': 'Servers', 'es': 'Servidores'},
    'addServer': {'en': 'Add Server', 'es': 'Añadir servidor'},
    'addPcManually': {'en': 'Add PC Manually', 'es': 'Agregar PC manualmente'},
    'scanNetwork': {'en': 'Scan Network', 'es': 'Escanear red'},
    'discoveringServers': {
      'en': 'Discovering servers…',
      'es': 'Buscando servidores…',
    },
    'serverOffline': {
      'en': 'Server is offline',
      'es': 'Servidor fuera de línea',
    },
    'serverUnpaired': {
      'en': 'Server removed pairing. Please pair again.',
      'es': 'El servidor eliminó el emparejamiento. Vincule de nuevo.',
    },
    'verifyingPairing': {
      'en': 'Verifying pairing…',
      'es': 'Verificando vinculación…',
    },
    'noServersFound': {
      'en': 'No servers found',
      'es': 'No se encontraron servidores',
    },
    'tapToAdd': {
      'en': 'Tap + to add a server manually\nor tap refresh to scan again',
      'es':
          'Toca + para agregar un servidor\no toca actualizar para escanear de nuevo',
    },
    'online': {'en': 'Online', 'es': 'En línea'},
    'offline': {'en': 'Offline', 'es': 'Sin conexión'},
    'connected': {'en': 'Connected', 'es': 'Conectado'},
    'disconnected': {'en': 'Disconnected', 'es': 'Desconectado'},
    'enter': {'en': 'Enter', 'es': 'Entrar'},
    'pairAction': {'en': 'Pair', 'es': 'Vincular'},
    'paired': {'en': 'Paired', 'es': 'Vinculado'},
    'notPaired': {'en': 'Not Paired', 'es': 'Sin vincular'},

    'pairingRequired': {
      'en': 'Pairing Required',
      'es': 'Vinculación requerida',
    },
    'pairingInstructions': {
      'en': 'Enter this PIN in Sunshine/Apollo to authorize JUJO:',
      'es': 'Ingresa este PIN en Sunshine/Apollo para autorizar JUJO:',
    },
    'pairing': {'en': 'Pairing in progress…', 'es': 'Vinculando…'},
    'pairingFailed': {'en': 'Pairing failed', 'es': 'Error al vincular'},
    'pairedSuccessfully': {
      'en': 'Paired successfully',
      'es': 'Vinculado exitosamente',
    },

    'refresh': {'en': 'Refresh', 'es': 'Actualizar'},
    'details': {'en': 'Details', 'es': 'Detalles'},
    'ipAddressHint': {
      'en': 'IP or IP:port (e.g., 192.168.1.100)',
      'es': 'IP o IP:puerto (ej. 192.168.1.100)',
    },

    'play': {'en': 'Play', 'es': 'Jugar'},
    'resume': {'en': 'Resume', 'es': 'Reanudar'},
    'noAppsFound': {
      'en': 'No apps found on this server',
      'es': 'No se encontraron juegos en este servidor',
    },
    'loadingGames': {'en': 'Loading games…', 'es': 'Cargando juegos…'},
    'loadingPosters': {
      'en': 'Loading game library…',
      'es': 'Cargando biblioteca de juegos…',
    },
    'running': {'en': 'Running', 'es': 'EN EJECUCIÓN'},
    'favorites': {'en': 'Favorites', 'es': 'Favoritos'},
    'recent': {'en': 'Recent', 'es': 'Recientes'},
    'all': {'en': 'All', 'es': 'Todos'},
    'search': {'en': 'Search', 'es': 'Buscar'},
    'searchGame': {'en': 'Search game', 'es': 'Buscar juego'},
    'typeGameName': {'en': 'Type the name', 'es': 'Escribe el nombre'},
    'noResults': {
      'en': 'No results for this filter.',
      'es': 'Sin resultados para este filtro.',
    },
    'noResultsQuery': {
      'en': 'No results for "{q}".',
      'es': 'Sin resultados para "{q}".',
    },
    'addToFavorites': {'en': 'Add to favorites', 'es': 'Agregar a favoritos'},
    'removeFromFavorites': {
      'en': 'Remove from favorites',
      'es': 'Quitar de favoritos',
    },
    'gameOptions': {'en': 'Game Options', 'es': 'Opciones de juego'},
    'launcherAppearance': {
      'en': 'Launcher Appearance',
      'es': 'Apariencia del launcher',
    },
    'configureVibepollo': {
      'en': 'Configure Vibepollo API',
      'es': 'Configurar Vibepollo API',
    },
    'activeSession': {'en': 'Active Session', 'es': 'Sesión activa'},
    'quitSession': {'en': 'Quit Session', 'es': 'Cerrar sesión'},
    'quitApp': {'en': 'Quit App?', 'es': '¿Cerrar app?'},
    'quitAppConfirm': {
      'en': 'This will terminate the running session on the server.',
      'es': 'Esto cerrará la sesión activa en el servidor.',
    },
    'quit': {'en': 'Quit', 'es': 'Cerrar'},
    'sessionClosed': {'en': 'Session closed', 'es': 'Sesión cerrada'},

    'video': {'en': 'Video', 'es': 'Video'},
    'audio': {'en': 'Audio', 'es': 'Audio'},
    'host': {'en': 'Host', 'es': 'Servidor'},
    'uiDiagnostics': {'en': 'UI & Diagnostics', 'es': 'UI y diagnósticos'},

    'pluginsTitle': {'en': 'Plugins', 'es': 'Plugins'},
    'pluginsSubtitle': {
      'en': 'Extend JUJO with optional features.',
      'es': 'Amplía JUJO con funcionalidades opcionales.',
    },
    'pluginMetadataName': {'en': 'Game Metadata', 'es': 'Metadatos de juegos'},
    'pluginMetadataDesc': {
      'en':
          'Fetches game info (description, cover, rating) from IGDB / RAWG. Uses internet connection.',
      'es':
          'Descarga información de juegos (descripción, portada, calificación) desde IGDB / RAWG. Requiere internet.',
    },
    'pluginVideoName': {
      'en': 'Game Videos (Extra Metadata)',
      'es': 'Videos de juegos (Metadata extra)',
    },
    'pluginVideoDesc': {
      'en':
          'Shows Steam micro-trailers and background videos when browsing games. Uses internet connection.',
      'es':
          'Muestra micro-tráilers de Steam y videos de fondo al navegar juegos. Requiere internet.',
    },
    'pluginDisabledByDefault': {
      'en': 'Disabled by default for stability.',
      'es': 'Desactivado por defecto para mayor estabilidad.',
    },

    'aboutTitle': {'en': 'About JUJO', 'es': 'Acerca de JUJO'},
    'version': {'en': 'Version', 'es': 'Versión'},
    'developedBy': {'en': 'Developed by', 'es': 'Desarrollado por'},
    'basedOn': {'en': 'Based on Artemis by', 'es': 'Basado en Artemis por'},
    'viewOnGithub': {'en': 'View on GitHub', 'es': 'Ver en GitHub'},
    'supportKofi': {'en': 'Support on Ko-fi', 'es': 'Apoyar en Ko-fi'},
    'license': {'en': 'License', 'es': 'Licencia'},
    'openSource': {'en': 'Open Source — GPL-3.0', 'es': 'Código abierto — GPL-3.0'},

    'connecting': {'en': 'Connecting to', 'es': 'Conectando con'},
    'disconnect': {'en': 'Disconnect', 'es': 'Desconectar'},
    'specialKeys': {'en': 'Special Keys', 'es': 'Teclas especiales'},
    'stats': {'en': 'Stats', 'es': 'Stats'},
    'gamepad': {'en': 'Gamepad', 'es': 'Control'},
    'padMouse': {'en': 'Pad Mouse', 'es': 'Mouse con pad'},
    'keyboard': {'en': 'Keyboard', 'es': 'Teclado'},
    'closeMenu': {'en': 'Close Menu', 'es': 'Cerrar menú'},
    'streamError': {
      'en': 'Failed to start streaming session',
      'es': 'Error al iniciar la sesión de streaming',
    },

    'searchingServers': {
      'en': 'Searching for servers...',
      'es': 'Buscando servidores...',
    },
    'makeSureSunshine': {
      'en': 'Make sure Sunshine/Apollo is running on your PC',
      'es': 'Asegúrate de que Sunshine/Apollo esté corriendo en tu PC',
    },
    'wakeOnLan': {'en': 'Wake PC', 'es': 'Despertar PC'},
    'macNotAvailable': {'en': 'MAC not available', 'es': 'MAC no disponible'},

    'focusMode': {'en': 'Focus Mode', 'es': 'Modo Focus'},
    'focusModeSubtitle': {
      'en': 'Single-server dedicated view',
      'es': 'Vista dedicada a un solo servidor',
    },
    'focusModeEnabled': {
      'en': 'Focus Mode enabled',
      'es': 'Modo Focus activado',
    },
    'focusModeDisabled': {
      'en': 'Focus Mode disabled',
      'es': 'Modo Focus desactivado',
    },
    'sendingWol': {
      'en': 'Sending Wake on LAN packet… please wait.',
      'es': 'Enviando paquete Wake on LAN… por favor espera.',
    },

    'connectionError': {'en': 'Connection error', 'es': 'Error de conexión'},
    'quitSessionQuestion': {'en': 'Quit Session?', 'es': '¿Cerrar sesión?'},
    'quitSessionDesc': {
      'en': 'This will terminate the app on the server.',
      'es': 'Esto cerrará la app en el servidor.',
    },
    'streamQuality': {'en': 'Stream Quality', 'es': 'Calidad del Stream'},
    'fast': {'en': 'Fast', 'es': 'Rápido'},
    'balanced': {'en': 'Balanced', 'es': 'Balanceado'},
    'quality': {'en': 'Quality', 'es': 'Calidad'},
    'doubleTapHint': {
      'en': 'Double-tap or gamepad combo to open menu',
      'es': 'Doble-tap o combo de gamepad para abrir menú',
    },
    'navHint': {
      'en': '↑↓ Navigate  ▶ Select  ● Close',
      'es': '↑↓ Navegar  ▶ Seleccionar  ● Cerrar',
    },
    'pointAndClick': {'en': 'Point & Click', 'es': 'Punto y clic'},
    'trackpad': {'en': 'Trackpad', 'es': 'Trackpad'},
    'mouse': {'en': 'Mouse', 'es': 'Mouse'},

    'nowPlaying': {'en': 'Now playing', 'es': 'Jugando ahora'},
    'continueLabel': {'en': 'Continue', 'es': 'Continuar'},
    'options': {'en': 'Options', 'es': 'Opciones'},
    'favorite': {'en': 'Favorite', 'es': 'Favorito'},
    'notFavorite': {'en': 'Not favorite', 'es': 'No favorito'},
    'removeFav': {'en': 'Remove fav.', 'es': 'Quitar fav.'},
    'gridView': {'en': 'Grid view', 'es': 'Vista grid'},
    'carouselView': {'en': 'Carousel view', 'es': 'Vista carrusel'},
    'closeActiveSession': {
      'en': 'Close active session',
      'es': 'Cerrar sesión activa',
    },
    'launchGame': {'en': 'Launch', 'es': 'Iniciar'},
    'resumeSession': {'en': 'Resume Session', 'es': 'Reanudar sesión'},
    'currentlyRunning': {'en': 'Currently running', 'es': 'En ejecución'},
    'localLibrary': {'en': 'Local library', 'es': 'Biblioteca local'},
    'similarGames': {'en': 'Similar to this', 'es': 'Similar a este'},
    'smartFilters': {'en': 'Smart Filters', 'es': 'Filtros inteligentes'},
    'updateMetadata': {'en': 'Update metadata', 'es': 'Actualizar metadata'},
    'updatingMetadata': {
      'en': 'Updating metadata in background…',
      'es': 'Actualizando metadata en segundo plano…',
    },
    'starting': {'en': 'Starting…', 'es': 'Iniciando…'},
    'launchFailed': {'en': 'Launch failed', 'es': 'Error al iniciar'},
    'clear': {'en': 'Clear', 'es': 'Limpiar'},
    'apply': {'en': 'Apply', 'es': 'Aplicar'},
    'skip': {'en': 'Skip', 'es': 'Saltar'},
    'startStreaming': {'en': 'Start streaming', 'es': 'Iniciar streaming'},
    'information': {'en': 'Information', 'es': 'Información'},
    'viewGameDetails': {
      'en': 'View game details',
      'es': 'Ver detalles del juego',
    },

    'sessionMetadata': {'en': 'Session Metadata', 'es': 'Datos de sesión'},
    'steamLibrary': {'en': 'Steam / Library', 'es': 'Steam / Biblioteca'},
    'gameInformation': {'en': 'Game Information', 'es': 'Información del juego'},
    'pickLocalImage': {'en': 'Pick local image', 'es': 'Elegir imagen local'},
    'quickPresets': {'en': 'Quick Presets', 'es': 'Presets rápidos'},
    'perGameStreamProfile': {
      'en': 'Per-Game Stream Profile',
      'es': 'Perfil de stream por juego',
    },
    'competitive': {'en': 'Competitive', 'es': 'Competitivo'},
    'visualQuality': {'en': 'Visual Quality', 'es': 'Calidad visual'},
    'handheld': {'en': 'Handheld', 'es': 'Portátil'},
    'bitrate': {'en': 'Bitrate', 'es': 'Bitrate'},
    'fps': {'en': 'FPS', 'es': 'FPS'},
    'videoCodec': {'en': 'Video Codec', 'es': 'Video Codec'},
    'forceHdr': {'en': 'Force HDR', 'es': 'Forzar HDR'},
    'showOnScreenControls': {
      'en': 'Show On-Screen Controls',
      'es': 'Mostrar controles en pantalla',
    },
    'ultraLowLatency': {'en': 'Ultra Low Latency', 'es': 'Latencia ultrabaja'},
    'performanceOverlay': {
      'en': 'Performance Overlay',
      'es': 'Overlay de rendimiento',
    },
    'frameRate': {'en': 'Frame Rate', 'es': 'Tasa de cuadros'},
    'profileSaved': {
      'en': 'Per-game profile saved',
      'es': 'Perfil por juego guardado',
    },
    'overridesReset': {
      'en': 'Overrides reset to global profile',
      'es': 'Overrides reiniciados al perfil global',
    },
    'presetApplied': {
      'en': 'Preset {name} applied. Save to persist.',
      'es': 'Preset {name} aplicado. Guarda para persistirlo.',
    },
    'watchTrailer': {'en': 'Watch Trailer', 'es': 'Ver Tráiler'},
    'trailerTitle': {'en': 'Trailer — {name}', 'es': 'Tráiler — {name}'},
    'trailerSteamError': {'en': 'Could not play the Steam trailer.', 'es': 'No se pudo reproducir el tráiler de Steam.'},
    'exitFullscreen': {'en': 'Exit fullscreen', 'es': 'Salir de pantalla completa'},
    'goBack': {'en': 'Back', 'es': 'Volver'},
    'fullscreen': {'en': 'Fullscreen', 'es': 'Pantalla completa'},
    'navConfirmBack': {
      'en': '←→ Navigate  Ⓐ Confirm  Ⓑ Back',
      'es': '←→ Navegar  Ⓐ Confirmar  Ⓑ Volver',
    },
    'streamQualityLabel': {'en': 'Stream Quality', 'es': 'Calidad del Stream'},
    'achievements': {'en': 'Achievements…', 'es': 'Logros…'},
    'achievements100': {'en': '100% ★', 'es': '100% ★'},
    'achievementsPending': {'en': 'Pending', 'es': 'Pendientes'},
    'achievementsNeverStarted': {'en': 'Not started', 'es': 'Sin iniciar'},
    'vibepolloConfigApi': {
      'en': 'Vibepollo Config API',
      'es': 'Vibepollo Config API',
    },
    'vibepolloInstructions': {
      'en':
          'Enter the web UI credentials for your Vibepollo server to enable Playnite library categories and store badges.',
      'es':
          'Ingresa las credenciales de la web UI de tu servidor Vibepollo para habilitar categorías de biblioteca Playnite y badges de tienda.',
    },
    'username': {'en': 'Username', 'es': 'Usuario'},
    'password': {'en': 'Password', 'es': 'Contraseña'},

    'multipleControllers': {
      'en': 'Multiple Controllers',
      'es': 'Múltiples mandos',
    },
    'multipleControllersDesc': {
      'en': 'Allow more than one controller',
      'es': 'Permitir más de un mando',
    },
    'hdrLabel': {'en': 'HDR', 'es': 'HDR'},
    'hdrDesc': {
      'en': 'Requires host & client support',
      'es': 'Requiere soporte en host y cliente',
    },
    'readyStatus': {'en': 'READY', 'es': 'LISTO'},

    'steamLibraryInfoName': {
      'en': 'Steam Library Info',
      'es': 'Info de biblioteca Steam',
    },
    'steamLibraryInfoDesc': {
      'en':
          'Shows data from your Steam library in each game\'s sheet: play time, achievements, reviews, Steam Store genres, and filters by 100%, pending or never started. Requires Steam Connect.',
      'es':
          'Muestra datos de tu biblioteca Steam en la ficha de cada juego: tiempo jugado, logros, reseñas, géneros de Steam Store, y filtros por 100%, pendiente o nunca iniciado. Requiere Steam Connect.',
    },

    'themeAndPerformance': {
      'en': 'Theme & Performance',
      'es': 'Tema y rendimiento',
    },
    'reduceEffects': {'en': 'Reduce Effects', 'es': 'Reducir efectos'},
    'reduceEffectsDesc': {
      'en': 'Disable Ken Burns, palette extraction, video previews',
      'es': 'Desactiva Ken Burns, extracción de paleta, previews de video',
    },
    'performanceMode': {'en': 'Performance Mode', 'es': 'Modo rendimiento'},
    'performanceModeDesc': {
      'en': 'Reduce effects + lower quality defaults for weak devices',
      'es':
          'Reduce efectos + calidad baja por defecto para dispositivos débiles',
    },
    'inputTouch': {'en': 'Input / Touch', 'es': 'Entrada / Táctil'},
    'gamepadSection': {'en': 'Gamepad', 'es': 'Mando'},
    'keyboardSection': {'en': 'Keyboard', 'es': 'Teclado'},
    'onScreenControls': {
      'en': 'On-Screen Controls',
      'es': 'Controles en pantalla',
    },
    'aboutAndCredits': {'en': 'About & Credits', 'es': 'Acerca de y créditos'},
    'versionCredits': {
      'en': 'Version, credits, Ko-fi',
      'es': 'Versión, créditos, Ko-fi',
    },
    'gameMetadataVideos': {
      'en': 'Game metadata, background videos…',
      'es': 'Metadatos de juegos, videos de fondo…',
    },

    'couldNotOpen': {'en': 'Could not open', 'es': 'No se pudo abrir'},
    'welcomeToJujo': {'en': 'Welcome to JUJO', 'es': 'Bienvenido a JUJO'},
    'gotIt': {'en': 'Got it', 'es': 'Entendido'},

    'runningStatus': {'en': '● RUNNING', 'es': '● EN EJECUCIÓN'},
    'noResultsShort': {'en': 'No results.', 'es': 'Sin resultados.'},
    'playniteCategories': {
      'en': 'Playnite Categories',
      'es': 'Categorías Playnite',
    },
    'categoryLabel': {'en': 'Category', 'es': 'Categoría'},
    'genreLabel': {'en': 'Genre', 'es': 'Género'},
    'enableMetadataHint': {
      'en':
          'Enable Metadata, add your RAWG API key and turn on Smart Genre Filters to use this filter.',
      'es':
          'Activa Metadata, agrega tu API key RAWG y habilita Smart Genre Filters para usar este filtro.',
    },
    'smartFiltersExplain': {
      'en':
          'We group RAWG genres into broad categories so you can browse faster without adding visual noise to the main screen.',
      'es':
          'Agrupamos los generos RAWG en categorias amplias para navegar mas rapido sin meter mas ruido visual en la pantalla principal.',
    },
    'noGenresYet': {
      'en':
          'No genres classified yet. Run a metadata update to populate the filters.',
      'es':
          'Todavia no hay generos clasificados. Lanza una actualizacion de metadata para poblar los filtros.',
    },
    'genreAction': {'en': 'Action', 'es': 'Acción'},
    'genreAdventure': {'en': 'Adventure', 'es': 'Aventura'},
    'genreFighting': {'en': 'Fighting', 'es': 'Pelea'},
    'genrePlatform': {'en': 'Platform', 'es': 'Plataforma'},
    'genreCards': {'en': 'Cards', 'es': 'Cartas'},
    'genreRogue': {'en': 'Rogue', 'es': 'Rogue'},
    'genreRpg': {'en': 'RPG', 'es': 'RPG'},
    'genreStrategy': {'en': 'Strategy', 'es': 'Estrategia'},
    'genreSimulation': {'en': 'Simulation', 'es': 'Simulación'},
    'genreRacing': {'en': 'Racing', 'es': 'Carreras'},
    'genreSports': {'en': 'Sports', 'es': 'Deportes'},
    'genrePuzzle': {'en': 'Puzzle', 'es': 'Puzzle'},
    'genreHorror': {'en': 'Horror', 'es': 'Horror'},
    'genreStealth': {'en': 'Stealth', 'es': 'Stealth'},
    'mostPlayed': {'en': 'Most played', 'es': 'Más jugados'},
    'collectionFallback': {'en': 'Collection', 'es': 'Colección'},
    'noDescription': {
      'en':
          'No description available. Enable the Metadata addon to get game info.',
      'es':
          'Sin descripción disponible. Activa el addon de Metadatos para obtener información del juego.',
    },
    'steamApiKeyHint': {
      'en':
          'Set up a Steam Web API Key in the plugin to view play time and achievements.',
      'es':
          'Configura una Steam Web API Key en el plugin para ver tiempo jugado y logros.',
    },
    'accountLabel': {'en': 'Account', 'es': 'Cuenta'},
    'timePlayed': {'en': 'Time played', 'es': 'Tiempo jugado'},
    'last2Weeks': {'en': 'Last 2 weeks', 'es': 'Últimas 2 semanas'},
    'lastSessionLabel': {'en': 'Last Session', 'es': 'Última sesión'},
    'releaseDate': {'en': 'Release', 'es': 'Lanzamiento'},
    'developerLabel': {'en': 'Developer', 'es': 'Desarrollador'},
    'metacriticLabel': {'en': 'Metacritic', 'es': 'Metacritic'},
    'never': {'en': 'Never', 'es': 'Nunca'},
    'todayLabel': {'en': 'Today', 'es': 'Hoy'},
    'yesterdayLabel': {'en': 'Yesterday', 'es': 'Ayer'},
    'justNow': {'en': 'Just now', 'es': 'Ahora mismo'},
    'presetExplain': {
      'en':
          'Apply a base profile for this game and then fine-tune the details below.',
      'es':
          'Aplica un perfil base para este juego y luego ajusta los detalles finos debajo.',
    },
    'competitiveSub': {
      'en': 'Low latency and overlay active',
      'es': 'Baja latencia y overlay activo',
    },
    'visualQualitySub': {
      'en': 'More bitrate and HDR when applicable',
      'es': 'Más bitrate y HDR cuando conviene',
    },
    'balancedSub': {
      'en': 'Stable profile for most',
      'es': 'Perfil estable para la mayoría',
    },
    'handheldSub': {
      'en': 'Touch-friendly and variable networks',
      'es': 'Pensado para toque y redes variables',
    },
    'customProfile': {'en': 'Custom', 'es': 'Personalizado'},
    'globalOnly': {'en': 'Global only', 'es': 'Solo global'},
    'launchCountLabel': {'en': 'Launch Count', 'es': 'Veces lanzado'},
    'overridesLabelMeta': {'en': 'Overrides', 'es': 'Overrides'},
    'unfav': {'en': 'Unfav', 'es': 'Quitar'},
    'resetLabel': {'en': 'Reset', 'es': 'Reiniciar'},
    'closeSession': {'en': 'Close Session', 'es': 'Cerrar sesión'},
    'menuHint': {
      'en': '↑↓ Navigate  ←→ Options  Ⓐ Select  Ⓑ Close',
      'es': '↑↓ Navegar  ←→ Opciones  Ⓐ Seleccionar  Ⓑ Cerrar',
    },
    'settingsLabel': {'en': 'Settings', 'es': 'Opciones'},
    'fav': {'en': 'Fav', 'es': 'Fav'},

    'configureFromPhone': {
      'en': 'Configure from phone',
      'es': 'Configurar desde celular',
    },
    'scanQrInstruction': {
      'en': 'Scan the QR with your phone',
      'es': 'Escanea el QR con tu celular',
    },
    'qrDescription': {
      'en':
          'Open the URL in your phone\'s browser to configure\n'
          'API keys, Steam ID and more — no need to type on the TV.',
      'es':
          'Abre la URL en el navegador de tu teléfono para configurar\n'
          'API keys, Steam ID y más — sin necesidad de teclear en la TV.',
    },
    'serverActiveNote': {
      'en':
          'The server will remain active while the app is open.\n'
          'Both devices must be on the same Wi-Fi network.',
      'es':
          'El servidor seguirá activo mientras la app esté abierta.\n'
          'Ambos dispositivos deben estar en la misma red Wi-Fi.',
    },
    'noLocalIpError': {
      'en': 'Could not obtain local network IP.',
      'es': 'No se pudo obtener la IP de red local.',
    },
    'serverStartError': {
      'en': 'Error starting server: {error}',
      'es': 'Error al iniciar el servidor: {error}',
    },

    'appControlled': {'en': 'App Controlled', 'es': 'Controlado por app'},

    'configureFromPhoneBtn': {
      'en': 'Configure from phone',
      'es': 'Configurar desde el celular',
    },
    'pluginEnabledSnack': {
      'en': '{name} enabled',
      'es': '{name} habilitado',
    },
    'pluginDisabledSnack': {
      'en': '{name} disabled',
      'es': '{name} deshabilitado',
    },
    'videoDelayLabel': {
      'en': 'Video delay',
      'es': 'Delay de video',
    },

    'myProfile': {'en': 'My Profile', 'es': 'Mi Perfil'},
    'changeAvatar': {'en': 'Change Avatar', 'es': 'Cambiar Avatar'},
    'changeName': {'en': 'Change Name', 'es': 'Cambiar Nombre'},
    'chooseYourAvatar': {'en': 'CHOOSE YOUR AVATAR', 'es': 'ELIGE TU AVATAR'},
    'avatarNavHint': {
      'en': 'Use arrows to navigate · A to confirm · B to cancel',
      'es': 'Usa las flechas para navegar · A para confirmar · B para cancelar',
    },
    'yourName': {'en': 'Your name', 'es': 'Tu nombre'},
    'playerName': {'en': 'Player name', 'es': 'Nombre de jugador'},
    'totalTime': {'en': 'Total time', 'es': 'Tiempo total'},
    'gamesLabel': {'en': 'Games', 'es': 'Juegos'},
    'sessionsLabel': {'en': 'Sessions', 'es': 'Sesiones'},
    'achievementsTitle': {'en': 'Achievements', 'es': 'Logros'},
    'achievementsSection': {'en': 'ACHIEVEMENTS', 'es': 'LOGROS'},
    'unlockedCount': {'en': 'unlocked', 'es': 'desbloqueados'},
    'recentSessions': {'en': 'Recent sessions', 'es': 'Sesiones recientes'},
    'noSessionsYet': {'en': 'No sessions yet', 'es': 'Sin sesiones todavía'},
    'playToSeeHistory': {
      'en': 'Play a game to see your history here',
      'es': 'Juega una partida para ver tu historial aquí',
    },
    'completedPercent': {'en': 'completed', 'es': 'completado'},

    'myCollections': {'en': 'My collections', 'es': 'Mis colecciones'},
    'noCollections': {'en': 'No collections', 'es': 'Sin colecciones'},
    'createFirstCollection': {
      'en': 'Create your first collection to group your favorite games.',
      'es': 'Crea tu primera colección para agrupar tus juegos favoritos.',
    },
    'createCollection': {'en': 'Create collection', 'es': 'Crear colección'},
    'newCollection': {'en': 'New collection', 'es': 'Nueva colección'},
    'pipDesc': {
      'en': 'When going Home or switching apps, the session continues in PiP. If OFF, it disconnects.',
      'es': 'Al ir a Home o cambiar de app, la sesión continúa en PiP. Si está OFF, se desconecta.',
    },
    'deleteCollection': {'en': 'Delete collection', 'es': 'Eliminar colección'},
    'deleteCollectionConfirm': {'en': 'Delete', 'es': 'Eliminar'},
    'renameCollection': {'en': 'Rename collection', 'es': 'Renombrar colección'},
    'renameLabel': {'en': 'Rename', 'es': 'Renombrar'},
    'collectionName': {'en': 'Collection name', 'es': 'Nombre de la colección'},
    'colorLabel': {'en': 'Color', 'es': 'Color'},
    'selectCollection': {'en': 'Select a collection', 'es': 'Selecciona una colección'},
    'addToCollection': {'en': 'Add to collection', 'es': 'Agregar a colección'},
    'addedToCollection': {'en': 'added to', 'es': 'agregado a'},
    'collectionNameHint': {'en': 'Name', 'es': 'Nombre'},
    'gamesCount': {'en': 'games', 'es': 'juegos'},
    'gameCount': {'en': 'game', 'es': 'juego'},

    'resetDefaults': {'en': 'Reset', 'es': 'Restablecer'},
    'resetDefaultsConfirm': {'en': 'Reset to defaults?', 'es': '¿Volver a los valores por defecto?'},
    'yes': {'en': 'Yes', 'es': 'Sí'},
    'launcherAppearanceTitle': {'en': 'Launcher Appearance', 'es': 'Apariencia del Launcher'},

    'applyingQuality': {'en': 'Applying quality…', 'es': 'Aplicando calidad…'},
    'applyingPreset': {'en': 'Applying preset…', 'es': 'Aplicando preset…'},
    'reconnecting': {'en': 'Reconnecting…', 'es': 'Reconectando…'},

    'smartBitrate': {'en': 'Smart Bitrate', 'es': 'Bitrate Inteligente'},
    'smartBitrateDesc': {
      'en': 'Auto-detect network speed and pick the best bitrate before each session',
      'es': 'Detecta la velocidad de red y elige el mejor bitrate antes de cada sesión',
    },
    'smartBitrateMin': {'en': 'Minimum Range', 'es': 'Rango Mínimo'},
    'smartBitrateMax': {'en': 'Maximum Range', 'es': 'Rango Máximo'},
    'smartBitrateMeasuring': {'en': 'Measuring network…', 'es': 'Midiendo red…'},
    'smartBitrateResult': {'en': 'Smart Bitrate: {value} Mbps', 'es': 'Bitrate Inteligente: {value} Mbps'},

    'editName': {'en': 'Edit Name', 'es': 'Editar Nombre'},
    'editPoster': {'en': 'Change Poster', 'es': 'Cambiar Póster'},
    'customNameHint': {'en': 'Custom game name', 'es': 'Nombre personalizado'},
    'posterUrlHint': {'en': 'Image URL (https://...)', 'es': 'URL de imagen (https://...)'},
    'overrideApplied': {'en': 'Custom override saved', 'es': 'Personalización guardada'},
    'overrideCleared': {'en': 'Override removed', 'es': 'Personalización eliminada'},
    'clearOverride': {'en': 'Reset to original', 'es': 'Restaurar original'},

    'remoteAccessVpn': {'en': 'Remote Access (VPN)', 'es': 'Acceso Remoto (VPN)'},
    'remoteAccessVpnDesc': {'en': 'Tailscale, ZeroTier, WireGuard', 'es': 'Tailscale, ZeroTier, WireGuard'},
    'artQualityLabel': {'en': 'Art Quality', 'es': 'Calidad de arte'},
    'artQualityHigh': {'en': 'High  (no limit)', 'es': 'Alta  (sin límite)'},
    'artQualityMedium': {'en': 'Medium  (max 720 px)', 'es': 'Media  (max 720 px)'},
    'artQualityLow': {'en': 'Low  (max 400 px)', 'es': 'Baja  (max 400 px)'},
    'launcherThemeClassic': {'en': 'Classic', 'es': 'Clásico'},
    'launcherThemeClassicDesc': {
      'en': 'Vertical poster carousel with grid toggle. The original JUJO layout.',
      'es': 'Carrusel vertical de pósters con vista grid. El layout original de JUJO.',
    },
    'launcherThemeBackbone': {'en': 'Backbone', 'es': 'Backbone'},
    'launcherThemeBackboneDesc': {
      'en': 'Rectangular cards, side menu, status bar. Inspired by Backbone One.',
      'es': 'Tarjetas rectangulares, menú lateral, barra de estado. Inspirado en Backbone One.',
    },
    'launcherThemePs5': {'en': 'PS5', 'es': 'PS5'},
    'launcherThemePs5Desc': {
      'en': 'Horizontal icon strip with hero art and slide-up detail panel. TV optimized.',
      'es': 'Barra de iconos horizontal con arte de fondo y panel deslizable. Optimizado para TV.',
    },
    'launcherThemeHero': {'en': 'Hero', 'es': 'Hero'},
    'launcherThemeHeroDesc': {
      'en': 'Full-screen hero art, bottom icon strip, slide-up detail panel. Premium.',
      'es': 'Arte de fondo completo, barra inferior de iconos, panel deslizable. Premium.',
    },
    'launcherThemeLabel': {'en': 'Layout Style', 'es': 'Estilo de Layout'},

    'presAppearance': {'en': 'Launcher Appearance', 'es': 'Apariencia del Launcher'},
    'presReset': {'en': 'Reset', 'es': 'Restablecer'},
    'presResetConfirm': {'en': 'Restore default values?', 'es': '¿Volver a los valores por defecto?'},
    'presYes': {'en': 'Yes', 'es': 'Sí'},
    'presSectionBackground': {'en': 'Background', 'es': 'Fondo de pantalla'},
    'presBlur': {'en': 'Blur', 'es': 'Desenfoque'},
    'presOverlayDarkness': {'en': 'Overlay darkness', 'es': 'Oscuridad del overlay'},
    'presParallaxDrift': {'en': 'Parallax drift', 'es': 'Derive parallax'},
    'presParallaxDriftSub': {'en': 'Background moves smoothly when switching games', 'es': 'El fondo se mueve suavemente al cambiar de juego'},
    'presParallaxSpeed': {'en': 'Parallax speed', 'es': 'Velocidad del parallax'},
    'presParallaxSpeedSub': {'en': 'Full cycle time — higher = slower', 'es': 'Tiempo de un ciclo completo — mayor = más lento'},
    'presSectionCards': {'en': 'Game cards', 'es': 'Tarjetas de juego'},
    'presBorderRadius': {'en': 'Border radius', 'es': 'Redondez de bordes'},
    'presCardSpacing': {'en': 'Card spacing', 'es': 'Separación entre tarjetas'},
    'presCardWidth': {'en': 'Card width', 'es': 'Ancho de tarjeta'},
    'presCardHeight': {'en': 'Card height', 'es': 'Alto de tarjeta'},
    'presShowGameName': {'en': 'Show game name', 'es': 'Mostrar nombre del juego'},
    'presRunningIndicator': {'en': 'Running indicator', 'es': 'Indicador "en ejecución"'},
    'presRunningIndicatorSub': {'en': 'Green dot on active game cards', 'es': 'Punto verde en tarjetas de juegos activos'},
    'presSectionCategoryBar': {'en': 'Category bar', 'es': 'Barra de categorías'},
    'presShowFilterBar': {'en': 'Show filter bar', 'es': 'Mostrar barra de filtros'},
    'presFilterBarSub': {'en': 'All / Recent / Active / Favorites', 'es': 'Todos / Recientes / Activos / Favoritos'},
    'presShowCounts': {'en': 'Show counts', 'es': 'Mostrar conteos'},
    'presShowCountsSub': {'en': 'Number of games per category', 'es': 'Número de juegos por categoría'},
    'presSectionSearch': {'en': 'Search', 'es': 'Búsqueda'},
    'presInstantSearch': {'en': 'Instant search while typing', 'es': 'Filtro instantáneo al escribir'},
    'presInstantSearchSub': {'en': 'Filter the list as you type without confirming first', 'es': 'Filtra la lista mientras escribes sin confirmar primero'},
    'themeOptions': {'en': 'Theme Options', 'es': 'Opciones del Tema'},
    'launcherThemeDesc': {
      'en': 'Change the entire layout and navigation style',
      'es': 'Cambia el layout completo y el estilo de navegación',
    },
    'colorSchemeLabel': {'en': 'Color Scheme', 'es': 'Esquema de Color'},
    'colorSchemeDesc': {
      'en': 'Change the color palette (works with any theme)',
      'es': 'Cambia la paleta de colores (funciona con cualquier tema)',
    },
    'proUpsellTitle': {'en': 'Upgrade to Pro', 'es': 'Mejora a Pro'},
    'proUpsellSubtitle': {
      'en': 'Unlock the full JUJO Stream experience',
      'es': 'Desbloquea la experiencia completa de JUJO Stream',
    },
    'proUpsellBenefit1': {
      'en': 'All color schemes & launcher themes',
      'es': 'Todos los esquemas de color y temas del launcher',
    },
    'proUpsellBenefit2': {
      'en': 'Unlimited favorites & collections',
      'es': 'Favoritos y colecciones ilimitados',
    },
    'proUpsellBenefit3': {
      'en': 'Smart Bitrate, Cloud Sync & advanced overlay',
      'es': 'Bitrate Inteligente, Cloud Sync y overlay avanzado',
    },
    'proUpsellBenefit4': {
      'en': 'Premium plugins: Intro Video, Steam Library, Genre Filters, Game Videos',
      'es': 'Plugins premium: Video Intro, Biblioteca Steam, Filtros de Género, Videos de Juegos',
    },
    'proUpsellBenefit5': {
      'en': 'High quality art, full session history & more',
      'es': 'Arte en alta calidad, historial completo de sesiones y más',
    },
    'proUpsellBenefit6': {
      'en': 'Future themes & features included',
      'es': 'Futuros temas y funcionalidades incluidos',
    },
    'proUpsellCta': {'en': 'Get Pro', 'es': 'Obtener Pro'},
    'proUpsellLater': {'en': 'Maybe later', 'es': 'Quizás después'},
    'favoritesLimitReached': {
      'en': 'Free limit reached (5 favorites). Upgrade to Pro for unlimited.',
      'es': 'Límite gratuito alcanzado (5 favoritos). Mejora a Pro para ilimitados.',
    },
    'pluginRemove': {'en': 'Remove', 'es': 'Quitar'},
    'pluginSelectVideo': {'en': 'Select video', 'es': 'Seleccionar video'},
    'pluginVideoSaved': {
      'en': 'Startup video saved. You can skip it when opening the app.',
      'es': 'Video de inicio guardado. Puedes interrumpirlo al abrir la app.',
    },
    'pluginSteamLoginFirst': {
      'en': 'Sign in with Steam first.',
      'es': 'Inicia sesión con Steam primero.',
    },
    'pluginSteamLogin': {
      'en': 'Sign in with Steam',
      'es': 'Iniciar sesión con Steam',
    },
    'pluginSteamConnecting': {
      'en': 'Connecting…',
      'es': 'Conectando…',
    },
    'pluginSteamAccount': {
      'en': 'Account',
      'es': 'Cuenta',
    },
    'pluginVideoHint': {
      'en': 'Recommended: 2-4 second videos. Users can interrupt playback when opening the app.',
      'es': 'Recomendado: videos de 2-4 segundos. El usuario puede interrumpir la reproducción al abrir la app.',
    },
    'pluginVideoWhen': {
      'en': 'When should the video play?',
      'es': '¿Cuándo reproducir el video?',
    },
    'pluginVideoTriggerApp': {
      'en': 'When opening the app',
      'es': 'Al abrir la aplicación',
    },
    'pluginVideoTriggerServer': {
      'en': 'Before entering a server',
      'es': 'Antes de entrar a un servidor',
    },
    'pluginStartMuted': {
      'en': 'Start videos muted',
      'es': 'Iniciar videos sin sonido',
    },
    'pluginVideoDelay': {
      'en': 'Video start delay',
      'es': 'Tiempo antes de reproducir el video',
    },
    'pluginSteamValidationFailed': {
      'en': 'Could not validate Steam connection.',
      'es': 'No se pudo validar la conexión con Steam.',
    },
    'pluginSteamConnectedMsg': {
      'en': 'Steam connected',
      'es': 'Steam conectado',
    },
    'pluginSteamLinkedPrivate': {
      'en': 'Steam linked (private profile).',
      'es': 'Steam vinculado (perfil privado).',
    },
  };

  String _s(String key) {
    final lang = locale.languageCode == 'es' ? 'es' : 'en';
    return _strings[key]?[lang] ?? _strings[key]?['en'] ?? key;
  }

  String get appTitle => _s('appTitle');
  String get settings => _s('settings');
  String get about => _s('about');
  String get credits => _s('credits');
  String get plugins => _s('plugins');
  String get cancel => _s('cancel');
  String get retry => _s('retry');
  String get back => _s('back');
  String get ok => _s('ok');
  String get close => _s('close');
  String get done => _s('done');
  String get save => _s('save');
  String get create => _s('create');
  String get remove => _s('remove');
  String get add => _s('add');
  String get on => _s('on');
  String get off => _s('off');
  String get enabled => _s('enabled');
  String get disabled => _s('disabled');
  String get language => _s('language');
  String get languageName => _s('languageName');

  String get servers => _s('servers');
  String get addServer => _s('addServer');
  String get addPcManually => _s('addPcManually');
  String get scanNetwork => _s('scanNetwork');
  String get discoveringServers => _s('discoveringServers');
  String get serverOffline => _s('serverOffline');
  String get serverUnpaired => _s('serverUnpaired');
  String get verifyingPairing => _s('verifyingPairing');
  String get noServersFound => _s('noServersFound');
  String get tapToAdd => _s('tapToAdd');
  String get online => _s('online');
  String get offline => _s('offline');
  String get connected => _s('connected');
  String get disconnected => _s('disconnected');
  String get enter => _s('enter');
  String get pairAction => _s('pairAction');
  String get paired => _s('paired');
  String get notPaired => _s('notPaired');

  String get pairingRequired => _s('pairingRequired');
  String get pairingInstructions => _s('pairingInstructions');
  String get pairing => _s('pairing');
  String get pairingFailed => _s('pairingFailed');
  String pairedSuccessfully(String name) => locale.languageCode == 'es'
      ? 'Vinculado exitosamente con $name'
      : 'Paired successfully with $name';

  String get refresh => _s('refresh');
  String get details => _s('details');
  String get ipAddressHint => _s('ipAddressHint');

  String get play => _s('play');
  String get resume => _s('resume');
  String get noAppsFound => _s('noAppsFound');
  String get loadingGames => _s('loadingGames');
  String get loadingPosters => _s('loadingPosters');
  String get running => _s('running');
  String get favorites => _s('favorites');
  String get recent => _s('recent');
  String get all => _s('all');
  String get search => _s('search');
  String get searchGame => _s('searchGame');
  String get typeGameName => _s('typeGameName');
  String get noResults => _s('noResults');
  String noResultsQuery(String q) => _s('noResultsQuery').replaceAll('{q}', q);
  String get addToFavorites => _s('addToFavorites');
  String get removeFromFavorites => _s('removeFromFavorites');
  String get gameOptions => _s('gameOptions');
  String get launcherAppearance => _s('launcherAppearance');
  String get configureVibepollo => _s('configureVibepollo');
  String get activeSession => _s('activeSession');
  String get quitSession => _s('quitSession');
  String get quitApp => _s('quitApp');
  String get quitAppConfirm => _s('quitAppConfirm');
  String get quit => _s('quit');
  String get sessionClosed => _s('sessionClosed');

  String get video => _s('video');
  String get audio => _s('audio');
  String get host => _s('host');
  String get uiDiagnostics => _s('uiDiagnostics');

  String get pluginsTitle => _s('pluginsTitle');
  String get pluginsSubtitle => _s('pluginsSubtitle');
  String get pluginMetadataName => _s('pluginMetadataName');
  String get pluginMetadataDesc => _s('pluginMetadataDesc');
  String get pluginVideoName => _s('pluginVideoName');
  String get pluginVideoDesc => _s('pluginVideoDesc');
  String get pluginDisabledByDefault => _s('pluginDisabledByDefault');

  String get aboutTitle => _s('aboutTitle');
  String get version => _s('version');
  String get developedBy => _s('developedBy');
  String get basedOn => _s('basedOn');
  String get viewOnGithub => _s('viewOnGithub');
  String get supportKofi => _s('supportKofi');
  String get license => _s('license');
  String get openSource => _s('openSource');

  String connecting(String appName) => locale.languageCode == 'es'
      ? 'Conectando con $appName…'
      : 'Connecting to $appName…';
  String get disconnect => _s('disconnect');
  String get specialKeys => _s('specialKeys');
  String get stats => _s('stats');
  String get gamepadLabel => _s('gamepad');
  String get padMouse => _s('padMouse');
  String get keyboard => _s('keyboard');
  String get closeMenu => _s('closeMenu');
  String get streamError => _s('streamError');
  String get pipPremiumHint => locale.languageCode == 'es'
      ? 'PiP requiere JUJO Pro'
      : 'PiP requires JUJO Pro';

  String specialKeyDesc(String key) {
    const descs = {
      'skExit': {'en': 'Exit', 'es': 'Salir'},
      'skFullscreen': {'en': 'Fullscreen', 'es': 'P. Completa'},
      'skCloseApp': {'en': 'Close App', 'es': 'Cerrar App'},
      'skSwitchApp': {'en': 'Switch App', 'es': 'Cambiar App'},
      'skWindowed': {'en': 'Windowed', 'es': 'Ventana'},
      'skDesktop': {'en': 'Desktop', 'es': 'Escritorio'},
      'skTaskView': {'en': 'Task View', 'es': 'Vista Tareas'},
      'skDisplayMode': {'en': 'Display Mode', 'es': 'Modo Display'},
      'skDisplayLeft': {'en': 'Display ←', 'es': 'Display Izq'},
      'skDisplayRight': {'en': 'Display →', 'es': 'Display Der'},
      'skNextField': {'en': 'Next Field', 'es': 'Sig. Campo'},
      'skPaste': {'en': 'Paste', 'es': 'Pegar'},
      'skCopy': {'en': 'Copy', 'es': 'Copiar'},
      'skCut': {'en': 'Cut', 'es': 'Cortar'},
      'skUndo': {'en': 'Undo', 'es': 'Deshacer'},
      'skSelectAll': {'en': 'Select All', 'es': 'Selec. Todo'},
      'skStartMenu': {'en': 'Start Menu', 'es': 'Menú Inicio'},
      'skGameBar': {'en': 'Game Bar', 'es': 'Barra Juegos'},
      'skScreenshot': {'en': 'Screenshot', 'es': 'Captura'},
      'skSecurity': {'en': 'Security', 'es': 'Seguridad'},
      'skTaskManager': {'en': 'Task Mgr', 'es': 'Admin Tareas'},
      'skExplorer': {'en': 'Explorer', 'es': 'Explorador'},
      'skPlayPause': {'en': 'Play/Pause', 'es': 'Reproducir'},
      'skVolUp': {'en': 'Vol +', 'es': 'Vol +'},
      'skVolDown': {'en': 'Vol −', 'es': 'Vol −'},
      'skMute': {'en': 'Mute', 'es': 'Silenciar'},
    };
    final map = descs[key];
    if (map == null) return key;
    return map[locale.languageCode] ?? map['en'] ?? key;
  }

  String get searchingServers => _s('searchingServers');
  String get makeSureSunshine => _s('makeSureSunshine');
  String get wakeOnLan => _s('wakeOnLan');
  String get macNotAvailable => _s('macNotAvailable');
  String get sendingWol => _s('sendingWol');

  String get focusMode => _s('focusMode');
  String get focusModeSubtitle => _s('focusModeSubtitle');
  String get focusModeEnabled => _s('focusModeEnabled');
  String get focusModeDisabled => _s('focusModeDisabled');

  String get connectionError => _s('connectionError');
  String get quitSessionQuestion => _s('quitSessionQuestion');
  String get quitSessionDesc => _s('quitSessionDesc');
  String get streamQuality => _s('streamQuality');
  String get fast => _s('fast');
  String get balanced => _s('balanced');
  String get quality => _s('quality');
  String get doubleTapHint => _s('doubleTapHint');
  String get navHint => _s('navHint');
  String get pointAndClick => _s('pointAndClick');
  String get trackpadLabel => _s('trackpad');
  String get mouseLabel => _s('mouse');

  String get nowPlaying => _s('nowPlaying');
  String get continueLabel => _s('continueLabel');
  String get options => _s('options');
  String get favorite => _s('favorite');
  String get notFavorite => _s('notFavorite');
  String get removeFav => _s('removeFav');
  String get gridView => _s('gridView');
  String get carouselView => _s('carouselView');
  String get closeActiveSession => _s('closeActiveSession');
  String get launchGame => _s('launchGame');
  String get resumeSession => _s('resumeSession');
  String get currentlyRunning => _s('currentlyRunning');
  String get localLibrary => _s('localLibrary');
  String get similarGames => _s('similarGames');
  String get smartFilters => _s('smartFilters');
  String get updateMetadata => _s('updateMetadata');
  String get updatingMetadata => _s('updatingMetadata');
  String get starting => _s('starting');
  String get launchFailed => _s('launchFailed');
  String get clear => _s('clear');
  String get apply => _s('apply');
  String get skip => _s('skip');
  String get startStreaming => _s('startStreaming');
  String get information => _s('information');
  String get viewGameDetails => _s('viewGameDetails');

  String get sessionMetadata => _s('sessionMetadata');
  String get steamLibrary => _s('steamLibrary');
  String get gameInformation => _s('gameInformation');
  String get pickLocalImage => _s('pickLocalImage');
  String get quickPresets => _s('quickPresets');
  String get perGameStreamProfile => _s('perGameStreamProfile');
  String get competitive => _s('competitive');
  String get visualQuality => _s('visualQuality');
  String get handheld => _s('handheld');
  String get bitrate => _s('bitrate');
  String get fpsLabel => _s('fps');
  String get videoCodec => _s('videoCodec');
  String get forceHdr => _s('forceHdr');
  String get showOnScreenControls => _s('showOnScreenControls');
  String get ultraLowLatency => _s('ultraLowLatency');
  String get performanceOverlayLabel => _s('performanceOverlay');
  String get frameRate => _s('frameRate');
  String get profileSaved => _s('profileSaved');
  String get overridesReset => _s('overridesReset');
  String presetApplied(String name) =>
      _s('presetApplied').replaceAll('{name}', name);
  String get watchTrailer => _s('watchTrailer');
  String trailerTitle(String name) => _s('trailerTitle').replaceAll('{name}', name);
  String get trailerSteamError => _s('trailerSteamError');
  String get exitFullscreen => _s('exitFullscreen');
  String get goBack => _s('goBack');
  String get fullscreen => _s('fullscreen');
  String get navConfirmBack => _s('navConfirmBack');
  String get streamQualityLabel => _s('streamQualityLabel');
  String get achievements => _s('achievements');
  String get achievements100 => _s('achievements100');
  String get achievementsPending => _s('achievementsPending');
  String get achievementsNeverStarted => _s('achievementsNeverStarted');
  String get vibepolloConfigApi => _s('vibepolloConfigApi');
  String get vibepolloInstructions => _s('vibepolloInstructions');
  String get username => _s('username');
  String get password => _s('password');

  String get multipleControllers => _s('multipleControllers');
  String get multipleControllersDesc => _s('multipleControllersDesc');
  String get hdrLabel => _s('hdrLabel');
  String get hdrDesc => _s('hdrDesc');
  String get readyStatus => _s('readyStatus');

  String get steamLibraryInfoName => _s('steamLibraryInfoName');
  String get steamLibraryInfoDesc => _s('steamLibraryInfoDesc');

  String get themeAndPerformance => _s('themeAndPerformance');
  String get reduceEffects => _s('reduceEffects');
  String get reduceEffectsDesc => _s('reduceEffectsDesc');
  String get performanceMode => _s('performanceMode');
  String get performanceModeDesc => _s('performanceModeDesc');
  String get inputTouch => _s('inputTouch');
  String get gamepadSection => _s('gamepadSection');
  String get keyboardSection => _s('keyboardSection');
  String get onScreenControls => _s('onScreenControls');
  String get aboutAndCredits => _s('aboutAndCredits');
  String get versionCredits => _s('versionCredits');
  String get gameMetadataVideos => _s('gameMetadataVideos');

  String get couldNotOpen => _s('couldNotOpen');
  String get welcomeToJujo => _s('welcomeToJujo');
  String get gotIt => _s('gotIt');

  String get runningStatus => _s('runningStatus');
  String get noResultsShort => _s('noResultsShort');
  String get playniteCategories => _s('playniteCategories');
  String get categoryLabel => _s('categoryLabel');
  String get genreLabel => _s('genreLabel');
  String get enableMetadataHint => _s('enableMetadataHint');
  String get smartFiltersExplain => _s('smartFiltersExplain');
  String get noGenresYet => _s('noGenresYet');
  String get genreAction => _s('genreAction');
  String get genreAdventure => _s('genreAdventure');
  String get genreFighting => _s('genreFighting');
  String get genrePlatform => _s('genrePlatform');
  String get genreCards => _s('genreCards');
  String get genreRogue => _s('genreRogue');
  String get genreRpg => _s('genreRpg');
  String get genreStrategy => _s('genreStrategy');
  String get genreSimulation => _s('genreSimulation');
  String get genreRacing => _s('genreRacing');
  String get genreSports => _s('genreSports');
  String get genrePuzzle => _s('genrePuzzle');
  String get genreHorror => _s('genreHorror');
  String get genreStealth => _s('genreStealth');
  String get mostPlayed => _s('mostPlayed');
  String get collectionFallback => _s('collectionFallback');
  String get noDescription => _s('noDescription');
  String get steamApiKeyHint => _s('steamApiKeyHint');
  String get accountLabel => _s('accountLabel');
  String get timePlayed => _s('timePlayed');
  String get last2Weeks => _s('last2Weeks');
  String get lastSessionLabel => _s('lastSessionLabel');
  String get releaseDate => _s('releaseDate');
  String get developerLabel => _s('developerLabel');
  String get metacriticLabel => _s('metacriticLabel');
  String get never => _s('never');
  String get todayLabel => _s('todayLabel');
  String get yesterdayLabel => _s('yesterdayLabel');
  String get justNow => _s('justNow');
  String get presetExplain => _s('presetExplain');
  String get competitiveSub => _s('competitiveSub');
  String get visualQualitySub => _s('visualQualitySub');
  String get balancedSub => _s('balancedSub');
  String get handheldSub => _s('handheldSub');
  String get customProfile => _s('customProfile');
  String get globalOnly => _s('globalOnly');
  String get launchCountLabel => _s('launchCountLabel');
  String get overridesLabelMeta => _s('overridesLabelMeta');
  String get unfav => _s('unfav');
  String get resetLabel => _s('resetLabel');
  String get closeSession => _s('closeSession');
  String get menuHint => _s('menuHint');
  String get settingsLabel => _s('settingsLabel');
  String get fav => _s('fav');

  String get configureFromPhone => _s('configureFromPhone');
  String get scanQrInstruction => _s('scanQrInstruction');
  String get qrDescription => _s('qrDescription');
  String get serverActiveNote => _s('serverActiveNote');
  String get noLocalIpError => _s('noLocalIpError');
  String serverStartError(String error) =>
      _s('serverStartError').replaceAll('{error}', error);

  String get appControlled => _s('appControlled');

  String get configureFromPhoneBtn => _s('configureFromPhoneBtn');
  String pluginEnabledSnack(String name) =>
      _s('pluginEnabledSnack').replaceAll('{name}', name);
  String pluginDisabledSnack(String name) =>
      _s('pluginDisabledSnack').replaceAll('{name}', name);
  String get videoDelayLabel => _s('videoDelayLabel');

  String get myProfile => _s('myProfile');
  String get changeAvatar => _s('changeAvatar');
  String get changeName => _s('changeName');
  String get chooseYourAvatar => _s('chooseYourAvatar');
  String get avatarNavHint => _s('avatarNavHint');
  String get yourName => _s('yourName');
  String get playerName => _s('playerName');
  String get totalTime => _s('totalTime');
  String get gamesLabel => _s('gamesLabel');
  String get sessionsLabel => _s('sessionsLabel');
  String get achievementsTitle => _s('achievementsTitle');
  String get achievementsSection => _s('achievementsSection');
  String get unlockedCount => _s('unlockedCount');
  String get recentSessions => _s('recentSessions');
  String get noSessionsYet => _s('noSessionsYet');
  String get playToSeeHistory => _s('playToSeeHistory');
  String get completedPercent => _s('completedPercent');

  String get myCollections => _s('myCollections');
  String get noCollections => _s('noCollections');
  String get createFirstCollection => _s('createFirstCollection');
  String get createCollection => _s('createCollection');
  String get newCollection => _s('newCollection');
  String get pipDesc => _s('pipDesc');
  String get deleteCollection => _s('deleteCollection');
  String get deleteCollectionConfirm => _s('deleteCollectionConfirm');
  String get renameCollection => _s('renameCollection');
  String get renameLabel => _s('renameLabel');
  String get collectionName => _s('collectionName');
  String get colorLabel => _s('colorLabel');
  String get selectCollection => _s('selectCollection');
  String get addToCollection => _s('addToCollection');
  String get addedToCollection => _s('addedToCollection');
  String get collectionNameHint => _s('collectionNameHint');
  String get gamesCount => _s('gamesCount');
  String get gameCount => _s('gameCount');

  String get resetDefaults => _s('resetDefaults');
  String get resetDefaultsConfirm => _s('resetDefaultsConfirm');
  String get yes => _s('yes');
  String get launcherAppearanceTitle => _s('launcherAppearanceTitle');

  String get applyingQuality => _s('applyingQuality');
  String get applyingPreset => _s('applyingPreset');
  String get reconnectingLabel => _s('reconnecting');

  String get smartBitrate => _s('smartBitrate');
  String get smartBitrateDesc => _s('smartBitrateDesc');
  String get smartBitrateMin => _s('smartBitrateMin');
  String get smartBitrateMax => _s('smartBitrateMax');
  String get smartBitrateMeasuring => _s('smartBitrateMeasuring');
  String smartBitrateResult(int valueMbps) =>
      _s('smartBitrateResult').replaceAll('{value}', '$valueMbps');

  String get editName => _s('editName');
  String get editPoster => _s('editPoster');
  String get customNameHint => _s('customNameHint');
  String get posterUrlHint => _s('posterUrlHint');
  String get overrideApplied => _s('overrideApplied');
  String get overrideCleared => _s('overrideCleared');
  String get clearOverride => _s('clearOverride');

  String get launcherThemeClassic => _s('launcherThemeClassic');
  String get launcherThemeClassicDesc => _s('launcherThemeClassicDesc');
  String get launcherThemeBackbone => _s('launcherThemeBackbone');
  String get launcherThemeBackboneDesc => _s('launcherThemeBackboneDesc');
  String get launcherThemePs5 => _s('launcherThemePs5');
  String get launcherThemePs5Desc => _s('launcherThemePs5Desc');
  String get launcherThemeHero => _s('launcherThemeHero');
  String get launcherThemeHeroDesc => _s('launcherThemeHeroDesc');
  String get launcherThemeLabel => _s('launcherThemeLabel');

  String get presAppearance => _s('presAppearance');
  String get presReset => _s('presReset');
  String get presResetConfirm => _s('presResetConfirm');
  String get presYes => _s('presYes');
  String get presSectionBackground => _s('presSectionBackground');
  String get presBlur => _s('presBlur');
  String get presOverlayDarkness => _s('presOverlayDarkness');
  String get presParallaxDrift => _s('presParallaxDrift');
  String get presParallaxDriftSub => _s('presParallaxDriftSub');
  String get presParallaxSpeed => _s('presParallaxSpeed');
  String get presParallaxSpeedSub => _s('presParallaxSpeedSub');
  String get presSectionCards => _s('presSectionCards');
  String get presBorderRadius => _s('presBorderRadius');
  String get presCardSpacing => _s('presCardSpacing');
  String get presCardWidth => _s('presCardWidth');
  String get presCardHeight => _s('presCardHeight');
  String get presShowGameName => _s('presShowGameName');
  String get presRunningIndicator => _s('presRunningIndicator');
  String get presRunningIndicatorSub => _s('presRunningIndicatorSub');
  String get presSectionCategoryBar => _s('presSectionCategoryBar');
  String get presShowFilterBar => _s('presShowFilterBar');
  String get presFilterBarSub => _s('presFilterBarSub');
  String get presShowCounts => _s('presShowCounts');
  String get presShowCountsSub => _s('presShowCountsSub');
  String get presSectionSearch => _s('presSectionSearch');
  String get presInstantSearch => _s('presInstantSearch');
  String get presInstantSearchSub => _s('presInstantSearchSub');
  String get themeOptions => _s('themeOptions');
  String get launcherThemeDesc => _s('launcherThemeDesc');
  String get colorSchemeLabel => _s('colorSchemeLabel');
  String get colorSchemeDesc => _s('colorSchemeDesc');
  String get remoteAccessVpn => _s('remoteAccessVpn');
  String get remoteAccessVpnDesc => _s('remoteAccessVpnDesc');
  String get artQualityLabel => _s('artQualityLabel');
  String get artQualityHigh => _s('artQualityHigh');
  String get artQualityMedium => _s('artQualityMedium');
  String get artQualityLow => _s('artQualityLow');
  String get proUpsellTitle => _s('proUpsellTitle');
  String get proUpsellSubtitle => _s('proUpsellSubtitle');
  String get proUpsellBenefit1 => _s('proUpsellBenefit1');
  String get proUpsellBenefit2 => _s('proUpsellBenefit2');
  String get proUpsellBenefit3 => _s('proUpsellBenefit3');
  String get proUpsellBenefit4 => _s('proUpsellBenefit4');
  String get proUpsellBenefit5 => _s('proUpsellBenefit5');
  String get proUpsellBenefit6 => _s('proUpsellBenefit6');
  String get proUpsellCta => _s('proUpsellCta');
  String get proUpsellLater => _s('proUpsellLater');
  String get favoritesLimitReached => _s('favoritesLimitReached');
  String get pluginRemove => _s('pluginRemove');
  String get pluginSelectVideo => _s('pluginSelectVideo');
  String get pluginVideoSaved => _s('pluginVideoSaved');
  String get pluginSteamLoginFirst => _s('pluginSteamLoginFirst');
  String get pluginSteamLogin => _s('pluginSteamLogin');
  String get pluginSteamConnecting => _s('pluginSteamConnecting');
  String get pluginSteamAccount => _s('pluginSteamAccount');
  String get pluginVideoHint => _s('pluginVideoHint');
  String get pluginVideoWhen => _s('pluginVideoWhen');
  String get pluginVideoTriggerApp => _s('pluginVideoTriggerApp');
  String get pluginVideoTriggerServer => _s('pluginVideoTriggerServer');
  String get pluginStartMuted => _s('pluginStartMuted');
  String get pluginVideoDelay => _s('pluginVideoDelay');
  String get pluginSteamValidationFailed => _s('pluginSteamValidationFailed');
  String get pluginSteamConnectedMsg => _s('pluginSteamConnectedMsg');
  String get pluginSteamLinkedPrivate => _s('pluginSteamLinkedPrivate');
  String unlockedOf(int unlocked, int total) =>
      '$unlocked / $total ${_s('unlockedCount')}';
  String completedPercentLabel(double pct) =>
      '${pct.toStringAsFixed(0)}% ${_s('completedPercent')}';
  String daysAgo(int n) =>
      locale.languageCode == 'es' ? 'Hace $n días' : '$n days ago';
  String monthsAgo(int n) =>
      locale.languageCode == 'es' ? 'Hace $n meses' : '$n months ago';
  String yearsAgo(int n) =>
      locale.languageCode == 'es' ? 'Hace $n año(s)' : '$n year(s) ago';
  String minutesAgo(int n) =>
      locale.languageCode == 'es' ? 'Hace $n min' : '$n min ago';
  String hoursAgo(int n) =>
      locale.languageCode == 'es' ? 'Hace $n h' : '$n h ago';
  String daysAgoShort(int n) =>
      locale.languageCode == 'es' ? 'Hace $n d' : '$n d ago';
  String achievementsProgress(int unlocked, int total) =>
      locale.languageCode == 'es'
      ? 'Logros: $unlocked / $total'
      : 'Achievements: $unlocked / $total';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'es'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
