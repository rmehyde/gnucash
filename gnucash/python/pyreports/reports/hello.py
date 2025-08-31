from textwrap import dedent
from uuid import UUID

from pyreports.pyreport import Report


class HelloReport(Report):
    template_id = UUID("50628fb4-7bdc-452f-bd9b-77b6649041a2")

    def html(self) -> str:
        return dedent("""
        <html>
            <body>
                <h1>Python Test Report</h1>
                This "report" is rendered as hardcoded HTML from HelloReport
            </body>
        </html>
        """).strip()
