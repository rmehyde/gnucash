# reports.py
from __future__ import annotations

import abc
import sys
from abc import ABC
from typing import Dict, Type
from uuid import UUID

_TEMPLATE_REGISTRY: Dict[UUID, Type[Report]] = {}


def get_html_by_template_url(template_url: str) -> str:
    prefix = "pyreport:uuid="
    if not template_url.startswith(prefix):
        raise ValueError(f"Expected template_url '{template_url}' to start with '{prefix}'")

    template_id = template_url[len(prefix):].strip()
    try:
        uuid = UUID(template_id)
    except ValueError as e:
        raise ValueError(f"Failed to create UUID from input '{template_id}'") from e
    report_class = _TEMPLATE_REGISTRY[uuid]
    report = report_class()
    return report.html()


class Report(ABC):
    """base report; subclasses auto-register via __init_subclass__"""
    template_uuid: UUID

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)

        # don't register the abstract base class itself
        if cls is Report:
            return

        # validate and register
        template_id = getattr(cls, "template_id", None)
        print(f"Registering template ID {template_id}", file=sys.stderr)
        sys.stderr.flush()
        if not template_id:
            raise TypeError(f"{cls.__name__} must define class attribute 'template_uuid'")
        if template_id in _TEMPLATE_REGISTRY:
            raise KeyError(f"Template ID {template_id} already registered by {_TEMPLATE_REGISTRY[template_id].__name__}")
        _TEMPLATE_REGISTRY[template_id] = cls

    @abc.abstractmethod
    def html(self) -> str:
        raise NotImplementedError()
