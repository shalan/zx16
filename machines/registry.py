"""Machine registry — maps logical names to packages."""

from __future__ import annotations

from dataclasses import dataclass
from importlib import import_module
from pathlib import Path
from typing import Any, Type

MACHINES_ROOT = Path(__file__).resolve().parent

# logical name -> python package folder under machines/
_ALIASES = {
    "su26": "su26",
    "su26-ext": "su26_ext",
    "su26_ext": "su26_ext",
}


@dataclass
class MachineInfo:
    name: str
    package: str
    yaml_path: Path
    sim_module: str
    sim_class: str
    cc_module: str


def list_machines() -> list[str]:
    return sorted(set(_ALIASES.keys()) - {"su26_ext"})  # prefer hyphenated public name


def resolve(name: str) -> MachineInfo:
    key = name.strip().lower()
    if key not in _ALIASES:
        raise KeyError(f"unknown machine {name!r}; choose from {list_machines()}")
    pkg = _ALIASES[key]
    yaml_path = MACHINES_ROOT / pkg / "machine.yaml"
    # public name prefers hyphen form
    public = "su26-ext" if pkg == "su26_ext" else pkg
    return MachineInfo(
        name=public,
        package=pkg,
        yaml_path=yaml_path,
        sim_module=f"machines.{pkg}.simulator.sim",
        sim_class="Su26ExtSim" if pkg == "su26_ext" else "Su26Sim",
        cc_module=f"machines.{pkg}.cc.target",
    )


def load_sim_class(name: str) -> Type[Any]:
    info = resolve(name)
    mod = import_module(info.sim_module)
    return getattr(mod, info.sim_class)


def load_cc_target(name: str) -> Any:
    info = resolve(name)
    return import_module(info.cc_module)
