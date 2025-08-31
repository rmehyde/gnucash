#include <gtk/gtk.h>
#include <glib/gi18n.h>
#include <Python.h>
#include <stdio.h>

#include "gnc-plugin-python-menu.h"
#include "gnc-main-window.h"
#include "gnc-plugin-page.h"
#include "gnucash/gnome/gnc-plugin-page-report.h"
#include "gnucash/html/gnc-html.h"
#include "gnc-plugin-page-pyreport.h"

static void gnc_plugin_python_menu_class_init (GncPluginPythonMenuClass *klass);
static void gnc_plugin_python_menu_init (GncPluginPythonMenu *plugin);
static void gnc_plugin_python_menu_finalize (GObject *object);

void gnc_main_window_open_pyreport(const char *template_uuid, GncMainWindow *window);

// Python report HTML generation
static char* gnc_plugin_python_get_report_html (const char *template_uuid, char **error);

// url handler callbacks
static gboolean gnc_python_report_stream_cb (const char *location, char ** data, int *len);
static gboolean gnc_python_report_url_cb (const char *location, const char *label, gboolean new_window, GNCURLResult *result);

/* Command callbacks */
static void gnc_plugin_python_cmd_test_report (GSimpleAction *simple, GVariant *parameter, gpointer user_data);
static void gnc_plugin_python_open_exiting_report_tab(GSimpleAction *simple, GVariant *parameter, gpointer user_data);

/* Python Plumbing */
static char *pyerr_to_string(void);

#define PLUGIN_ACTIONS_NAME "gnc-plugin-python-menu-actions"
#define PLUGIN_UI_FILENAME  "gnc-plugin-python-menu.ui"

// we'll use this in plugin init to wire the menu item Action to the actual function
static GActionEntry gnc_plugin_actions [] = {
    { "TestPythonCallAction", gnc_plugin_python_cmd_test_report, NULL, NULL, NULL },
    { "PythonTestExistingReportAction", gnc_plugin_python_open_exiting_report_tab, NULL, NULL, NULL },
    { "SamplePythonReportAction", gnc_plugin_python_cmd_test_report, NULL, NULL, NULL },
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
    /* Reference the  plugin to ensure it exists in the gtk type system. */
    GNC_TYPE_PLUGIN_PYTHON_MENU;

    /* Register html handlers */
    gnc_html_register_stream_handler (URL_TYPE_PYREPORT, gnc_python_report_stream_cb);
    gnc_html_register_url_handler (URL_TYPE_PYREPORT, gnc_python_report_url_cb);

    // create plugin and return it to be registered
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

/* PYREPORTS IMPL */

static gboolean
gnc_python_report_stream_cb (const char *location, char ** data, int *len)
{
    char *html, *error = NULL;
    // TODO: properly parse URL


    html = gnc_plugin_python_get_report_html(location, &error);

    if (html) {
        *data = html;
        *len = strlen(*data);
        return TRUE;
    } else {
        // include error text in the HTML output
        const char *fallback_fmt =
            "<html><body>"
            "<h1>Python Report Error</h1>"
            "<p>Failed to generate report.</p>"
            "<pre>%s</pre>"
            "</body></html>";

        if (error) {
            *data = g_strdup_printf(fallback_fmt, error);
            free(error);   // free malloc'd error string
        } else {
            *data = g_strdup("<html><body><h1>Python Report Error</h1>"
                             "<p>Failed to generate report.</p></body></html>");
        }

        *len = strlen(*data);
        return FALSE;
    }
}

// pyreport URL handler: mirror image of gnc_report_system_report_url_cb()
static gboolean
gnc_python_report_url_cb (const char *location, const char *label,
                                 gboolean new_window, GNCURLResult *result)
{
    g_return_val_if_fail (location != NULL, FALSE);
    g_return_val_if_fail (result != NULL, FALSE);

    /* make a new window if necessary */
    if (new_window)
    {
        char *url;

        url = gnc_build_url (URL_TYPE_PYREPORT, location, label);
        gnc_main_window_open_report_url (url, GNC_MAIN_WINDOW(result->parent));
        g_free (url);

        result->load_to_stream = FALSE;
    }
    else
    {
        result->load_to_stream = TRUE;
    }

    return TRUE;
}

void gnc_main_window_open_pyreport(const char *template_uuid, GncMainWindow *window) {
    GncPluginPage *reportPage;

    if (window) {
        g_return_if_fail(GNC_IS_MAIN_WINDOW(window));
    }

    // Ensure our GType is registered
    GNC_TYPE_PLUGIN_PAGE_PYREPORT;
    
    reportPage = gnc_plugin_page_pyreport_new(template_uuid);
    if (reportPage) {
        gnc_main_window_open_page( window, reportPage );

    }
}

/* PYTHON HTML FETCHING */


// menu action callback to run the Python report
static char*
gnc_plugin_python_get_report_html (const char *template_uuid, char **error)
{
    PyGILState_STATE gstate;
    PyObject *module, *function, *py_template_uuid, *result;
    char* finalResult = NULL;

    /* Acquire the GIL */
    gstate = PyGILState_Ensure();

    /* Import the pyreports module */
    module = PyImport_ImportModule("pyreports");
    if (module == NULL) {
        *error = pyerr_to_string();
        PyGILState_Release(gstate);
        return NULL;
    }

    /* Get the render_test_html function */
    function = PyObject_GetAttrString(module, "get_html_by_template_url");
    if (function == NULL || !PyCallable_Check(function)) {
        *error = pyerr_to_string();
        Py_DECREF(module);
        PyGILState_Release(gstate);
        return NULL;
    }

    /* Call the function */
    py_template_uuid = PyUnicode_FromString(template_uuid);
    if (!py_template_uuid) {
        const char *errMsg = "Failed to create py_template_uuid";
        *error = strdup(errMsg);
        Py_DECREF(function);
        Py_DECREF(module);
        PyGILState_Release(gstate);
        return NULL;
    }
    result = PyObject_CallOneArg(function, py_template_uuid);
    Py_DECREF(py_template_uuid);
    if (result == NULL) {
        *error = pyerr_to_string();
    } else {
        /* Convert result to string and copy to C string */
        PyObject* str_result = PyObject_Str(result);
        if (str_result) {
            const char* html_output = PyUnicode_AsUTF8(str_result);
            if (html_output) {
                finalResult = g_strdup(html_output);
            }
            Py_DECREF(str_result);
        }
        Py_DECREF(result);
    }

    /* Cleanup */
    Py_DECREF(function);
    Py_DECREF(module);

    /* Release the GIL */
    PyGILState_Release(gstate);

    return finalResult;
}

/* TEST ACTIONS */

// menu action callback to open an existing report
static void
gnc_plugin_python_open_exiting_report_tab(GSimpleAction *simple, GVariant *parameter, gpointer user_data) {
    (void)simple;
    (void)parameter;
    
    GncMainWindowActionData *mw = user_data;
    g_return_if_fail (mw != NULL);

    gnc_main_window_open_report(0, mw->window);
}

static void gnc_plugin_python_cmd_test_report (GSimpleAction *simple, GVariant *parameter, gpointer user_data) {
    (void)simple;
    (void)parameter;
    
    GncMainWindowActionData *mw = user_data;
    g_return_if_fail (mw != NULL);

    gnc_main_window_open_pyreport("50628fb4-7bdc-452f-bd9b-77b6649041a2", mw->window);
}


/* PYTHON STUFF */

// returns malloc'd string with full traceback; caller free()s it
static char *pyerr_to_string(void) {
    PyObject *ptype=NULL, *pvalue=NULL, *ptb=NULL;
    PyErr_Fetch(&ptype, &pvalue, &ptb);
    if (!ptype) return strdup("no Python error set");
    PyErr_NormalizeException(&ptype, &pvalue, &ptb);

    PyObject *tbmod = PyImport_ImportModule("traceback");
    if (!tbmod) { Py_XDECREF(ptype); Py_XDECREF(pvalue); Py_XDECREF(ptb); return strdup("traceback import failed"); }

    PyObject *list = PyObject_CallMethod(tbmod, "format_exception", "OOO", ptype, pvalue ? pvalue : Py_None, ptb ? ptb : Py_None);
    char *out = NULL;
    if (list) {
        PyObject *sep = PyUnicode_FromString("");
        PyObject *joined = sep ? PyUnicode_Join(sep, list) : NULL;
        if (joined) {
            const char *u = PyUnicode_AsUTF8(joined);
            if (u) out = strdup(u);
            Py_DECREF(joined);
        }
        Py_XDECREF(sep);
        Py_DECREF(list);
    }
    Py_DECREF(tbmod);
    Py_XDECREF(ptype); Py_XDECREF(pvalue); Py_XDECREF(ptb);

    return out ? out : strdup("unknown Python error");
}
