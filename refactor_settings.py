import sys
import re

content = open("lib/screens/settings/settings_screen.dart", "r", encoding="utf-8").read()

# We need to replace the scaffolding around ListView.

# Find the start of the Scaffold
scaffold_start = content.find("child: Scaffold(")
if scaffold_start == -1:
    print("Scaffold not found")
    sys.exit(1)

scaffold_end_match = re.search(r"        \),\n      \),\n    \);", content)
if not scaffold_end_match:
    print("Scaffold end not found")
    sys.exit(1)
scaffold_end = scaffold_end_match.end()

listview_start = content.find("child: ListView(", scaffold_start)
listview_end_match = re.search(r"                \),\n              \);\n            \},\n          \),\n        \),\n      \),\n    \);", content)

listview_children_start = content.find("children: [", listview_start) + len("children: [")
listview_children_end = content.find("                ],\n              ),", listview_children_start)

children_content = content[listview_children_start:listview_children_end]

# Split children by sections
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
        elif "'Network" in line or "'Debug" in line or "'Advanced'" in line:
            current_section = 'labs'
        
    sections[current_section].append(line)

# Add "Desktop" settings (Allow fullscreen)
sections['desktop'].append("                    _section(_tr(context, 'Desktop', 'Escritorio')),")
sections['desktop'].append("                    _toggle(")
sections['desktop'].append("                      _tr(context, 'Allow Fullscreen', 'Permitir pantalla completa'),")
sections['desktop'].append("                      _tr(context, 'App starts in borderless fullscreen mode', 'La app inicia en modo pantalla completa sin bordes'),")
sections['desktop'].append("                      preferences.desktopFullscreen,")
sections['desktop'].append("                      (v) => preferences.setDesktopFullscreen(v),")
sections['desktop'].append("                    ),")

# Build the new Tabs UI
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

new_scaffold = f"""      child: DefaultTabController(
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
      ),"""

content = content[:scaffold_start - 13] + new_scaffold + content[listview_end_match.end() - 7:]

open("lib/screens/settings/settings_screen.dart", "w", encoding="utf-8").write(content)
print("Settings screen refactored.")
