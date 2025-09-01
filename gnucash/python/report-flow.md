# GnuCash Report System Architecture

## Executive Summary

The GnuCash report system implements a **dual-language architecture** where Scheme defines report logic and menu structure while C manages UI integration and display. The system employs two distinct interface patterns: **Extension objects** (menu items) are decomposed from Scheme records into C structs for native processing, while **Report objects** (report instances) remain as opaque Scheme objects in a C-managed registry. This architecture enables dynamic report generation while maintaining clean separation between business logic (Scheme) and presentation layer (C/GTK).

## System Architecture

### Core Components

The report system consists of five interconnected subsystems that bridge Scheme and C:

**Report Definition Layer (Scheme)**
- **Report Templates:** [`report-core.scm`](../report/report-core.scm) - Define report types with renderers, options, and metadata
- **Menu Extensions:** [`gnc-menu-extensions.scm`](../gnome-utils/gnc-menu-extensions.scm) - Create menu item definitions as Extension records
- **Menu Setup:** [`report-menus.scm`](../gnome/report-menus.scm) - Generate menu hierarchy from report templates

**Integration Layer (C/Scheme Bridge)**
- **Extension Bridge:** [`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c) - Convert Extension records to C structs
- **Report Registry:** [`gnc-report.cpp`](../report/gnc-report.cpp) - Store and retrieve Scheme Report objects by ID
- **URL Handlers:** [`gnc-plugin-report-system.c`](../gnome/gnc-plugin-report-system.c) - Register stream handlers for report URLs

**Presentation Layer (C/GTK)**
- **Menu Plugin:** [`gnc-plugin-menu-additions.c`](../gnome-utils/gnc-plugin-menu-additions.c) - Display Scheme-generated menus in GTK
- **Report Tabs:** [`gnc-plugin-page-report.cpp`](../gnome/gnc-plugin-page-report.cpp) - Manage report display windows
- **HTML Widget:** [`gnc-html-webkit2.c`](../html/gnc-html-webkit2.c) - Render HTML content via WebKit

### Interface Patterns

The system uses two fundamentally different patterns for bridging Scheme and C:

| Pattern | Object Type | Scheme→C | C Storage | C→Scheme |
|---------|------------|----------|-----------|----------|
| **Decomposition** | Extension (menus) | Fields extracted to C struct | Native C data + protected SCM | Callback via original SCM |
| **Opaque Registry** | Report (instances) | No extraction | Hash table of SCM objects | Direct SCM passing |

This dual approach optimizes each object type: Extensions need C-native data for GTK menu creation, while Reports remain in Scheme for complex business logic execution.

## Data Model

### Scheme Record Types

**Extension Records** define menu items and get decomposed into C:

```scheme
(define-record-type :extension
  (gnc:make-extension type name guid documentation-string path script)
  :extension?
  (type gnc:extension-type)           ; Symbol: 'menu-item, 'menu, 'separator
  (name gnc:extension-name)           ; String: Display name
  (guid gnc:extension-guid)           ; String: Unique identifier
  (documentation-string gnc:extension-documentation) ; String: Tooltip
  (path gnc:extension-path)           ; List: Menu hierarchy
  (script gnc:extension-script))      ; Procedure: Click callback
```

**Report Records** represent report instances and remain opaque to C:

```scheme
(define-record-type <report>
  (make-report type id options dirty? needs-save? 
               editor-widget ctext custom-template anchors)
  report?
  (type report-type)                  ; String: Template GUID
  (id report-id)                      ; Integer: Instance ID
  (options report-options)            ; Object: Configuration
  (dirty? report-dirty?)              ; Boolean: Needs re-render
  ...)
```

### C Data Structures

**ExtensionInfo Struct** holds decomposed Extension data:

```c
typedef struct {
    gchar *name;                    // Extracted via gnc:extension-name
    gchar *guid;                    // Extracted via gnc:extension-guid
    gchar *documentation_string;    // Extracted via gnc:extension-documentation
    gchar *path;                    // Converted from Scheme list
    SCM extension;                  // Original Scheme object (GC-protected)
} ExtensionInfo;
```

**Report Registry** stores opaque Report objects:

```c
static GHashTable *reports;        // Maps int* → SCM report
```

## System Initialization

The report system initializes during GnuCash startup through a carefully orchestrated sequence that establishes URL handlers before creating menus:

### Handler Registration Phase

`gnc_plugin_report_system_new` ([`gnc-plugin-report-system.c`](../gnome/gnc-plugin-report-system.c)`L273`) establishes the URL handling infrastructure:

1. **Stream Handler Registration** (L282-284): Maps URL types to content generators
   ```c
   gnc_html_register_stream_handler(URL_TYPE_REPORT, gnc_report_system_report_stream_cb);
   ```
   This creates: `"report"` → `gnc_report_system_report_stream_cb` in the global handler registry

2. **URL Handler Registration** (L286-288): Maps URL types to action handlers
   ```c
   gnc_html_register_url_handler(URL_TYPE_REPORT, gnc_report_system_report_url_cb);
   ```

### Menu Generation Phase

After handlers are registered, the system loads Scheme modules and generates menus:

1. **Module Loading** (L290-292): Loads report modules and calls `gnc:report-menu-setup` ([`report-menus.scm`](../gnome/report-menus.scm)`L70`)
   - TODO: lines where??
2. **Template Processing**: Scheme iterates through all registered report templates
3. **Extension Creation**: Each template generates an Extension record with menu metadata
4. **C Registration**: Extensions are converted to C structs via `gnc_add_scm_extension` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L334`)

## Menu Generation Flow

### Template to Extension Conversion

`gnc:report-menu-setup` ([`report-menus.scm`](../gnome/report-menus.scm)`L70-121`) orchestrates menu creation from report templates:

1. **Category Creation** (L71-86): Creates submenus for report categories (Assets, Income, Budget, etc.)
2. **Template Iteration** (L111): Calls `gnc:add-report-template-menu-items` ([`report-menus.scm`](../gnome/report-menus.scm)`L42-68`)
3. **Extension Generation** (L61-66): For each template, creates Extension with callback:
   ```scheme
   (gnc:make-menu-item
     (gnc:report-template-name template)
     (lambda (window)
       (gnc-main-window-open-report 
         (gnc:make-report template-guid) window)))
   ```

### Scheme to C Conversion

`gnc_add_scm_extension` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L334-341`) converts Extension records to C structs:

1. **Field Extraction**: Uses cached Scheme accessor functions to extract each field
2. **Type Conversion**: Converts Scheme types to C types:
   - Strings via `gnc_scm_call_1_to_string` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L119`)
   - Symbols via `gnc_scm_call_1_symbol_to_string` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L83`)
   - Procedures remain as SCM objects
3. **Memory Management**: Protects original Scheme object with `scm_gc_protect_object`
4. **Storage**: Adds `ExtensionInfo` ([`gnc-menu-extensions.h`](../gnome-utils/gnc-menu-extensions.h)`L35`) to global list

### GTK Menu Creation

The menu additions plugin ([`gnc-plugin-menu-additions.c`](../gnome-utils/gnc-plugin-menu-additions.c)) processes C structs into GTK menus:

1. **Extension Retrieval** (L487): Gets list of `ExtensionInfo` structs
2. **Menu Building** (L412-450): Creates GTK menu items from C struct fields
3. **Action Registration** (L422): Stores Extension callbacks in hash table by action name
4. **Menu Display** (L500-510): Inserts menu into "ReportsPlaceholder0" location

## Execution Flow

### Menu Click to Report Display

When a user clicks a report menu item, execution flows through multiple layers:

1. **GTK Action Dispatch**: `gnc_plugin_menu_additions_action_new_cb` ([`gnc-plugin-menu-additions.c`](../gnome-utils/gnc-plugin-menu-additions.c)`L173-199`)
2. **Extension Retrieval**: Looks up original Scheme Extension from hash table
3. **Scheme Callback**: `gnc_extension_invoke_cb` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L244-252`) executes callback
4. **Report Creation**: Callback calls `gnc:make-report` ([`report-core.scm`](../report/report-core.scm)) creating Report instance
5. **C Registration**: `gnc_report_add` ([`gnc-report.cpp`](../report/gnc-report.cpp)`L149-189`) stores Report in registry
6. **Tab Opening**: `gnc_main_window_open_report` ([`gnc-plugin-page-report.cpp`](../gnome/gnc-plugin-page-report.cpp)`L2102-2111`) creates display tab

### Tab to HTML Pipeline

Report tabs automatically trigger HTML generation through the URL system:

1. **URL Construction**: Tab creates `gnc-report:id=123` URL via `gnc_build_url` ([`gnc-plugin-page-report.cpp`](../gnome/gnc-plugin-page-report.cpp)`L558`)
2. **URL Loading**: `gnc_html_show_url` ([`gnc-plugin-page-report.cpp`](../gnome/gnc-plugin-page-report.cpp)`L449`) loads URL in HTML widget
3. **Handler Dispatch**: `load_to_stream` ([`gnc-html-webkit2.c`](../html/gnc-html-webkit2.c)`L482-490`) looks up stream handler
4. **Stream Handler**: `gnc_report_system_report_stream_cb` ([`gnc-plugin-report-system.c`](../gnome/gnc-plugin-report-system.c)`L151`) executes
5. **Report Rendering**: Handler calls `gnc_run_report_with_error_handling` ([`gnc-report.cpp`](../report/gnc-report.cpp)`L222`)
6. **Scheme Execution**: Calls `gnc:render-report` → `gnc:report-render-html` ([`report-core.scm`](../report/report-core.scm))
7. **HTML Return**: Scheme renderer generates HTML, returns to C as UTF-8 string

## Scheme/C Interface Mechanics

### Extension Object Decomposition

C extracts fields from Scheme Extension records using cached accessor functions:

**Accessor Cache** (`initialize_getters` in [`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L58-73`):
```c
static struct {
    SCM type, name, guid, documentation, path, script;
} getters;
getters.name = scm_c_eval_string("gnc:extension-name");
```

**Field Extraction** (`gnc_create_extension_info` in [`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L257-314`):
1. Calls Scheme accessor with Extension object
2. Converts result to C type
3. Stores in `ExtensionInfo` struct ([`gnc-menu-extensions.h`](../gnome-utils/gnc-menu-extensions.h)`L35`)
4. Protects original Scheme object from GC

### Report Object Registry

C maintains Report objects as opaque Scheme values:

**Storage** (`gnc_report_add` in [`gnc-report.cpp`](../report/gnc-report.cpp)`L149-189`):
```c
g_hash_table_insert(reports, key, (gpointer)report);
scm_gc_protect_object(report);
```

**Retrieval** (`gnc_report_find` in [`gnc-report.cpp`](../report/gnc-report.cpp)`L124-145`):
```c
return (SCM)g_hash_table_lookup(reports, &id);
```

### SWIG Object Wrapping

C pointers become opaque Scheme objects via SWIG:

**Window Wrapping** (`gnc_main_window_to_scm` in [`gnc-plugin-menu-additions.c`](../gnome-utils/gnc-plugin-menu-additions.c)`L157-171`):
```c
static swig_type_info * main_window_type = 
    SWIG_TypeQuery("_p_GncMainWindow");
return SWIG_NewPointerObj(window, main_window_type, 0);
```

This allows Scheme callbacks to receive and pass C objects without understanding their structure.

### Memory Management

**Extension Objects**:
- C strings: Allocated with `g_malloc`, freed in `cleanup_extension_info` ([`gnc-menu-extensions.c`](../gnome-utils/gnc-menu-extensions.c)`L317-330`)
- Scheme objects: Protected/unprotected with `scm_gc_protect_object`/`scm_gc_unprotect_object`
- Lifetime: Menu system lifetime

**Report Objects**:
- Hash keys: Integer pointers via `g_new(gint, 1)`
- Scheme objects: Protected while in registry
- Lifetime: Report instance lifetime

**SWIG Objects**:
- Managed by SWIG runtime
- No explicit cleanup needed

## Key Design Insights

### Architectural Decisions

1. **Dual Interface Pattern**: Extensions are decomposed for efficient C processing (menu creation), while Reports remain opaque for complex Scheme logic (report generation)

2. **URL System Bridge**: Report tabs don't directly call renderers - they generate URLs that trigger registered handlers, providing clean separation and enabling URL-based navigation

3. **Registry Pattern**: C acts as a registry service for Report objects, providing ID-based storage without understanding Report internals

4. **Cached Accessors**: Scheme accessor functions are cached once and reused, avoiding repeated string evaluation

### Abstraction Boundaries

The system maintains clear boundaries between concerns:

- **Scheme Domain**: Report logic, template definitions, rendering algorithms
- **C Domain**: UI management, GTK integration, URL routing, HTML display
- **Bridge Layer**: Extension decomposition, Report registry, SWIG wrapping

This separation enables independent evolution of report logic and UI infrastructure while maintaining stable interfaces.