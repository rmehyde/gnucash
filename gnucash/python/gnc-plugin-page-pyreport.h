/**
 * gnc-plugin-page-pyreport.h -- A GncPlugin page for a Python report.
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

#ifndef __GNC_PLUGIN_PAGE_PYREPORT_H
#define __GNC_PLUGIN_PAGE_PYREPORT_H

#include <gtk/gtk.h>
#include "gnc-plugin-page.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define GNC_TYPE_PLUGIN_PAGE_PYREPORT            (gnc_plugin_page_pyreport_get_type ())
#define GNC_PLUGIN_PAGE_PYREPORT(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), GNC_TYPE_PLUGIN_PAGE_PYREPORT, GncPluginPagePyReport))
#define GNC_PLUGIN_PAGE_PYREPORT_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass), GNC_TYPE_PLUGIN_PAGE_PYREPORT, GncPluginPagePyReportClass))
#define GNC_IS_PLUGIN_PAGE_PYREPORT(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GNC_TYPE_PLUGIN_PAGE_PYREPORT))
#define GNC_IS_PLUGIN_PAGE_PYREPORT_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass), GNC_TYPE_PLUGIN_PAGE_PYREPORT))
#define GNC_PLUGIN_PAGE_PYREPORT_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj), GNC_TYPE_PLUGIN_PAGE_PYREPORT, GncPluginPagePyReportClass))

#define GNC_PLUGIN_PAGE_PYREPORT_NAME "GncPluginPagePyReport"

typedef struct
{
    GncPluginPage gnc_plugin;
} GncPluginPagePyReport;

typedef struct
{
    GncPluginPageClass gnc_plugin;
} GncPluginPagePyReportClass;

GType gnc_plugin_page_pyreport_get_type( void );

GncPluginPage *gnc_plugin_page_pyreport_new( const char *report_uuid );

#ifdef __cplusplus
}
#endif

#endif /* __GNC_PLUGIN_PAGE_PYREPORT_H */