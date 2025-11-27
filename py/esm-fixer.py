import re
from pathlib import Path

# --- Configuration ---
# Set the root directory for TypeChain generated files.
ROOT_DIR = '../typechain-types/'

# --- Regex Definitions for Import Path Fixing ---

# R1: Pattern for `import * as Alias from "./path";` (or similar star/alias imports).
# Goal: Change to `import * as Alias from "./path/index.js";`
# The pattern ensures it captures the full import line and is non-greedy.
# Group 1: The start of the import statement up to the opening quote (e.g., `* as Factory from "`)
# Group 2: The relative path (e.g., `../typechain-types/Factory`)
# Note: Using negative lookbehind/lookahead might be complex; simple capture groups are safer here.
# We look for the common structure where a relative path is imported without extension/index.
PATTERN_INDEX_JS = re.compile(
    r'(^\s*import\s+\* as \w+\s+from\s+\")([.]{1,2}\/[^"]+)(\";)', 
    re.MULTILINE
)

# R2: Pattern for named imports that typically need a '.js' extension.
# E.g., `} from "../factories/MyContract__factory";` 
# Goal: Change to `} from "../factories/MyContract__factory.js";`
# Group 1: The start of the import statement up to the opening quote (e.g., `} from "`)
# Group 2: The relative path (e.g., `../factories/MyContract__factory`)
PATTERN_DOT_JS = re.compile(
    r'(\}\s+from\s+\")([.]{1,2}\/[^"]+)(?<!\.js|\/index)\";', 
    re.MULTILINE
)

print(f"Starting import path patching in '{Path(ROOT_DIR).resolve()}'")

# Recursively iterate over all files in the target directory
for path in Path(ROOT_DIR).rglob('*'):
    if path.is_file():
        # Only process TypeScript or JavaScript files
        if path.suffix not in ['.ts', '.js', '.d.ts']:
            continue
        
        try:
            # Read all file content efficiently
            content = path.read_text(encoding='utf-8')
            original_content = content
        except UnicodeDecodeError:
            # Skip non-text files
            print(f"Skipping non-text file: {path}")
            continue

        # --- FIX 1: Append /index.js for star/alias imports ---
        # Replacement uses captured groups: \g<1> (start) + \g<2> (path) + "/index.js" + \g<3> (semicolon)
        content = PATTERN_INDEX_JS.sub(r'\g<1>\g<2>/index.js\g<3>', content)

        # --- FIX 2: Append .js for other relative imports ---
        # Replacement uses captured groups: \g<1> (start) + \g<2> (path) + ".js" + \g<3> (semicolon)
        content = PATTERN_DOT_JS.sub(r'\g<1>\g<2>.js\g<3>', content)

        # Write back only if the content has changed
        if content != original_content:
            try:
                # Use Pathlib's write_text for a cleaner file write
                path.write_text(content, encoding='utf-8')
                print(f"Patched: {path.name}")
            except Exception as e:
                print(f"Error writing to file {path.name}: {e}")

print("Import path patching complete.")
