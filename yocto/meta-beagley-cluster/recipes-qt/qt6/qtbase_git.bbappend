# MapLibre Native uses QtLocation's offline/cache database path on the target.
# Build the SQLite SQL driver into qtbase-plugins so the renderer does not boot
# with repeated "SQLite driver not found" warnings.
PACKAGECONFIG:append:class-target = " sql-sqlite"
