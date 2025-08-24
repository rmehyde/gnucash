#ifndef __GNC_PLUGIN_PYTHON_MENU_H
#define __GNC_PLUGIN_PYTHON_MENU_H

#include <gtk/gtk.h>
#include "gnc-plugin.h"

G_BEGIN_DECLS

/* type macros */
#define GNC_TYPE_PLUGIN_PYTHON_MENU            (gnc_plugin_python_menu_get_type ())
G_DECLARE_FINAL_TYPE(GncPluginPythonMenu, gnc_plugin_python_menu, GNC, PLUGIN_PYTHON_MENU, GncPlugin)

#define GNC_PLUGIN_PYTHON_MENU_NAME "gnc-plugin-python-menu"

/* function prototypes */

GncPlugin *gnc_plugin_python_menu_new (void);

G_END_DECLS

#endif /* __GNC_PLUGIN_PYTHON_MENU_H */