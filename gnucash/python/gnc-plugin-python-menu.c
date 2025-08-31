#include <gtk/gtk.h>
#include <glib/gi18n.h>
#include <Python.h>
#include <stdio.h>

#include "gnc-plugin-python-menu.h"
#include "gnc-main-window.h"
#include "gnc-plugin-page.h"
#include "gnucash/gnome/gnc-plugin-page-report.h"

static void gnc_plugin_python_menu_class_init (GncPluginPythonMenuClass *klass);
static void gnc_plugin_python_menu_init (GncPluginPythonMenu *plugin);
static void gnc_plugin_python_menu_finalize (GObject *object);

/* Command callbacks */
static void gnc_plugin_python_cmd_test_report (GSimpleAction *simple, GVariant *parameter, gpointer user_data);
static void gnc_plugin_python_open_exiting_report_tab(GSimpleAction *simple, GVariant *parameter, gpointer user_data);

#define PLUGIN_ACTIONS_NAME "gnc-plugin-python-menu-actions"
#define PLUGIN_UI_FILENAME  "gnc-plugin-python-menu.ui"

// we'll use this in plugin init to wire the menu item Action to the actual function
static GActionEntry gnc_plugin_actions [] = {
    { "TestPythonCallAction", gnc_plugin_python_cmd_test_report, NULL, NULL, NULL },
    { "PythonTestExistingReportAction", gnc_plugin_python_open_exiting_report_tab, NULL, NULL, NULL },
};
static guint gnc_plugin_n_actions = G_N_ELEMENTS (gnc_plugin_actions);

static const gchar *gnc_plugin_load_ui_items [] = {
    "PythonPlaceholder0",
    NULL,
};

struct _GncPluginPythonMenu {
    GncPluginClass gnc_plugin;
};

// this is our entrypoint: we're creating a GncPlugin and calling this from gncmod-python to register the plugin
GncPlugin *
gnc_plugin_python_menu_new (void)
{
    // this will call into gnc_plugin_python_menu_class_init() through some gnc magic
    return GNC_PLUGIN (g_object_new (GNC_TYPE_PLUGIN_PYTHON_MENU, NULL));
}

G_DEFINE_TYPE(GncPluginPythonMenu, gnc_plugin_python_menu, GNC_TYPE_PLUGIN)

static void
gnc_plugin_python_menu_class_init (GncPluginPythonMenuClass *klass)
{
    // instantiate our empty classes
    GObjectClass *object_class = G_OBJECT_CLASS (klass);
    GncPluginClass *plugin_class = GNC_PLUGIN_CLASS (klass);
    
    object_class->finalize = gnc_plugin_python_menu_finalize;
    plugin_class->plugin_name   = GNC_PLUGIN_PYTHON_MENU_NAME;

    // key update are gnc_plugin_load_ui_items(), and gnc_plugin_actions map
    plugin_class->actions_name    = PLUGIN_ACTIONS_NAME;
    plugin_class->actions         = gnc_plugin_actions;
    plugin_class->n_actions       = gnc_plugin_n_actions;
    plugin_class->ui_filename     = PLUGIN_UI_FILENAME;
    plugin_class->ui_updates      = gnc_plugin_load_ui_items;
}

static void
gnc_plugin_python_menu_init (GncPluginPythonMenu *plugin) {}

static void
gnc_plugin_python_menu_finalize (GObject *object)
{
    G_OBJECT_CLASS (gnc_plugin_python_menu_parent_class)->finalize (object);
}

// menu action callback to open an existing report
static void
gnc_plugin_python_open_exiting_report_tab(GSimpleAction *simple, GVariant *parameter, gpointer user_data) {
   // get main window
    GncMainWindowActionData *mw = user_data;
    g_return_if_fail (mw != NULL);

    // open exiting report in main window
    gnc_main_window_open_report(0, mw->window);
}

// menu action callback to run the Python report
static void
gnc_plugin_python_cmd_test_report (GSimpleAction *simple, GVariant *parameter, gpointer user_data)
{
    PyGILState_STATE gstate;
    PyObject *module, *function, *result;

    /* Acquire the GIL */
    gstate = PyGILState_Ensure();

    /* Import the pyreports module */
    module = PyImport_ImportModule("pyreports");
    if (module == NULL) {
        fprintf(stderr, "Failed to import pyreports module");
        if (PyErr_Occurred()) {
            PyErr_Print();
        }
        PyGILState_Release(gstate);
        return;
    }

    /* Get the render_test_html function */
    function = PyObject_GetAttrString(module, "render_test_html");
    if (function == NULL || !PyCallable_Check(function)) {
        fprintf(stderr, "render_test_html function not found or not callable");
        if (PyErr_Occurred()) {
            PyErr_Print();
        }
        Py_DECREF(module);
        PyGILState_Release(gstate);
        return;
    }

    /* Call the function */
    result = PyObject_CallObject(function, NULL);
    if (result == NULL) {
        fprintf(stderr, "Error calling render_test_html function");
        if (PyErr_Occurred()) {
            PyErr_Print();
        }
    } else {
        /* Convert result to string and print */
        PyObject* str_result = PyObject_Str(result);
        if (str_result) {
            const char* html_output = PyUnicode_AsUTF8(str_result);
            fprintf(stdout, "Python menu triggered! Function returned: %s\n", html_output);
            fflush(stdout);
            Py_DECREF(str_result);
        }
        Py_DECREF(result);
    }

    /* Cleanup */
    Py_DECREF(function);
    Py_DECREF(module);

    /* Release the GIL */
    PyGILState_Release(gstate);
}
