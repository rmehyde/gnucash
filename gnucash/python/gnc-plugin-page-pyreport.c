/**
 * gnc-plugin-page-pyreport.c -- A GncPlugin page for a Python report.
 *
 * Copyright (C) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, contact:
 *
 * Free Software Foundation           Voice:  +1-617-542-5942
 * 51 Franklin Street, Fifth Floor    Fax:    +1-617-542-2652
 * Boston, MA  02110-1301,  USA       gnu@gnu.org
 **/

#include <gtk/gtk.h>
#include <glib/gi18n.h>
#include <config.h>

#include "gnc-plugin-page-pyreport.h"
#include "gnucash/html/gnc-html-factory.h"
#include "gnucash/html/gnc-html.h"
#include "gnucash/html/gnc-html-extras.h"
#include "gnc-ui-util.h"
#include "gnc-ui.h"
#include "gnc-icons.h"
#include "gnc-session.h"

enum
{
    PROP_0,
    PROP_REPORT_UUID,
};

typedef struct GncPluginPagePyReportPrivate
{
    gchar *report_uuid;
    GncHtml *html;
    GtkContainer *container;
} GncPluginPagePyReportPrivate;

G_DEFINE_TYPE_WITH_PRIVATE(GncPluginPagePyReport, gnc_plugin_page_pyreport, GNC_TYPE_PLUGIN_PAGE)

#define GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(o)  \
   ((GncPluginPagePyReportPrivate*)gnc_plugin_page_pyreport_get_instance_private((GncPluginPagePyReport*)o))

static GObject *gnc_plugin_page_pyreport_constructor(GType this_type, guint n_properties, GObjectConstructParam *properties);
static void gnc_plugin_page_pyreport_finalize (GObject *object);
static void gnc_plugin_page_pyreport_get_property (GObject *object, guint prop_id, GValue *value, GParamSpec *pspec);
static void gnc_plugin_page_pyreport_set_property (GObject *object, guint prop_id, const GValue *value, GParamSpec *pspec);

static GtkWidget* gnc_plugin_page_pyreport_create_widget( GncPluginPage *plugin_page );
static void gnc_plugin_page_pyreport_destroy_widget( GncPluginPage *plugin_page );

static void
gnc_plugin_page_pyreport_class_init (GncPluginPagePyReportClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);
    GncPluginPageClass *gnc_plugin_page_class = GNC_PLUGIN_PAGE_CLASS (klass);

    object_class->constructor = gnc_plugin_page_pyreport_constructor;
    object_class->finalize = gnc_plugin_page_pyreport_finalize;
    object_class->set_property = gnc_plugin_page_pyreport_set_property;
    object_class->get_property = gnc_plugin_page_pyreport_get_property;

    gnc_plugin_page_class->tab_icon        = GNC_ICON_ACCOUNT_REPORT;
    gnc_plugin_page_class->plugin_name     = GNC_PLUGIN_PAGE_PYREPORT_NAME;
    gnc_plugin_page_class->create_widget   = gnc_plugin_page_pyreport_create_widget;
    gnc_plugin_page_class->destroy_widget  = gnc_plugin_page_pyreport_destroy_widget;

    g_object_class_install_property (object_class,
                                     PROP_REPORT_UUID,
                                     g_param_spec_string ("report-uuid",
                                                          _("Report UUID"),
                                                          _("The UUID of the Python report"),
                                                          NULL,
                                                          (GParamFlags)(G_PARAM_READWRITE | G_PARAM_CONSTRUCT_ONLY)));
}

static void
gnc_plugin_page_pyreport_init (GncPluginPagePyReport *plugin_page)
{
    (void)plugin_page;
}

static GObject *
gnc_plugin_page_pyreport_constructor(GType this_type, guint n_properties, GObjectConstructParam *properties)
{
    GObject *obj = G_OBJECT_CLASS (gnc_plugin_page_pyreport_parent_class)->constructor(this_type, n_properties, properties);
    
    g_object_set (G_OBJECT(obj),
                  "page-name", "Python Report",
                  NULL);
    
    gnc_plugin_page_add_book (GNC_PLUGIN_PAGE(obj), gnc_get_current_book());

    return obj;
}

static void
gnc_plugin_page_pyreport_finalize (GObject *object)
{
    GncPluginPagePyReportPrivate *priv = GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(object);
    
    g_free(priv->report_uuid);
    
    G_OBJECT_CLASS (gnc_plugin_page_pyreport_parent_class)->finalize (object);
}

static void
gnc_plugin_page_pyreport_get_property (GObject *object, guint prop_id, GValue *value, GParamSpec *pspec)
{
    GncPluginPagePyReportPrivate *priv = GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(object);

    switch (prop_id)
    {
    case PROP_REPORT_UUID:
        g_value_set_string (value, priv->report_uuid);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
}

static void
gnc_plugin_page_pyreport_set_property (GObject *object, guint prop_id, const GValue *value, GParamSpec *pspec)
{
    GncPluginPagePyReportPrivate *priv = GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(object);

    switch (prop_id)
    {
    case PROP_REPORT_UUID:
        g_free(priv->report_uuid);
        priv->report_uuid = g_value_dup_string (value);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
}

static GtkWidget*
gnc_plugin_page_pyreport_create_widget( GncPluginPage *plugin_page )
{
    GncPluginPagePyReport *pyreport;
    GncPluginPagePyReportPrivate *priv;
    GtkWindow *topLvl;
    char *url;

    pyreport = GNC_PLUGIN_PAGE_PYREPORT(plugin_page);
    priv = GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(pyreport);
    
    topLvl = gnc_ui_get_main_window (NULL);
    priv->html = gnc_html_factory_create_html();
    gnc_html_set_parent( priv->html, topLvl );

    priv->container = GTK_CONTAINER(gtk_frame_new(NULL));
    gtk_frame_set_shadow_type(GTK_FRAME(priv->container), GTK_SHADOW_NONE);
    gtk_widget_set_name (GTK_WIDGET(priv->container), "gnc-id-pyreport-page");
    
    gtk_container_add(GTK_CONTAINER(priv->container),
                      gnc_html_get_widget(priv->html));

    url = g_strdup_printf("pyreport:uuid=%s", priv->report_uuid);
    gnc_html_show_url(priv->html, URL_TYPE_PYREPORT, url, NULL, 0);
    g_free(url);
    
    gtk_widget_show_all(GTK_WIDGET(priv->container));

    return GTK_WIDGET(priv->container);
}

static void
gnc_plugin_page_pyreport_destroy_widget( GncPluginPage *plugin_page )
{
    GncPluginPagePyReportPrivate *priv = GNC_PLUGIN_PAGE_PYREPORT_GET_PRIVATE(plugin_page);
    
    if (priv->html)
    {
        g_object_unref(G_OBJECT(priv->html));
        priv->html = NULL;
    }
}

GncPluginPage *
gnc_plugin_page_pyreport_new( const char *report_uuid )
{
    return GNC_PLUGIN_PAGE(g_object_new(GNC_TYPE_PLUGIN_PAGE_PYREPORT,
                                       "report-uuid", report_uuid,
                                       NULL));
}