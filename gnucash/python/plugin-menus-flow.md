# Plugin Menu Integration Flow

## High-Level Overview

GnuCash uses a plugin architecture where loadable modules can extend the main application with new menus, actions, and functionality. Plugins define menu structures in UI XML files and implement corresponding action callbacks in C code. The main application integrates these plugin menus into the main window menu bar through a placeholder/merge system managed by the plugin manager.

**Complete Integration Requirements:**
1. **Main Window Setup:** Define top-level menu action and UI placeholders  
2. **Plugin Implementation:** Define actions, UI filename, window callbacks, and UI updates array
3. **Plugin UI Definition:** Create UI XML targeting main window placeholders
4. **GResources Integration:** Embed UI files in binary via build system
5. **Signal Callbacks:** Implement page/menu change handlers that enable plugin actions
6. **Action Registration:** Use plugin manager to register and enable actions in main window

**Key Components:**
- **GResources System:** [`gnucash/CMakeLists.txt`](../../gnucash/CMakeLists.txt) L55-81 embeds UI files into binary via `gnucash_GRESOURCES` 
- **Main Window Structure:** [`gnc-main-window.ui`](../../gnucash/ui/gnc-main-window.ui) defines menu placeholders 
- **Main Window Actions:** [`gnc-main-window.cpp`](../../gnucash/gnome-utils/gnc-main-window.cpp) L285-323 defines placeholder actions
- **Plugin Manager:** Handles registration, window integration, and action merging

## Existing Pattern: Business Plugin

The Business plugin demonstrates the existing working menu integration pattern that was used as the reference implementation:

**1. Main Window Setup:**
- [`gnc-main-window.ui`](../../gnucash/ui/gnc-main-window.ui) L356-387 defines Business submenu with placeholders:
  - `mainwin.BusinessAction` (no-op action for top-level menu)
  - `mainwin.BusinessPlaceholder0`, `BusinessPlaceholder1`, etc. (merge points for plugin content)

**2. Plugin Implementation:**
- [`gnc-plugin-business.c`](../../gnucash/gnome/gnc-plugin-business.c) L108-223 defines complete plugin structure:
  - `gnc_plugin_actions[]` array with customer/vendor/employee actions
  - `plugin_class->ui_filename = "gnc-plugin-business.ui"`
  - `plugin_class->add_to_window = gnc_plugin_business_add_to_window`
  - `plugin_class->ui_updates = gnc_plugin_load_ui_items` (critical for UI merging)

**3. Plugin UI Definition:**
- [`gnc-plugin-business.ui`](../../gnucash/ui/gnc-plugin-business.ui) defines menu structure:
  - Uses `<menu id="BusinessPlaceholder0">` to merge into main window placeholder
  - Menu items reference actions like `gnc-plugin-business-actions.CustomerNewCustomerOpenAction`

**4. Signal Callbacks:**
- [`add_to_window`](../../gnucash/gnome/gnc-plugin-business.c) L1000-1011 connects to window signals
- [`page_changed`](../../gnucash/gnome/gnc-plugin-business.c) L789-795 calls menu update functions
- [`update_menus`](../../gnucash/gnome/gnc-plugin-business.c) L750-786 enables actions via `gnc_plugin_set_actions_enabled`

**5. UI Updates Array:**
- [`gnc_plugin_load_ui_items`](../../gnucash/gnome/gnc-plugin-business.c) L735-742 specifies which placeholders to merge
- Critical for telling plugin manager where to integrate UI elements

## Python Plugin Implementation

Following the Business plugin pattern, the Python plugin implements:

**1. Main Window Integration:**
- Added [`PythonAction`](../../gnucash/gnome-utils/gnc-main-window.cpp) L313 as no-op action
- Added Python submenu with [`PythonPlaceholder0`](../../gnucash/ui/gnc-main-window.ui) L444-453

**2. Plugin Structure:**
- [`gnc-plugin-python-menu.c`](../../gnucash/python/gnc-plugin-python-menu.c) implements complete plugin class:
  - Actions array with `PythonTestReportAction`
  - UI filename and action namespace configuration
  - `add_to_window` function with signal callbacks
  - **UI updates array specifying `PythonPlaceholder0`** (essential for UI merging)

**3. Signal Callback System:**
- `add_to_window`: Connects to `page_changed` and `menu_changed` signals
- `page_changed`: Calls `gnc_plugin_python_update_menus`
- `update_menus`: Gets action group and enables actions via `gnc_plugin_set_actions_enabled`

**4. UI Integration:**
- [`gnc-plugin-python-menu.ui`](../../gnucash/ui/gnc-plugin-python-menu.ui) targets `PythonPlaceholder0`
- Embedded via [`gnucash_GRESOURCES`](../../gnucash/CMakeLists.txt) L70
- Registered via [`gncmod-python.c`](../../gnucash/python/gncmod-python.c) L111

**Essential Components:**

**UI Updates Array:**
```c
static const gchar *gnc_plugin_load_ui_items [] = {
    "PythonPlaceholder0",
    NULL,
};
plugin_class->ui_updates = gnc_plugin_load_ui_items;
```

**Action Enabling:**
```c
gnc_plugin_set_actions_enabled (G_ACTION_MAP(simple_action_group), python_actions, TRUE);
```

**Signal Callback Chain:**
Complete callback chain: `add_to_window` → signal connections → `page_changed` → `update_menus` → action enabling.

## Integration Mechanism

**Plugin Registration Flow:**
1. Module loads → Plugin manager registers plugin globally
2. Main window created → Plugin manager calls `add_to_window` for each registered plugin
3. `add_to_window` connects to window signals (`page_changed`, `menu_changed`)
4. Window signals fire → Callbacks trigger `update_menus`
5. `update_menus` gets plugin action group and enables actions
6. UI merging occurs based on `ui_updates` array specification
7. Menu items become visible and functional

The Business plugin works because it implements every step of this chain. The Python plugin initially failed because it was missing the `ui_updates` array and action enabling steps.