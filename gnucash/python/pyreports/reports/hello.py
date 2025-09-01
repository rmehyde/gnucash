import sys
from textwrap import dedent, indent
from uuid import UUID

from pyreports.pyreport import Report

import gnucash
from gnucash import _sw_app_utils
from gnucash import app_utils


def get_current_account_balances() -> dict[str, str]:
    session = app_utils.gnc_get_current_session()
    book = session.book
    root_account = book.get_root_account()
    balances = {}
    for acct in root_account.get_children():
        cmdty = acct.GetCommodity()
        symbol = cmdty.get_nice_symbol()
        balance = float(acct.GetPresentBalanceInCurrency(cmdty, True))
        balances[acct.GetName()] = f"{symbol}{balance:,.2f}"
    return balances

class HelloReport(Report):
    template_id = UUID("50628fb4-7bdc-452f-bd9b-77b6649041a2")

    @staticmethod
    def _balances_to_html(balances: dict[str, str]) -> str:
        """return an HTML table of account balances"""
        rows = "\n".join(
            f"""<tr><td style="font-weight: bold">{acct}</td><td style="text-align:right">{bal}</td></tr>"""
            for acct, bal in balances.items()
        )
        return dedent(f"""
        <table border="1" cellpadding="4" cellspacing="0">
          <thead style="background-color:#c2dfff">
              <tr><th>Account</th><th>Balance</th></tr>
          </thead>
          <tbody>
              {rows}
          </tbody>
        </table>
        """).strip()


    def html(self) -> str:
        balances = get_current_account_balances()
        table_html = self.balances_to_html(balances)
        return dedent(f"""
        <html>
            <body>
                <h1>Python Test Report: Top-Level Balances</h1>
                This report is generated from Python code.<br><br>
                {indent(table_html, "                ")}
            </body>
        </html>
        """).strip()
