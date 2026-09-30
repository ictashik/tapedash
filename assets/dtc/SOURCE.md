# Fault-code descriptions

`dtc.json` maps a diagnostic trouble code (`P0420`) to one line of plain English.

**Where it comes from.** It is written from scratch for this project. The codes are
the standard SAE J2012 / ISO 15031-6 identifiers, which are public facts about how
OBD-II works. The wording is our own: short, plain sentences describing what each
code says, not copied or adapted from any database, manual or website. Nothing here is
under a third-party licence, and the file is released with the rest of the project.

**What it covers.** The common generic powertrain codes (fuel and air metering,
oxygen sensors, injectors, misfires, ignition, crank and cam sensors, emissions and
EVAP, idle and speed, computer faults, transmission) and a few network (`U`) and
chassis (`C`) ones. It is deliberately not exhaustive.

**What it does not cover.** Manufacturer-specific codes (`P1xxx`, `P3xxx`, most
`B`, `C` and `U` codes) mean different things on different cars. For those, and for
any generic code missing here, the app says which system the code belongs to and to
look it up for the car, and never guesses a description.

**Adding to it.** Write the description yourself from the code's meaning; do not paste
from another source. Keep one short line, name the part and the fault, and keep the
file sorted by code.
