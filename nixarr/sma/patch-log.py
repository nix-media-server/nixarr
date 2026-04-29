"""Patch log.py to redirect all writable paths out of the nix store.

Takes two args: <log.py path> <writable log dir>
The log dir should be a directory writable by all SMA-invoking users (e.g. via
group permissions on the media group).
"""
import sys

path = sys.argv[1]
log_dir = sys.argv[2]

with open(path) as f:
    content = f.read()

# Redirect logpath from configpath (in nix store) to the provided log dir
content = content.replace(
    "logpath = configpath",
    f"logpath = '{log_dir}'",
)

# Also redirect the logging.ini configfile lookup to the log dir
content = content.replace(
    "configfile = os.path.abspath(os.path.join(configpath, CONFIG_DEFAULT))",
    "configfile = os.path.abspath(os.path.join(logpath, CONFIG_DEFAULT))",
)

# Before checkLoggingConfig call, seed the default logging.ini if missing
content = content.replace(
    "    checkLoggingConfig(configfile)\n",
    "    if not os.path.exists(configfile):\n"
    "        import shutil as _shutil\n"
    "        _default = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', 'logging.ini.default')\n"
    "        _shutil.copy2(_default, configfile)\n"
    "    checkLoggingConfig(configfile)\n",
)

with open(path, "w") as f:
    f.write(content)
