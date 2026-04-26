import re
import sys

content = open("lib/screens/settings/settings_screen.dart", "r", encoding="utf-8").read()

build_start = content.find("  @override\n  Widget build(BuildContext context) {")
if build_start == -1:
    build_start = content.find("  Widget build(BuildContext context) {")

brace_count = 0
build_end = -1
in_build = False

for i in range(build_start, len(content)):
    if content[i] == '{':
        if not in_build:
            in_build = True
        brace_count += 1
    elif content[i] == '}':
        brace_count -= 1
        if in_build and brace_count == 0:
            build_end = i + 1
            break

build_method = content[build_start:build_end]

listview_children_start = build_method.find("children: [") + len("children: [")
listview_children_end = build_method.find("                  ],\n                ),", listview_children_start)
if listview_children_end == -1:
    listview_children_end = build_method.rfind("                  ],\n                )")
if listview_children_end == -1:
    listview_children_end = build_method.rfind("                  ]")

children_content = build_method[listview_children_start:listview_children_end]

sections = {
    'personalization': [],
    'video_audio': [],
    'controller': [],
    'desktop': [],
    'labs': []
}

current_section = 'personalization'
lines = children_content.split('\n')
for line in lines:
    if "_section(" in line:
        if "'Appearance'" in line or "'Ambience'" in line or "'Language" in line:
            current_section = 'personalization'
        elif "'Performance & Quality'" in line or "'Video'" in line or "'Audio'" in line:
            current_section = 'video_audio'
        elif "'Input / Touch'" in line or "'Keyboard'" in line or "'Gamepad'" in line or "'On-Screen Controls'" in line:
            current_section = 'controller'
        elif "'Desktop'" in line:
            current_section = 'desktop'
        elif "'Network" in line or "'Debug" in line or "'Advanced'" in line or "'Host'" in line or "'Plugins'" in line or "'Collections'" in line or "'About'" in line:
            current_section = 'labs'
        
    sections[current_section].append(line)

sections['desktop'].append("                    _section(_tr(context, 'Desktop', 'Escritorio')),")
sections['desktop'].append("                    _toggle(")
sections['desktop'].append("                      _tr(context, 'Allow Fullscreen', 'Permitir pantalla completa'),")
sections['desktop'].append("                      _tr(context, 'App starts in borderless fullscreen mode', 'La app inicia en modo pantalla completa sin bordes'),")
sections['desktop'].append("                      preferences.desktopFullscreen,")
sections['desktop'].append("                      (v) => preferences.setDesktopFullscreen(v),")
sections['desktop'].append("                    ),")

new_app_bar = """        appBar: AppBar(
          title: Text(
            l.settings,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: cardBg,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
            tabs: [
              Tab(text: _tr(context, 'Personalization', 'Personalización')),
              Tab(text: _tr(context, 'Video & Audio', 'Video y Audio')),
              Tab(text: _tr(context, 'Controller', 'Mando')),
              Tab(text: _tr(context, 'Desktop', 'Escritorio')),
              Tab(text: _tr(context, 'Labs', 'Laboratorios')),
            ],
          ),
        ),"""

def make_tab_view(content_lines):
    return """                  FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: ListView(
                      padding: const EdgeInsets.only(top: 16, bottom: 160),
                      children: [
""" + "\\n".join(content_lines) + """
                      ],
                    ),
                  ),"""

tab_views = [
    make_tab_view(sections['personalization']),
    make_tab_view(sections['video_audio']),
    make_tab_view(sections['controller']),
    make_tab_view(sections['desktop']),
    make_tab_view(sections['labs']),
]

new_build_method = build_method[:build_method.find("      child: Scaffold(")] + f"""      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          backgroundColor: bg,
{new_app_bar}
          body: SafeArea(
            top: false,
            bottom: false,
            child: Consumer<SettingsProvider>(
              builder: (context, settings, _) {{
                final c = settings.config;
                final themeProvider = context.watch<ThemeProvider>();
                final preferences = context.watch<LauncherPreferences>();

                return TabBarView(
                  children: [
{tab_views[0]}
{tab_views[1]}
{tab_views[2]}
{tab_views[3]}
{tab_views[4]}
                  ],
                );
              }},
            ),
          ),
        ),
      ),
    );
  }}"""

content = content[:build_start] + new_build_method + content[build_end:]

open("lib/screens/settings/settings_screen.dart", "w", encoding="utf-8").write(content)
print("Settings UI replaced!")
