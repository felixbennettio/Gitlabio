"""Retry dependency transport failures, never source/compiler/test failures."""
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
download = re.search(r"Could not (?:GET|HEAD|get resource|download)|Downloading from .+ failed", text)
transport = re.search(r"Remote host terminated the handshake|SocketTimeoutException|Read timed out|Connection (?:reset|timed out)|Connect timed out", text)
code_failure = re.search(r"Compilation error|^e: |There were failing tests|[0-9]+ tests completed, [1-9][0-9]* failed", text, re.MULTILINE)
sys.exit(0 if download and transport and not code_failure else 1)
